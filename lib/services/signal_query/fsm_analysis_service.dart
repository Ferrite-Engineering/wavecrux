// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';

/// Stateless service that builds an [FsmModel] for a signal by scanning its
/// value changes and grouping equal values into states.
///
/// The signal must be pre-loaded via [WaveformDataSource.loadSignal] before
/// calling [buildModel]. Values containing `x` or `z` are skipped — they
/// represent uninitialised or high-impedance states that are not part of
/// the FSM's reachable state space.
///
/// State labels are resolved in this priority order:
/// 1. [FsmAnnotation.stateLabels] (user-supplied).
/// 2. [TranslateFilter.translate] (GTKWave translate filter).
/// 3. The raw integer value (decimal string).
class FsmAnalysisService {
  const FsmAnalysisService();

  /// Builds the FSM model for [signalRef] over `[startTime, endTime)`.
  ///
  /// [signalPath] is purely informational and stored on the resulting
  /// [FsmModel].
  ///
  /// Returns an [FsmModel] with empty states/transitions if the signal has
  /// no defined values in the range (all x/z, or unloaded).
  FsmModel buildModel({
    required String signalRef,
    required String signalPath,
    required WaveformDataSource source,
    required int startTime,
    required int endTime,
    FsmAnnotation? annotation,
    TranslateFilter? translateFilter,
  }) {
    final timeRange = TimeRange(start: startTime, end: endTime);

    // Per-state metadata.
    final entryCounts = <String, int>{};
    final firstEntries = <String, int>{};

    // Per-transition metadata. Key: "from→to".
    final transitionTimes = <String, List<int>>{};

    // Determine the initial state at startTime (if any).
    final initialRaw = source.valueAt(signalRef, startTime);
    final initialId = _normalize(initialRaw);
    if (initialId != null) {
      entryCounts[initialId] = 1;
      firstEntries[initialId] = startTime;
    }

    // Process all changes strictly after the initial value, in order.
    final changes = source.changesInRange(signalRef, startTime, endTime);

    var prevId = initialId;
    for (final change in changes) {
      // Skip the change at startTime itself — it was already represented by
      // the valueAt() call. (changesInRange returns changes whose time is in
      // [startTime, endTime), so the very first change may coincide with
      // startTime if a transition falls on the boundary.)
      if (change.time == startTime && initialId != null) continue;

      final id = _normalize(change.value);
      if (id == null) {
        // x/z transitions break the chain — the FSM is in an undefined
        // state until a defined value reappears. We do not record a
        // transition into an undefined state.
        prevId = null;
        continue;
      }

      // Record entry to this state.
      entryCounts[id] = (entryCounts[id] ?? 0) + 1;
      firstEntries[id] ??= change.time;

      // Record transition from previous (if any) to this.
      if (prevId != null) {
        final key = '$prevId→$id';
        transitionTimes.putIfAbsent(key, () => <int>[]).add(change.time);
      }

      prevId = id;
    }

    // Materialise states. Sort by numeric id where possible, otherwise
    // lexicographically.
    final stateIds = entryCounts.keys.toList()..sort(_compareIds);
    final states = [
      for (final id in stateIds)
        FsmState(
          id: id,
          label: _resolveLabel(id, annotation, translateFilter),
          entryCount: entryCounts[id]!,
          firstEntryTime: firstEntries[id],
        ),
    ];

    // Materialise transitions. Sort by (from, to) for deterministic output.
    final transitionKeys = transitionTimes.keys.toList()..sort();
    final transitions = <FsmTransition>[];
    var totalCount = 0;
    for (final key in transitionKeys) {
      final times = transitionTimes[key]!..sort();
      final parts = key.split('→');
      transitions.add(
        FsmTransition(
          fromId: parts[0],
          toId: parts[1],
          count: times.length,
          times: List<int>.unmodifiable(times),
        ),
      );
      totalCount += times.length;
    }

    return FsmModel(
      signalRef: signalRef,
      signalPath: signalPath,
      timeRange: timeRange,
      states: List<FsmState>.unmodifiable(states),
      transitions: List<FsmTransition>.unmodifiable(transitions),
      totalTransitionCount: totalCount,
    );
  }

  /// Returns the FSM state id (decimal integer string) corresponding to the
  /// raw value at [time], or null when the signal is x/z or undefined.
  String? stateIdAt({
    required String signalRef,
    required WaveformDataSource source,
    required int time,
  }) {
    final raw = source.valueAt(signalRef, time);
    return _normalize(raw);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Converts a wellen bit-string (or real-valued string) into a canonical
  /// decimal integer string suitable as an FSM state id.
  ///
  /// Returns null for null, empty, x/z-tainted, or unparseable values.
  static String? _normalize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.contains('x') || lower.contains('z')) return null;

    // Strip the optional 'b' prefix that some VCD writers produce.
    final body = lower.startsWith('b') ? lower.substring(1) : lower;
    if (body.isEmpty) return null;

    // Real values (e.g. "3.14") are not FSM state values. We only accept
    // pure binary strings.
    if (body.contains('.')) return null;
    for (var i = 0; i < body.length; i++) {
      final c = body.codeUnitAt(i);
      // Allow only '0' and '1'.
      if (c != 0x30 && c != 0x31) return null;
    }

    final value = BigInt.tryParse(body, radix: 2);
    if (value == null) return null;
    return value.toString();
  }

  static String _resolveLabel(
    String id,
    FsmAnnotation? annotation,
    TranslateFilter? translateFilter,
  ) {
    final annotated = annotation?.labelFor(id);
    if (annotated != null && annotated.isNotEmpty) return annotated;
    if (translateFilter != null) {
      // Translate filter expects a binary bit-string; we have decimal.
      // Re-encode as binary so the existing API works.
      final value = BigInt.parse(id);
      final translated = translateFilter.translate(value.toRadixString(2));
      if (translated != null && translated.isNotEmpty) return translated;
    }
    return id;
  }

  /// Numeric id comparison; falls back to lexicographic for non-numeric ids.
  static int _compareIds(String a, String b) {
    final ai = BigInt.tryParse(a);
    final bi = BigInt.tryParse(b);
    if (ai != null && bi != null) return ai.compareTo(bi);
    return a.compareTo(b);
  }
}
