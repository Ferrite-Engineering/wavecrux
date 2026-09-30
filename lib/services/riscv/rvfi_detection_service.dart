// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// One parsed `rvfi_*` signal name.
class RvfiNameMatch {
  const RvfiNameMatch({
    required this.channel,
    required this.channelIndex,
    required this.namePrefix,
    required this.exact,
  });

  /// Which RVFI channel the name resolved to.
  final RvfiChannel channel;

  /// Retirement channel index (`rvfi_valid[1]` → 1). 0 for single-issue.
  final int channelIndex;

  /// Leaf-name prefix before the `rvfi_` token (`core0_rvfi_valid` →
  /// `core0_`), empty for a canonical name.
  final String namePrefix;

  /// True when the leaf name is the bare canonical port name — no prefix, no
  /// `_i` / `_o` suffix, no index. Used only to grade match confidence.
  final bool exact;
}

/// Recognizes the riscv-formal RVFI bundle in a loaded trace by name pattern
/// and returns a typed binding set plus a completeness report.
///
/// Detection is deliberately *pattern* based rather than heuristic: a name
/// either resolves to a known [RvfiChannel] or it does not participate. The
/// three real-world spellings are handled explicitly —
///
/// - **hierarchy-prefixed** — `top.cpu.rvfi_valid`. Handled for free, since
///   detection matches on the leaf [Variable.name] and groups by
///   [Variable.scopePath]; a trace holding two instrumented cores yields two
///   candidate scopes and the more complete one wins.
/// - **flattened prefix** — `core0_rvfi_valid`, produced when a wrapper
///   flattens the hierarchy into the signal name.
/// - **`_i` / `_o` suffix** — `rvfi_valid_o`, produced when the ports are
///   declared on a module boundary.
/// - **multi-channel** — `rvfi_valid[1]` / `rvfi_valid_1`, the superscalar
///   form, bound as independent retirement channels.
///
/// A *packed* superscalar bundle (one wide `rvfi_valid` carrying `NRET` bits)
/// is detected but **not** sliced: the report raises
/// [RvfiCompletenessReport.packedVectorSuspected] instead. Binding channel 0
/// to a packed vector would mis-attribute every retirement, and a wrong
/// answer here is worse than an honest refusal.
///
/// Structurally this mirrors `BoardAutoBindService`: pure Dart, takes the
/// available-signal map plus the existing bindings, and returns candidates
/// carrying a match tier and a human-readable reason. It is the second
/// open-core [StageAutoBindService] implementation, and the reason that seam
/// exists — the affordance used to be hard-gated to compound board widgets.
class RvfiDetectionService implements StageAutoBindService {
  const RvfiDetectionService();

  /// Parses one leaf signal name into an [RvfiNameMatch], or null when the
  /// name is not an RVFI port.
  ///
  /// Suffix and index stripping are applied repeatedly until the name stops
  /// changing, so `rvfi_valid_o[1]` and `rvfi_valid[1]_o` both resolve.
  static RvfiNameMatch? parseName(String rawName) {
    var name = rawName.toLowerCase().trim();
    if (!name.contains('rvfi_')) return null;

    final original = name;
    var index = 0;
    var sawIndex = false;
    var sawSuffix = false;

    var changed = true;
    while (changed) {
      changed = false;
      // `_i` / `_o` port-direction suffix. Stripped only while an `rvfi_`
      // token survives, so an unrelated `_o`-suffixed signal is never
      // chewed down into something that accidentally matches.
      if (name.endsWith('_i') || name.endsWith('_o')) {
        final stripped = name.substring(0, name.length - 2);
        if (stripped.contains('rvfi_')) {
          name = stripped;
          sawSuffix = true;
          changed = true;
        }
      }
      // `[N]` bracketed index.
      if (name.endsWith(']')) {
        final open = name.lastIndexOf('[');
        if (open > 0) {
          final inner = name.substring(open + 1, name.length - 1);
          final parsed = int.tryParse(inner);
          if (parsed != null) {
            index = parsed;
            sawIndex = true;
            name = name.substring(0, open);
            changed = true;
          }
        }
      }
      // `_N` trailing-underscore index — only when what remains still
      // resolves to a channel, so `rvfi_rs1_addr` never loses its `_addr`.
      final underscore = name.lastIndexOf('_');
      if (underscore > 0 && underscore < name.length - 1) {
        final tail = name.substring(underscore + 1);
        final parsed = int.tryParse(tail);
        if (parsed != null) {
          final stripped = name.substring(0, underscore);
          if (_channelForTail(stripped) != null) {
            index = parsed;
            sawIndex = true;
            name = stripped;
            changed = true;
          }
        }
      }
    }

    final channel = _channelForTail(name);
    if (channel == null) return null;

    final prefix = name.substring(0, name.length - channel.signalName.length);
    return RvfiNameMatch(
      channel: channel,
      channelIndex: index,
      namePrefix: prefix,
      exact: prefix.isEmpty && !sawIndex && !sawSuffix && original == name,
    );
  }

  /// Detects the best RVFI bundle in [availableSignals].
  ///
  /// When more than one bundle is present (a multi-core trace, or a design
  /// that exposes both a wrapper's and the core's ports) the bundle covering
  /// the most channels wins; ties break on the shorter scope path and then
  /// lexicographically, so the answer is stable across runs.
  RvfiDetectionResult detect(Map<String, Variable> availableSignals) {
    final groups = <String, _Bundle>{};

    // Deterministic order, shortest leaf name first, so a design exposing
    // both `rvfi_valid` and `rvfi_valid_o` always binds the canonical
    // spelling rather than whichever the map happened to yield first.
    final signals = availableSignals.values.toList()
      ..sort((a, b) {
        final byLength = a.name.length.compareTo(b.name.length);
        if (byLength != 0) return byLength;
        return a.name.compareTo(b.name);
      });

    for (final v in signals) {
      final match = parseName(v.name);
      if (match == null) continue;
      final key = '${v.scopePath}\x00${match.namePrefix}';
      groups
          .putIfAbsent(
            key,
            () => _Bundle(scopePath: v.scopePath, namePrefix: match.namePrefix),
          )
          .add(match, v);
    }

    if (groups.isEmpty) return RvfiDetectionResult.none;

    final ordered = groups.values.toList()
      ..sort((a, b) {
        final byCount = b.channelsFound.compareTo(a.channelsFound);
        if (byCount != 0) return byCount;
        final byDepth = a.scopePath.length.compareTo(b.scopePath.length);
        if (byDepth != 0) return byDepth;
        return a.scopePath.compareTo(b.scopePath);
      });
    final best = ordered.first;

    final found = best.refs.keys.toSet();
    final missing = RvfiChannel.values.toSet().difference(found);
    final RvfiBindingCompleteness completeness;
    if (RvfiChannel.values.any((c) => c.isRequired && !found.contains(c))) {
      completeness = RvfiBindingCompleteness.unusable;
    } else if (missing.isEmpty) {
      completeness = RvfiBindingCompleteness.full;
    } else {
      completeness = RvfiBindingCompleteness.reduced;
    }

    return RvfiDetectionResult(
      bindings: RvfiBindingSet(
        refs: {
          for (final entry in best.refs.entries)
            entry.key: Map<int, String>.unmodifiable(entry.value),
        },
        channelCount: best.channelCount,
        scopePath: best.scopePath,
        namePrefix: best.namePrefix,
      ),
      report: RvfiCompletenessReport(
        found: found,
        missing: missing,
        completeness: completeness,
        channelCount: best.channelCount,
        packedVectorSuspected: best.packedVectorSuspected,
        candidateScopes: [for (final b in ordered) b.scopePath],
      ),
    );
  }

  // ── StageAutoBindService ──────────────────────────────────────────────────

  /// Maps the detected bundle onto the widget's declared pins.
  ///
  /// Pin naming convention: the canonical channel name for a single-issue
  /// core (`rvfi_valid`), and the indexed form (`rvfi_valid[1]`) for the
  /// additional retirement channels of a multi-issue one. A declared pin the
  /// trace does not carry is returned as a `noMatch` candidate rather than
  /// dropped, so the preview dialog shows the user what is missing.
  @override
  BoardAutoBindResult autoBind({
    required StageWidget widget,
    required Map<String, Variable> availableSignals,
    Map<String, StageSignalBinding> existingBindings = const {},
    Map<String, Object?> configuration = const {},
  }) {
    final result = detect(availableSignals);
    final candidates = <String, BoardAutoBindCandidate>{};
    final pins = <String>[
      for (final b in widget.requiredSignals)
        if (b.isVisibleIn(configuration)) b.name,
      for (final b in widget.optionalSignals)
        if (b.isVisibleIn(configuration)) b.name,
    ];

    for (final pin in pins) {
      // Never overwrite a binding the user made by hand.
      final existing = existingBindings[pin];
      if (existing != null && existing.signalRef.isNotEmpty) {
        candidates[pin] = BoardAutoBindCandidate(
          confidence: BoardAutoBindConfidence.exactMatch,
          matchReason: 'manually bound',
          binding: existing,
        );
        continue;
      }

      final parsed = parseName(pin);
      final ref = parsed == null
          ? null
          : result.bindings.ref(parsed.channel, index: parsed.channelIndex);
      if (parsed == null || ref == null) {
        candidates[pin] = BoardAutoBindCandidate(
          confidence: BoardAutoBindConfidence.noMatch,
          matchReason: parsed == null
              ? "'$pin' is not an RVFI channel"
              : "no '${parsed.channel.signalName}' in the loaded trace",
        );
        continue;
      }

      final isCanonical =
          result.bindings.namePrefix.isEmpty &&
          result.bindings.scopePath.isEmpty;
      candidates[pin] = BoardAutoBindCandidate(
        confidence: isCanonical
            ? BoardAutoBindConfidence.exactMatch
            : BoardAutoBindConfidence.knownAlias,
        matchReason:
            'RVFI ${parsed.channel.signalName} from '
            '${result.bindings.displayPath}',
        binding: StageSignalBinding(signalRef: ref),
      );
    }

    return BoardAutoBindResult(candidates: candidates);
  }

  // ── private ───────────────────────────────────────────────────────────────

  /// Longest-first channel lookup on a leaf name, so `rvfi_mem_rdata` is not
  /// shadowed by a shorter sibling and a flattened prefix still resolves.
  static RvfiChannel? _channelForTail(String name) {
    RvfiChannel? best;
    for (final c in RvfiChannel.values) {
      if (name == c.signalName || name.endsWith('_${c.signalName}')) {
        if (best == null || c.signalName.length > best.signalName.length) {
          best = c;
        }
      }
    }
    return best;
  }
}

class _Bundle {
  _Bundle({required this.scopePath, required this.namePrefix});

  final String scopePath;
  final String namePrefix;
  final Map<RvfiChannel, Map<int, String>> refs = {};
  int maxIndex = 0;
  bool packedVectorSuspected = false;

  int get channelsFound => refs.length;
  int get channelCount => maxIndex + 1;

  void add(RvfiNameMatch match, Variable v) {
    refs
        .putIfAbsent(match.channel, () => <int, String>{})
        .putIfAbsent(match.channelIndex, () => v.signalRef);
    if (match.channelIndex > maxIndex) maxIndex = match.channelIndex;
    // A `rvfi_valid` wider than one bit is a packed NRET vector.
    if (match.channel == RvfiChannel.valid &&
        match.channelIndex == 0 &&
        (v.bitWidth ?? 1) > 1) {
      packedVectorSuspected = true;
    }
  }
}
