// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';

/// Severity level emitted by Debug Advisor rule heuristics.
///
/// Open-core ships the enum so the no-op default and the Pro
/// implementation can return the same shape of result without forking
/// the sort / display / filter UI in the panel.
enum DebugAdvisorSeverity { info, warning, error }

/// Identifier for the rule family that produced a [DebugAdvisorSuggestion].
///
/// Open-core declares the four rule families. Adding a new rule
/// family is an open-core change (the picker UI / panel filters key on
/// these IDs) and is followed by the Pro overlay shipping the
/// implementation.
enum DebugAdvisorRuleId {
  /// X-propagation chain: signals in the same scope went X within a small
  /// temporal window of the focus signal's X transition.
  xPropagationChain,

  /// Clock-domain crossing indicator: a transition on signal A on edge of
  /// clock C1 is immediately followed by a transition on signal B on
  /// edge of a different clock C2 with no synchronizer chain between
  /// them.
  clockDomainCrossing,

  /// Stuck-at detection: signal held the same value for ≥ M% of the
  /// loaded time window despite having a non-trivial bit width.
  stuckAt,

  /// Setup/hold timing-violation hint: a data signal transitioned within
  /// K simulation ticks of its associated clock edge.
  timingViolation,
}

/// One concrete suggestion produced by a Debug Advisor rule.
///
/// Pure-Dart immutable model so open-core ships it as part of the seam
/// (the suggestions panel and the `NoopDebugAdvisorService` both depend on
/// it without pulling in any Pro implementation).
///
/// NAMING INVARIANT: the feature is called "Debug Advisor" — never "AI
/// Debug", which is a legacy name that survives nowhere. The Pro overlay's
/// implementation lives at `lib/services/debug_advisor/` (renamed from the
/// legacy `lib/services/ai_debug/` folder); symbol names, log channels, ARB
/// keys, and user-visible strings all use "Debug Advisor".
@immutable
class DebugAdvisorSuggestion {
  const DebugAdvisorSuggestion({
    required this.ruleId,
    required this.severity,
    required this.confidence,
    required this.labelArbKey,
    required this.explanationArbKey,
    required this.affectedSignals,
    required this.affectedTimeRangeStart,
    required this.affectedTimeRangeEnd,
    this.placeholders = const <String, String>{},
  });

  /// The rule family that produced this suggestion.
  final DebugAdvisorRuleId ruleId;

  /// Severity tier (info / warning / error) for grouping in the panel.
  final DebugAdvisorSeverity severity;

  /// Heuristic confidence in the range `[0.0, 1.0]`. Higher values rank
  /// higher in the panel ordering. Implementations must clamp before
  /// returning.
  final double confidence;

  /// ARB key (resolved by the panel via `L10NPro`) for the short
  /// human-readable label of this suggestion.
  final String labelArbKey;

  /// ARB key for the longer templated explanation. Placeholders are filled
  /// from [placeholders] at render time.
  final String explanationArbKey;

  /// Signal refs the user should examine. The first entry is conventionally
  /// the focus signal that triggered the rule.
  final List<String> affectedSignals;

  /// Inclusive start of the time range the suggestion calls attention to,
  /// in simulation ticks.
  final int affectedTimeRangeStart;

  /// Exclusive end of the time range, in simulation ticks. May equal
  /// [affectedTimeRangeStart] for point-in-time suggestions.
  final int affectedTimeRangeEnd;

  /// Substitution values for the [explanationArbKey] template (signal names,
  /// numeric thresholds, time deltas, etc.). Already resolved to display
  /// strings by the rule (so the panel does not need to format times or
  /// look up signal labels).
  final Map<String, String> placeholders;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DebugAdvisorSuggestion &&
          ruleId == other.ruleId &&
          severity == other.severity &&
          confidence == other.confidence &&
          labelArbKey == other.labelArbKey &&
          explanationArbKey == other.explanationArbKey &&
          _listEquals(affectedSignals, other.affectedSignals) &&
          affectedTimeRangeStart == other.affectedTimeRangeStart &&
          affectedTimeRangeEnd == other.affectedTimeRangeEnd &&
          _mapEquals(placeholders, other.placeholders);

  @override
  int get hashCode => Object.hash(
    ruleId,
    severity,
    confidence,
    labelArbKey,
    explanationArbKey,
    affectedTimeRangeStart,
    affectedTimeRangeEnd,
    affectedSignals.length,
  );

  @override
  String toString() =>
      'DebugAdvisorSuggestion(rule: $ruleId, '
      'severity: $severity, confidence: ${confidence.toStringAsFixed(2)}, '
      'signals: ${affectedSignals.length}, '
      'range: [$affectedTimeRangeStart, $affectedTimeRangeEnd))';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (b[key] != a[key]) return false;
  }
  return true;
}

/// Open-core extension point producing Debug Advisor suggestions.
///
/// Open-core ships [NoopDebugAdvisorService] (in
/// `lib/services/debug_advisor/`) which always returns an empty list. The
/// closed-source Pro overlay overrides
/// `debugAdvisorServiceProvider` with a heuristic rule engine implementing
/// the four rule families (X-propagation, clock-domain crossing,
/// stuck-at, timing violation).
///
/// Implementations must be pure: same `(source, cursorTime, focusSignal)`
/// triple → same suggestions. No persistent state, no network access, no
/// LLM/model inference.
// ignore: one_member_abstracts
abstract class DebugAdvisorService {
  /// Run every registered rule against the loaded waveform and return the
  /// set of suggestions for the cursor at [cursorTime].
  ///
  /// [focusSignalRef] is optional context: if non-null, rules may
  /// prioritize work that touches the user's currently-selected signal.
  /// [hierarchy] is the design hierarchy (used by rules that need to
  /// enumerate sibling signals); pass [WaveformDataSource.rootScopes].
  List<DebugAdvisorSuggestion> analyze({
    required WaveformDataSource source,
    required List<Scope> hierarchy,
    required int cursorTime,
    String? focusSignalRef,
  });
}
