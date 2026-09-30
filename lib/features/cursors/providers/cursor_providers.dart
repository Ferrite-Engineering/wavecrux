// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

part 'cursor_providers.g.dart';

/// Manages the primary and secondary cursor positions.
///
/// Widgets that need to move a cursor call [placePrimary] or [placeSecondary].
/// All times are simulation ticks. Both methods clamp the requested time to
/// the loaded simulation's `[startTime, endTime]` range (read from the live
/// [timeMapperProvider]) so a caller can never produce a cursor outside the
/// data — pre-fix (Issue 30), an edge-pan past `t=0` on iPhone landscape
/// reported `T: -233 ns` in the status bar with a dash in every value cell
/// because no data exists at negative time. When no waveform is loaded the
/// mapper's empty range collapses to `[0, 0]`, so the clamp is a no-op.
@riverpod
class CursorStateNotifier extends _$CursorStateNotifier {
  @override
  CursorState build() => const CursorState();

  int _clampToWaveformRange(int time) {
    final mapper = ref.read(timeMapperProvider);
    final lo = mapper.startTime;
    final hi = mapper.endTime;
    // No waveform loaded (empty mapper reports endTime == startTime): skip
    // the clamp so the cursor accepts whatever value the caller asked for.
    // Cursor placement has no observable effect until a file loads.
    if (hi <= lo) return time;
    return time.clamp(lo, hi);
  }

  /// Places the primary cursor at [time]. Clamped to `[startTime, endTime]`.
  void placePrimary(int time) {
    state = state.copyWith(primaryCursorTime: _clampToWaveformRange(time));
  }

  /// Places the secondary (delta-measurement) cursor at [time].
  /// Clamped to `[startTime, endTime]`.
  void placeSecondary(int time) {
    state = state.copyWith(secondaryCursorTime: _clampToWaveformRange(time));
  }

  /// Removes the secondary cursor; primary cursor is unaffected.
  void clearSecondary() {
    state = state.copyWith(secondaryCursorTime: null);
  }

  /// Removes both cursors.
  void clearAll() {
    state = const CursorState();
  }
}

/// Manages named markers (a–z) associated with simulation ticks.
///
/// Marker names follow GTKWave convention: a single lowercase letter.
@riverpod
class MarkerStateNotifier extends _$MarkerStateNotifier {
  @override
  MarkerState build() => const MarkerState();

  /// Sets marker [name] to [time], overwriting any previous position.
  void setMarker(String name, int time) {
    state = state.setMarker(name, time);
  }

  /// Removes marker [name]. No-op if the marker is not set.
  void removeMarker(String name) {
    state = state.removeMarker(name);
  }

  /// Returns the simulation tick for marker [name], or null if not set.
  ///
  /// Callers use the returned time to update the cursor or scroll the viewport.
  int? jumpToMarker(String name) => state.getMarker(name);
}

/// Pre-computed delta-time and frequency strings for the cursor measurement bar.
///
/// Returns a [CursorDelta] whose fields are null when either cursor is absent
/// or when the delta is zero (frequency would be infinite).
@riverpod
CursorDelta cursorDelta(Ref ref) {
  final cursor = ref.watch(cursorStateProvider);
  final timescale = ref.watch(currentTimescaleProvider);

  final deltaTicks = cursor.deltaTicks;
  if (deltaTicks == null) {
    return const CursorDelta(deltaDisplay: null, frequencyDisplay: null);
  }

  final formatter = TimeFormatService(timescale: timescale);
  final deltaDisplay = formatter.formatDelta(0, deltaTicks);

  String? frequencyDisplay;
  final spt = timescale?.secondsPerTick;
  if (spt != null && deltaTicks > 0) {
    final deltaSeconds = deltaTicks.toDouble() * spt;
    frequencyDisplay = _formatFrequency(1.0 / deltaSeconds);
  }

  return CursorDelta(
    deltaDisplay: deltaDisplay,
    frequencyDisplay: frequencyDisplay,
  );
}

/// Delta-time and frequency measurement between the two cursors.
@immutable
class CursorDelta {
  const CursorDelta({
    required this.deltaDisplay,
    required this.frequencyDisplay,
  });

  /// Human-readable delta time (e.g. `"500 ns"`), or null when not measurable.
  final String? deltaDisplay;

  /// Human-readable frequency (e.g. `"2 MHz"`), or null when not measurable.
  final String? frequencyDisplay;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CursorDelta &&
          deltaDisplay == other.deltaDisplay &&
          frequencyDisplay == other.frequencyDisplay;

  @override
  int get hashCode => Object.hash(deltaDisplay, frequencyDisplay);

  @override
  String toString() =>
      'CursorDelta(delta: $deltaDisplay, freq: $frequencyDisplay)';
}

String _formatFrequency(double hz) {
  if (hz >= 1e9) return '${_compact(hz / 1e9)} GHz';
  if (hz >= 1e6) return '${_compact(hz / 1e6)} MHz';
  if (hz >= 1e3) return '${_compact(hz / 1e3)} kHz';
  if (hz >= 1.0) return '${_compact(hz)} Hz';
  if (hz >= 1e-3) return '${_compact(hz * 1e3)} mHz';
  return '${_compact(hz * 1e6)} µHz';
}

String _compact(double v) {
  if (v >= 100) return v.toStringAsFixed(1);
  if (v >= 10) return v.toStringAsFixed(2);
  return v.toStringAsFixed(3);
}
