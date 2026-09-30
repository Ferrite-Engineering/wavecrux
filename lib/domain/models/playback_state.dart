// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// What the playhead does when it reaches the end of the active range.
enum PlaybackLoopMode {
  /// Stop at the end of the range (default).
  none,

  /// Wrap back to the start of the whole simulation range and keep playing.
  wholeRange,

  /// Wrap within the `[min, max]` span defined by the two cursors. Falls back
  /// to [wholeRange] semantics when the secondary cursor is unset.
  aToB,
}

/// How fast the playhead advances, expressed in one of two file-independent
/// modes.
///
/// - **Duration mode** ([PlaybackSpeed.duration]) plays the active range in a
///   fixed number of wall-clock seconds. Because it is derived from the range's
///   tick-span it needs no trace timescale and behaves identically whether the
///   trace is picosecond- or second-scale. This is the default and the only
///   mode surfaced in the transport UI.
/// - **Power mode** ([PlaybackSpeed.simTimePerSecond]) advances a fixed amount
///   of *simulation time* per wall-clock second; converting it to ticks needs
///   the trace timescale (the engine reads `currentTimescaleProvider`). When no
///   timescale is available the engine falls back to the default duration
///   playback.
@immutable
class PlaybackSpeed {
  /// Play the active range in [playSeconds] wall-clock seconds.
  const PlaybackSpeed.duration(double this.playSeconds)
    : simTimePerWallSecond = null;

  /// Advance [simTimePerWallSecond] seconds of simulation time per wall-clock
  /// second (requires the trace timescale).
  const PlaybackSpeed.simTimePerSecond(double this.simTimePerWallSecond)
    : playSeconds = null;

  /// Wall-clock seconds to play the whole active range. Null in power mode.
  final double? playSeconds;

  /// Seconds of simulation time advanced per wall second. Null in duration
  /// mode.
  final double? simTimePerWallSecond;

  /// True when this is a duration-mode speed.
  bool get isDuration => playSeconds != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSpeed &&
          runtimeType == other.runtimeType &&
          playSeconds == other.playSeconds &&
          simTimePerWallSecond == other.simTimePerWallSecond;

  @override
  int get hashCode => Object.hash(playSeconds, simTimePerWallSecond);

  @override
  String toString() => playSeconds != null
      ? 'PlaybackSpeed.duration($playSeconds s)'
      : 'PlaybackSpeed.simTimePerSecond($simTimePerWallSecond)';
}

/// Immutable snapshot of the Stage Playback transport state.
///
/// The playback *engine* (`PlaybackNotifier`) owns the frame loop and the
/// fractional position accumulator; this model holds only the user-visible
/// transport settings so the transport UI can rebuild from a single
/// `watch(playbackProvider)`.
@immutable
class PlaybackState {
  const PlaybackState({
    this.isPlaying = false,
    this.speed = const PlaybackSpeed.duration(10),
    this.loopMode = PlaybackLoopMode.none,
    this.followViewport = true,
  });

  /// Whether the playhead is currently advancing.
  final bool isPlaying;

  /// How fast the playhead advances.
  final PlaybackSpeed speed;

  /// What happens at the end of the active range.
  final PlaybackLoopMode loopMode;

  /// Whether the viewport recentres on the playhead when it scrolls off-screen.
  final bool followViewport;

  PlaybackState copyWith({
    bool? isPlaying,
    PlaybackSpeed? speed,
    PlaybackLoopMode? loopMode,
    bool? followViewport,
  }) => PlaybackState(
    isPlaying: isPlaying ?? this.isPlaying,
    speed: speed ?? this.speed,
    loopMode: loopMode ?? this.loopMode,
    followViewport: followViewport ?? this.followViewport,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          runtimeType == other.runtimeType &&
          isPlaying == other.isPlaying &&
          speed == other.speed &&
          loopMode == other.loopMode &&
          followViewport == other.followViewport;

  @override
  int get hashCode => Object.hash(isPlaying, speed, loopMode, followViewport);

  @override
  String toString() =>
      'PlaybackState(isPlaying: $isPlaying, speed: $speed, '
      'loopMode: $loopMode, followViewport: $followViewport)';
}
