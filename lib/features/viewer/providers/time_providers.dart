// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/services/waveform_geom/time_ruler_data.dart';

part 'time_providers.g.dart';

/// Manages zoom and pan state for the waveform viewport.
///
/// Call [initialize] when a new waveform file is loaded to set the simulation
/// time range and reset the view to fit-all. All zoom/pan operations produce a
/// new [TimeMapper]; the provider holds the current one.
@riverpod
class TimeMapperNotifier extends _$TimeMapperNotifier {
  double? _pendingTicksPerPixel;
  double? _pendingPanOffsetTicks;

  /// Whether the viewport is tracking "fit all" mode.
  ///
  /// When true, [updateViewportWidth] recalculates [TimeMapper.ticksPerPixel]
  /// so the full simulation range always fills the viewport. When false, the
  /// zoom level is preserved on resize (showing more or less waveform as the
  /// window grows or shrinks), and the mode automatically switches back to
  /// true once the viewport is wide enough to show the entire simulation at
  /// the current zoom level.
  bool _isFitAll = true;

  /// Whether a canvas has laid this mapper out for a loaded source.
  ///
  /// False until the first [initialize]: before that the state is the
  /// [TimeMapper.empty] placeholder, and zoom or pan applied to it changes
  /// nothing anyone can see. Remote viewport commands check it so they can
  /// report that rather than acknowledge a no-op.
  bool get isLaidOut => _isLaidOut;
  bool _isLaidOut = false;

  @override
  TimeMapper build() => TimeMapper.empty();

  /// Initializes the mapper with a new simulation time range.
  ///
  /// When [fitAll] is true (default), the viewport is zoomed to show the
  /// entire simulation range. Pass `fitAll: false` to preserve the current
  /// zoom level (e.g. when the same file is reloaded after an auto-refresh).
  ///
  /// If [setPendingZoomPan] was called before this method, the pending
  /// zoom/pan values are applied instead of fitting all, and then cleared.
  void initialize({
    required int startTime,
    required int endTime,
    required double viewportWidth,
    bool fitAll = true,
  }) {
    _isLaidOut = true;
    if (_pendingTicksPerPixel != null) {
      final tpp = _pendingTicksPerPixel!;
      final pan = _pendingPanOffsetTicks ?? startTime.toDouble();
      _pendingTicksPerPixel = null;
      _pendingPanOffsetTicks = null;
      // Session restore implies an explicit zoom/pan — not fit-all mode.
      _isFitAll = false;
      final mapper = TimeMapper(
        startTime: startTime,
        endTime: endTime,
        viewportWidth: viewportWidth,
        ticksPerPixel: 1,
        panOffsetTicks: pan,
      );
      // Clamp tpp into valid range now that we have the simulation bounds —
      // and the pan with it, so a session saved under the old unbounded
      // zoom-out reopens showing the trace rather than the blank space past
      // the end of it.
      state = mapper
          .copyWith(
            ticksPerPixel: tpp.clamp(
              mapper.minTicksPerPixel,
              mapper.maxTicksPerPixel,
            ),
          )
          .clamped();
      return;
    }
    if (fitAll) _isFitAll = true;
    state = fitAll
        ? TimeMapper.fitAll(
            startTime: startTime,
            endTime: endTime,
            viewportWidth: viewportWidth,
          )
        : TimeMapper(
            startTime: startTime,
            endTime: endTime,
            viewportWidth: viewportWidth,
            ticksPerPixel: state.ticksPerPixel,
            panOffsetTicks: state.panOffsetTicks,
          );
  }

  /// Stores zoom/pan values to apply the next time [initialize] is called.
  ///
  /// Used by [SessionNotifier] when restoring a session: the waveform file
  /// must open first (which triggers [initialize]), so the zoom/pan values
  /// are stored here and consumed by the next [initialize] call.
  void setPendingZoomPan({
    required double ticksPerPixel,
    required double panOffsetTicks,
  }) {
    _pendingTicksPerPixel = ticksPerPixel;
    _pendingPanOffsetTicks = panOffsetTicks;
  }

  /// Zooms in by [factor]× around [focalPixel].
  ///
  /// Bounded by [TimeMapper.minTicksPerPixel] — a viewport narrower than one
  /// simulation tick shows a flat expanse the data has no detail to fill.
  void zoomIn({required double focalPixel, double factor = 2.0}) {
    _isFitAll = false;
    state = state.zoomAround(focalPixel, factor).clamped();
  }

  /// Zooms out by [factor]× around [focalPixel].
  ///
  /// Bounded by [TimeMapper.maxTicksPerPixel] — the most zoomed-out state is
  /// fit-all, and there is nothing past the end of the trace to show.
  void zoomOut({required double focalPixel, double factor = 2.0}) {
    final newState = state.zoomAround(focalPixel, 1.0 / factor).clamped();
    // If clamped back to the maximum zoom-out (fit-all) level, re-enter
    // fit-all mode so subsequent resizes maintain the fit.
    _isFitAll =
        !state.isEmpty && newState.ticksPerPixel >= newState.maxTicksPerPixel;
    state = newState;
  }

  /// Pans by [deltaPixels] pixels (positive = move forward in time).
  void pan(double deltaPixels) {
    state = state.panByPixels(deltaPixels).clamped();
  }

  /// Pans by [deltaTicks] simulation ticks.
  void panByTime(int deltaTicks) {
    state = state.panByTime(deltaTicks).clamped();
  }

  /// Zooms to show the full simulation time range.
  void fitAll() {
    _isFitAll = true;
    state = state.fitAll();
  }

  /// Zooms to show exactly [[start], [end]].
  ///
  /// `.clamped()` because this is a *requested* range and the request can name
  /// one that runs off the end of the trace — a follower applying a
  /// presenter's viewport, the shared-pointer overlay re-centring at the
  /// current width. Every other mutator here clamps; this one skipping it was
  /// the one way the viewport could still end up past the data.
  void zoomToRange(int start, int end) {
    _isFitAll = false;
    state = state.zoomToRange(start, end).clamped();
  }

  /// Sets the pan offset directly to [offsetTicks] (the tick at viewport
  /// pixel x = 0), clamped to the valid scroll range.
  ///
  /// Used by [WaveformHorizontalScrollbar] when the user drags the thumb
  /// or taps on the track. Does not change zoom or fit-all mode.
  void setPanOffsetTicks(double offsetTicks) {
    state = state.copyWith(panOffsetTicks: offsetTicks).clamped();
  }

  /// Sets zoom directly to [ticksPerPixel], clamped to valid bounds.
  ///
  /// Used by the remote control API (`wavecrux.zoom` method).
  void setZoom(double ticksPerPixel) {
    final clamped = ticksPerPixel.clamp(
      state.minTicksPerPixel,
      state.maxTicksPerPixel,
    );
    _isFitAll = !state.isEmpty && clamped >= state.maxTicksPerPixel;
    state = state.copyWith(ticksPerPixel: clamped).clamped();
  }

  /// Updates the viewport width, adjusting the zoom level appropriately.
  ///
  /// - **Fit-all mode** (`_isFitAll == true`): recalculates [ticksPerPixel]
  ///   so the full simulation range always fills the new viewport width.
  /// - **Zoomed-in mode**: preserves [ticksPerPixel] so more or less of the
  ///   waveform becomes visible as the window grows or shrinks. If the new
  ///   viewport is wide enough to show the entire simulation at the current
  ///   zoom level, the view snaps to fit-all and fit-all mode is re-entered.
  ///
  /// Call this when the waveform canvas widget is resized.
  void updateViewportWidth(double width) {
    if (_isFitAll && !state.isEmpty) {
      state = TimeMapper.fitAll(
        startTime: state.startTime,
        endTime: state.endTime,
        viewportWidth: width,
      );
      return;
    }
    final newMapper = state.withViewportWidth(width).clamped();
    // Snap to fit-all when the viewport has grown large enough to show the
    // entire simulation at the current zoom level.
    if (!state.isEmpty &&
        newMapper.ticksPerPixel >= newMapper.maxTicksPerPixel) {
      _isFitAll = true;
      state = newMapper.fitAll();
    } else {
      state = newMapper;
    }
  }
}

/// The simulation time visible at the left and right edges of the viewport.
///
/// Derived from [timeMapperProvider]; updates automatically on
/// zoom/pan.
@riverpod
(int, int) visibleTimeRange(Ref ref) {
  final mapper = ref.watch(timeMapperProvider);
  return (mapper.visibleStartTime, mapper.visibleEndTime);
}

/// The active simulation timescale, derived from the loaded waveform file.
///
/// Returns `null` when no waveform is loaded.
@riverpod
Timescale? currentTimescale(Ref ref) {
  final source = ref.watch(waveformSourceProvider);
  return source.value?.timescale;
}

/// Pre-computed time ruler tick marks at the current zoom level.
///
/// Recomputed automatically whenever the viewport zoom/pan changes or a new
/// file is loaded.
@riverpod
TimeRulerData timeRulerData(Ref ref) {
  final mapper = ref.watch(timeMapperProvider);
  final timescale = ref.watch(currentTimescaleProvider);
  return TimeRulerData.compute(
    mapper,
    mapper.viewportWidth,
    timescale: timescale,
  );
}
