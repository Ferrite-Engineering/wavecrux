// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Immutable mapping between simulation time (integer ticks) and viewport
/// pixel x-coordinates.
///
/// Zoom and pan operations return a new [TimeMapper]; the original is unchanged.
/// Coordinate system: pixel 0 = left edge; pixel [viewportWidth] = right edge.
@immutable
class TimeMapper {
  const TimeMapper({
    required this.startTime,
    required this.endTime,
    required this.viewportWidth,
    required this.ticksPerPixel,
    required this.panOffsetTicks,
  });

  /// Constructs a [TimeMapper] that fits the entire simulation time range
  /// within [viewportWidth] pixels.
  factory TimeMapper.fitAll({
    required int startTime,
    required int endTime,
    required double viewportWidth,
  }) {
    final range = (endTime - startTime).toDouble();
    if (range <= 0 || viewportWidth <= 0) {
      return TimeMapper(
        startTime: startTime,
        endTime: endTime,
        viewportWidth: math.max(1, viewportWidth),
        ticksPerPixel: 1,
        panOffsetTicks: startTime.toDouble(),
      );
    }
    return TimeMapper(
      startTime: startTime,
      endTime: endTime,
      viewportWidth: viewportWidth,
      ticksPerPixel: range / viewportWidth,
      panOffsetTicks: startTime.toDouble(),
    );
  }

  /// An empty mapper placeholder used before a waveform file is loaded.
  factory TimeMapper.empty() => const TimeMapper(
    startTime: 0,
    endTime: 0,
    viewportWidth: 1000,
    ticksPerPixel: 1,
    panOffsetTicks: 0,
  );

  /// The simulation's start time (inclusive), in ticks.
  final int startTime;

  /// The simulation's end time (inclusive), in ticks.
  final int endTime;

  /// Width of the visible viewport in logical pixels.
  final double viewportWidth;

  /// Number of simulation ticks represented by one pixel.
  ///
  /// Higher = more zoomed out; lower = more zoomed in.
  final double ticksPerPixel;

  /// Simulation time (ticks) at pixel x = 0 (the left edge).
  final double panOffsetTicks;

  // ── zoom constraints ───────────────────────────────────────────────────────

  /// Hard floor on [ticksPerPixel], independent of the viewport.
  ///
  /// Only a guard: [minTicksPerPixel] is what the zoom actually clamps to, and
  /// this exists so the clamp can never be handed a zero or negative bound on
  /// a degenerate viewport.
  static const double absoluteMinTicksPerPixel = 1e-9;

  /// The fewest ticks a viewport is allowed to span — the finest zoom-in.
  ///
  /// **One tick, because one tick is the timescale's resolution.** The data
  /// carries no information below it, so a viewport narrower than a single
  /// tick is the mirror image of unbounded zoom-out: a flat expanse with no
  /// edge in it, at a magnification that cannot reveal anything the previous
  /// one did not, and a ruler labelling divisions the trace does not have.
  /// One rather than a handful so that zoom-to-selection on a one-tick
  /// selection still shows exactly that tick.
  static const double minVisibleTicks = 1;

  /// Maximum zoom-in level: [minVisibleTicks] ticks across the whole viewport.
  ///
  /// Viewport-relative for the same reason [maxTicksPerPixel] is — both bounds
  /// are statements about *what is on screen*, and a fixed ticks-per-pixel
  /// number means something different on every window width.
  double get minTicksPerPixel {
    if (viewportWidth <= 0) return absoluteMinTicksPerPixel;
    final floor = math.max(
      absoluteMinTicksPerPixel,
      minVisibleTicks / viewportWidth,
    );
    // Never above the zoom-out bound. A trace only a tick or two long must
    // still be able to fit-all, and `clamp` requires `min <= max`.
    return math.min(floor, maxTicksPerPixel);
  }

  /// Maximum zoom-out level: the fit-all scale (entire waveform fills the
  /// viewport). Zooming out further would only show blank space.
  ///
  /// Returns 1.0 when the simulation range is empty — there is no extent to
  /// fit, so any scale is as good as any other.
  ///
  /// **No `math.max(1, …)` floor here.** It used to have one, and on any trace
  /// shorter than one tick per pixel it silently became the bound instead of
  /// fit-all: a 70-tick trace in a 1400 px viewport fits at 0.05 ticks/px but
  /// was allowed out to 1.0, so twenty presses of zoom-out crushed the data
  /// into the left 5 % of the canvas and filled the rest with nothing. The
  /// doc-comment above already said that was the thing not to do.
  double get maxTicksPerPixel {
    final range = (endTime - startTime).toDouble();
    if (range <= 0 || viewportWidth <= 0) return 1;
    return math.max(absoluteMinTicksPerPixel, range / viewportWidth);
  }

  // ── zoom-bound queries ─────────────────────────────────────────────────────

  /// Whether zooming out would actually change anything — false once the
  /// viewport spans the whole trace.
  ///
  /// The control surfaces gate on this rather than letting the clamp absorb
  /// the press: a button that lights up, responds, and does nothing is its own
  /// small lie.
  bool get canZoomOut => !isEmpty && ticksPerPixel < maxTicksPerPixel;

  /// Whether zooming in would actually change anything — false once the
  /// viewport spans [minVisibleTicks].
  bool get canZoomIn => !isEmpty && ticksPerPixel > minTicksPerPixel;

  // ── state queries ──────────────────────────────────────────────────────────

  /// True when no simulation data has been loaded ([startTime] == [endTime]).
  bool get isEmpty => endTime <= startTime;

  // ── coordinate conversions ─────────────────────────────────────────────────

  /// Converts simulation [time] (ticks) to a viewport pixel x-coordinate.
  ///
  /// The result may be outside [0, viewportWidth] for off-screen times.
  double timeToPixel(int time) => (time - panOffsetTicks) / ticksPerPixel;

  /// Converts a viewport pixel x-coordinate to the nearest simulation tick.
  int pixelToTime(double pixel) =>
      (panOffsetTicks + pixel * ticksPerPixel).round();

  /// The simulation time at the left edge of the viewport (pixel x = 0).
  int get visibleStartTime => pixelToTime(0);

  /// The simulation time at the right edge of the viewport.
  int get visibleEndTime => pixelToTime(viewportWidth);

  /// Number of ticks currently visible across the full viewport width.
  int get visibleRange => visibleEndTime - visibleStartTime;

  // ── zoom operations ────────────────────────────────────────────────────────

  /// Zooms around [focalPixel], keeping that screen position at the same
  /// simulation time.
  ///
  /// [factor] > 1 zooms in; [factor] < 1 zooms out.
  /// [ticksPerPixel] is clamped to [[minTicksPerPixel], [maxTicksPerPixel]].
  TimeMapper zoomAround(double focalPixel, double factor) {
    if (factor <= 0) return this;
    final focalTime = panOffsetTicks + focalPixel * ticksPerPixel;
    final newTicksPerPixel = (ticksPerPixel / factor).clamp(
      minTicksPerPixel,
      maxTicksPerPixel,
    );
    final newPanOffset = focalTime - focalPixel * newTicksPerPixel;
    return _copy(ticksPerPixel: newTicksPerPixel, panOffsetTicks: newPanOffset);
  }

  // ── pan operations ─────────────────────────────────────────────────────────

  /// Pans by [deltaPixels] pixels (positive = moves forward in time).
  TimeMapper panByPixels(double deltaPixels) =>
      _copy(panOffsetTicks: panOffsetTicks + deltaPixels * ticksPerPixel);

  /// Pans by [deltaTicks] simulation ticks (positive = moves forward).
  TimeMapper panByTime(int deltaTicks) =>
      _copy(panOffsetTicks: panOffsetTicks + deltaTicks);

  // ── fit / range ────────────────────────────────────────────────────────────

  /// Returns a mapper that shows the full simulation range in the viewport.
  TimeMapper fitAll() => TimeMapper.fitAll(
    startTime: startTime,
    endTime: endTime,
    viewportWidth: viewportWidth,
  );

  /// Zooms to show exactly [[rangeStart], [rangeEnd]] in the viewport, or as
  /// close to it as the zoom bounds allow.
  ///
  /// Returns this mapper unchanged if the range is zero or inverted.
  TimeMapper zoomToRange(int rangeStart, int rangeEnd) {
    final range = (rangeEnd - rangeStart).toDouble();
    if (range <= 0 || viewportWidth <= 0) return this;
    final newTicksPerPixel = (range / viewportWidth).clamp(
      minTicksPerPixel,
      maxTicksPerPixel,
    );
    return _copy(
      ticksPerPixel: newTicksPerPixel,
      panOffsetTicks: rangeStart.toDouble(),
    );
  }

  // ── viewport resize ────────────────────────────────────────────────────────

  /// Returns a copy with [newWidth] as the viewport width, preserving the
  /// center simulation time.
  TimeMapper withViewportWidth(double newWidth) {
    if (newWidth <= 0 || newWidth == viewportWidth) return this;
    final centerTime = panOffsetTicks + (viewportWidth / 2) * ticksPerPixel;
    final newPanOffset = centerTime - (newWidth / 2) * ticksPerPixel;
    return TimeMapper(
      startTime: startTime,
      endTime: endTime,
      viewportWidth: newWidth,
      ticksPerPixel: ticksPerPixel,
      panOffsetTicks: newPanOffset,
    );
  }

  /// Returns a fit-all mapper for a new simulation time range, preserving
  /// [viewportWidth].
  TimeMapper withSimulationRange(int newStartTime, int newEndTime) =>
      TimeMapper.fitAll(
        startTime: newStartTime,
        endTime: newEndTime,
        viewportWidth: viewportWidth,
      );

  // ── pan clamping ───────────────────────────────────────────────────────────

  /// Returns a copy with [panOffsetTicks] clamped to the valid scroll range.
  ///
  /// - Left limit: [startTime] — the waveform cannot scroll before time zero.
  /// - Right limit: [endTime] − viewport width in ticks — endTime stays
  ///   reachable on the right edge. When fully zoomed out the limit collapses
  ///   to [startTime], keeping the waveform left-anchored.
  TimeMapper clamped() {
    if (isEmpty) return this;
    final minOffset = startTime.toDouble();
    final maxOffset = math.max(
      minOffset,
      endTime.toDouble() - viewportWidth * ticksPerPixel,
    );
    final clampedOffset = panOffsetTicks.clamp(minOffset, maxOffset);
    if (clampedOffset == panOffsetTicks) return this;
    return _copy(panOffsetTicks: clampedOffset);
  }

  // ── internals ──────────────────────────────────────────────────────────────

  TimeMapper _copy({double? ticksPerPixel, double? panOffsetTicks}) =>
      TimeMapper(
        startTime: startTime,
        endTime: endTime,
        viewportWidth: viewportWidth,
        ticksPerPixel: ticksPerPixel ?? this.ticksPerPixel,
        panOffsetTicks: panOffsetTicks ?? this.panOffsetTicks,
      );

  // ── copyWith ───────────────────────────────────────────────────────────────

  TimeMapper copyWith({
    int? startTime,
    int? endTime,
    double? viewportWidth,
    double? ticksPerPixel,
    double? panOffsetTicks,
  }) => TimeMapper(
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    viewportWidth: viewportWidth ?? this.viewportWidth,
    ticksPerPixel: ticksPerPixel ?? this.ticksPerPixel,
    panOffsetTicks: panOffsetTicks ?? this.panOffsetTicks,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeMapper &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.viewportWidth == viewportWidth &&
        other.ticksPerPixel == ticksPerPixel &&
        other.panOffsetTicks == panOffsetTicks;
  }

  @override
  int get hashCode => Object.hash(
    startTime,
    endTime,
    viewportWidth,
    ticksPerPixel,
    panOffsetTicks,
  );

  @override
  String toString() =>
      'TimeMapper(startTime: $startTime, endTime: $endTime, '
      'viewportWidth: $viewportWidth, ticksPerPixel: $ticksPerPixel, '
      'panOffsetTicks: $panOffsetTicks)';
}
