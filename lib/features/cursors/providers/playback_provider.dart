// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/playback_state.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

part 'playback_provider.g.dart';

/// Wall-clock seconds used to play the active range when power-mode playback is
/// requested but no trace timescale is available to convert sim-time to ticks.
/// Matches the duration-mode default so the playhead still advances.
const double _kDefaultPlaySeconds = 10;

/// Drives Stage Playback: a frame loop that auto-advances the **primary
/// cursor** so signal-bound Stage widgets animate on their own.
///
/// This lives at the **cursor layer** (sibling of [CursorStateNotifier]), not
/// under `features/stage/`, because "advance the cursor on a ticker" is reusable
/// cursor infrastructure — the playback *engine* is always-on and not gated on
/// Stage. Only the transport UI and the `togglePlayback` shortcut are
/// Stage-gated. Advancing `primaryCursorTime` is all it takes: Stage widgets
/// (`stageBoundSignalProvider`) and the value column already `watch`
/// [cursorStateProvider] and re-sample, so everything bound re-animates for
/// free.
///
/// The advance math lives in [advanceBy], which is pure with respect to the
/// [Ticker]/`DateTime`/`Timer` machinery — tests drive it directly with
/// synthetic [Duration]s.
///
/// Per-tab: overridden in `wavecruxTabOverrides` so it resolves the focused
/// tab's [cursorStateProvider] / [timeMapperProvider] / [navigationProvider]
/// rather than the empty root scope.
@riverpod
class PlaybackNotifier extends _$PlaybackNotifier {
  @override
  PlaybackState build() {
    ref.onDispose(_stopTicker);
    return const PlaybackState();
  }

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  /// Fractional playhead position in ticks (the cursor itself is integer).
  double _positionTicks = 0;

  /// Active-range bounds captured at [play]. Default `[0, 0]` so [stop] is safe
  /// before the first [play].
  int _rangeLo = 0;
  int _rangeHi = 0;

  // ── transport ──────────────────────────────────────────────────────────────

  /// Starts (or resumes) playback. No-op when no waveform is loaded or the
  /// captured range is degenerate.
  void play() {
    final mapper = ref.read(timeMapperProvider);
    if (mapper.isEmpty) return;

    final cursor = ref.read(cursorStateProvider);
    int lo;
    int hi;
    final primary = cursor.primaryCursorTime;
    final secondary = cursor.secondaryCursorTime;
    if (state.loopMode == PlaybackLoopMode.aToB &&
        primary != null &&
        secondary != null) {
      lo = math.min(primary, secondary);
      hi = math.max(primary, secondary);
    } else {
      // wholeRange / none (and aToB with a missing secondary) play the whole
      // simulation range.
      lo = mapper.startTime;
      hi = mapper.endTime;
    }
    if (hi <= lo) return;

    _rangeLo = lo;
    _rangeHi = hi;
    // Resume from the current primary cursor, unless it is unset or sits at /
    // past the end of the range — then (re)start from the range start so
    // re-pressing Play from the end replays.
    if (primary == null || primary >= hi || primary < lo) {
      _positionTicks = lo.toDouble();
    } else {
      _positionTicks = primary.toDouble();
    }

    if (!state.isPlaying) state = state.copyWith(isPlaying: true);
    _startTicker();
  }

  /// Pauses playback, leaving the cursor where it is.
  void pause() {
    _stopTicker();
    if (state.isPlaying) state = state.copyWith(isPlaying: false);
  }

  /// Stops playback and returns the cursor to the start of the captured range.
  void stop() {
    pause();
    ref.read(cursorStateProvider.notifier).placePrimary(_rangeLo);
  }

  /// Toggles between [play] and [pause].
  void toggle() => state.isPlaying ? pause() : play();

  // ── settings ─────────────────────────────────────────────────────────────────

  void setSpeed(PlaybackSpeed speed) => state = state.copyWith(speed: speed);

  void setLoopMode(PlaybackLoopMode mode) =>
      state = state.copyWith(loopMode: mode);

  void setFollowViewport({required bool value}) =>
      state = state.copyWith(followViewport: value);

  // ── advance math (pure w.r.t. Ticker / DateTime / Timer) ─────────────────────

  /// Advances the playhead by a wall-clock [dt], placing the primary cursor at
  /// the new position. Tests call this directly with synthetic durations.
  void advanceBy(Duration dt) {
    if (_rangeHi <= _rangeLo) return;

    _positionTicks += _ticksPerWallSecond() * dt.inMicroseconds / 1e6;

    if (_positionTicks >= _rangeHi) {
      if (state.loopMode == PlaybackLoopMode.none) {
        _positionTicks = _rangeHi.toDouble();
        _placeCursor(_rangeHi);
        _finishAtEnd();
        return;
      }
      // Loop: wrap the overshoot back into `[lo, hi)`.
      final span = (_rangeHi - _rangeLo).toDouble();
      _positionTicks = _rangeLo + ((_positionTicks - _rangeLo) % span);
    }

    _placeCursor(_positionTicks.round());
  }

  void _placeCursor(int t) {
    ref.read(cursorStateProvider.notifier).placePrimary(t);
    if (state.followViewport) _followIfOffscreen(t);
  }

  /// Ticks advanced per wall-clock second, from the active speed and range.
  double _ticksPerWallSecond() {
    final span = (_rangeHi - _rangeLo).toDouble();
    final speed = state.speed;
    final playSeconds = speed.playSeconds;
    if (playSeconds != null && playSeconds > 0) {
      // Duration mode: file-independent — the same wall-clock budget regardless
      // of the trace's tick scale.
      return span / playSeconds;
    }
    final simPerWallSecond = speed.simTimePerWallSecond;
    final secondsPerTick = ref.read(currentTimescaleProvider)?.secondsPerTick;
    if (simPerWallSecond != null &&
        secondsPerTick != null &&
        secondsPerTick > 0) {
      // Power mode: sim-seconds-per-wall-second ÷ sim-seconds-per-tick.
      return simPerWallSecond / secondsPerTick;
    }
    // Power mode requested without a usable timescale: fall back to the default
    // duration playback so the playhead still advances.
    return span / _kDefaultPlaySeconds;
  }

  /// Recentres the viewport on the playhead only when it has left the visible
  /// window, avoiding per-frame re-centring jitter.
  void _followIfOffscreen(int t) {
    final mapper = ref.read(timeMapperProvider);
    if (mapper.isEmpty) return;
    final windowLo = mapper.panOffsetTicks;
    final windowHi =
        mapper.panOffsetTicks + mapper.viewportWidth * mapper.ticksPerPixel;
    if (t < windowLo || t > windowHi) {
      ref.read(navigationProvider.notifier).jumpToTime(t);
    }
  }

  void _finishAtEnd() {
    _stopTicker();
    if (state.isPlaying) state = state.copyWith(isPlaying: false);
  }

  // ── ticker lifecycle ─────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    advanceBy(dt);
  }

  void _startTicker() {
    _stopTicker();
    _lastElapsed = Duration.zero;
    final ticker = Ticker(_onTick);
    _ticker = ticker;
    // Ticker.start() returns a TickerFuture that completes only when the ticker
    // is stopped/disposed; we drive frames via the callback, so the future is
    // intentionally not awaited.
    ticker.start();
  }

  void _stopTicker() {
    _ticker
      ?..stop()
      ..dispose();
    _ticker = null;
  }
}
