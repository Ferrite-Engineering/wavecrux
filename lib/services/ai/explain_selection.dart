// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Pure logic for the open-core, non-agentic **Explain Selection** feature:
/// the model request shape, the citation grammar + parser, and the resolver
/// that grounds each citation against the loaded trace.
///
/// No model and no Flutter: this is the testable core. The provider/controller
/// drives it; the panel renders the parsed segments.

// ── Request building ─────────────────────────────────────────────────────────

/// Citation grammar the model is instructed to use, and which
/// [parseExplanation] recognizes:
///
/// - `[[cite:signal=<signalRefOrPath>,time=<tick>]]` — a signal at a tick.
/// - `[[cite:time=<tick>]]` — a moment / decoded transaction.
///
/// The model must only cite `signalRef`/`path` and `time` values present in the
/// supplied context; [resolveExplainCitation] independently re-verifies every
/// citation against the live trace, so a hallucinated coordinate is caught and
/// surfaced as "could not locate" rather than producing a wrong jump.
const String explainCitationSyntaxDoc =
    '[[cite:signal=<signalRefOrPath>,time=<tick>]] or [[cite:time=<tick>]]';

/// The system instruction sent to the model. Not user-facing UI (it is a prompt
/// to the BYO model), so it is intentionally not localized.
const String _explainSystemPrompt =
    "You are WaveCrux's waveform signal-explanation assistant. You are given a "
    "compact JSON snapshot of a user's selection: signals, their value at the "
    'window start, their transitions in the window, any decoded protocol '
    'transactions, and an X-origin trace when a signal is unknown (X). '
    'Explain, in a few short sentences for a hardware engineer, what is '
    'happening in this selection.\n\n'
    'GROUND EVERYTHING, HALLUCINATE NOTHING. Every substantive claim must cite '
    'a concrete coordinate from the supplied context using this exact syntax: '
    '$explainCitationSyntaxDoc. Only cite signalRef/path and tick values that '
    'appear in the context. Do not invent times or signals. Prefer citing the '
    'transition or transaction that supports each statement. Be concise.';

/// Builds the single, non-agentic [AiRequest] for an Explain Selection call.
///
/// [context] is the structured map produced by the open-core
/// `getSelectionContext` tool. No tools are offered to the model (`tools: []`),
/// so this is a one-shot completion — never a tool loop.
AiRequest buildExplainSelectionRequest(Map<String, Object?> context) {
  return AiRequest(
    messages: [
      const AiMessage.system(_explainSystemPrompt),
      AiMessage.user(
        'Explain this selection. Respond with the explanation only.\n\n'
        '```json\n${jsonEncode(context)}\n```',
      ),
    ],
  );
}

// ── Parsing ──────────────────────────────────────────────────────────────────

/// One segment of a parsed explanation: either plain [ExplainText] or an
/// [ExplainCitation] that renders as a clickable affordance.
@immutable
sealed class ExplainSegment {
  const ExplainSegment();
}

/// A run of plain text between citations.
final class ExplainText extends ExplainSegment {
  const ExplainText(this.text);

  /// The literal text run.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ExplainText && text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ExplainText(${text.length} chars)';
}

/// A parsed citation token. [signal] is the raw signalRef-or-path the model
/// emitted (resolved later); [time] is the cited tick. At least one is non-null.
/// [raw] is the original token text, shown in the "could not locate" tooltip.
@immutable
final class ExplainCitation extends ExplainSegment {
  const ExplainCitation({required this.raw, this.signal, this.time});

  /// Raw signalRef or hierarchical path the model cited, if any.
  final String? signal;

  /// Cited simulation tick, if any.
  final int? time;

  /// The original `[[cite:…]]` token, for diagnostics / tooltip.
  final String raw;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExplainCitation &&
          signal == other.signal &&
          time == other.time &&
          raw == other.raw;

  @override
  int get hashCode => Object.hash(signal, time, raw);

  @override
  String toString() => 'ExplainCitation(signal: $signal, time: $time)';
}

final RegExp _citationPattern = RegExp(r'\[\[cite:([^\]]*)\]\]');

/// Parses a model explanation string into an ordered list of [ExplainSegment]s,
/// splitting out every `[[cite:…]]` token into an [ExplainCitation].
///
/// Malformed tokens (no recognizable `signal`/`time`) still become an
/// [ExplainCitation] with both fields null — the resolver will report it as
/// unresolvable rather than the parser silently dropping it.
List<ExplainSegment> parseExplanation(String raw) {
  final segments = <ExplainSegment>[];
  var cursor = 0;
  for (final match in _citationPattern.allMatches(raw)) {
    if (match.start > cursor) {
      segments.add(ExplainText(raw.substring(cursor, match.start)));
    }
    segments.add(_parseCitation(match.group(0)!, match.group(1) ?? ''));
    cursor = match.end;
  }
  if (cursor < raw.length) {
    segments.add(ExplainText(raw.substring(cursor)));
  }
  return segments;
}

ExplainCitation _parseCitation(String raw, String body) {
  String? signal;
  int? time;
  for (final part in body.split(',')) {
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    final key = part.substring(0, eq).trim();
    final value = part.substring(eq + 1).trim();
    switch (key) {
      case 'signal':
        if (value.isNotEmpty) signal = value;
      case 'time':
        time = int.tryParse(value);
    }
  }
  return ExplainCitation(raw: raw, signal: signal, time: time);
}

// ── Resolution (grounding) ───────────────────────────────────────────────────

/// The result of grounding an [ExplainCitation] against the loaded trace.
///
/// A [resolved] citation carries a concrete jump target (a [time] to place the
/// cursor at, and optionally a [signalRef]/[signalPath]/[variable] to select).
/// An unresolved citation carries no target — the UI renders it as a
/// non-clickable "could not locate" affordance, never a wrong jump.
@immutable
class ExplainCitationResolution {
  const ExplainCitationResolution.resolved({
    this.time,
    this.signalRef,
    this.signalPath,
    this.variable,
  }) : resolved = true;

  const ExplainCitationResolution.unresolved()
    : resolved = false,
      time = null,
      signalRef = null,
      signalPath = null,
      variable = null;

  /// Whether the citation grounded to a real coordinate.
  final bool resolved;

  /// The tick to jump the cursor to, if the citation carried a (valid) time.
  final int? time;

  /// The resolved signal ref to select, if the citation named a real signal.
  final String? signalRef;

  /// The resolved full path of the signal, if any.
  final String? signalPath;

  /// The resolved [Variable], if the citation named a real signal (used to add
  /// it to the view if it is not already shown).
  final Variable? variable;
}

/// Grounds [citation] against the loaded trace.
///
/// Resolution rules (a citation must reference at least a signal or a time):
/// - A named signal must exist in [variablesByRef] (by ref or full path).
/// - A cited time must fall within `[source.startTime, source.endTime]`.
/// - Both present → both must hold.
///
/// Any failure (no source, unknown signal, out-of-range time, empty citation)
/// returns [ExplainCitationResolution.unresolved] so the caller surfaces a
/// "could not locate" affordance instead of jumping somewhere wrong.
ExplainCitationResolution resolveExplainCitation(
  ExplainCitation citation, {
  required WaveformDataSource? source,
  required Map<String, Variable> variablesByRef,
  List<ActiveDecoder> decoders = const [],
}) {
  if (source == null) return const ExplainCitationResolution.unresolved();
  if (citation.signal == null && citation.time == null) {
    return const ExplainCitationResolution.unresolved();
  }

  Variable? variable;
  if (citation.signal != null) {
    variable =
        variablesByRef[citation.signal] ??
        _byFullPath(variablesByRef, citation.signal!);
    if (variable == null) {
      return const ExplainCitationResolution.unresolved();
    }
  }

  int? time;
  if (citation.time != null) {
    final t = citation.time!;
    if (t < source.startTime || t > source.endTime) {
      return const ExplainCitationResolution.unresolved();
    }
    time = t;
  }

  return ExplainCitationResolution.resolved(
    time: time,
    signalRef: variable?.signalRef,
    signalPath: variable?.fullPath,
    variable: variable,
  );
}

Variable? _byFullPath(Map<String, Variable> variablesByRef, String path) {
  for (final v in variablesByRef.values) {
    if (v.fullPath == path) return v;
  }
  return null;
}
