// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/time_selection.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

part 'navigation_provider.g.dart';

/// Manages waveform navigation actions and the active time-range selection.
///
/// All zoom/pan operations delegate to [TimeMapperNotifier]; this provider adds
/// keyboard/gesture-friendly convenience methods and tracks the user's
/// drag-selected [TimeSelection] for zoom-to-selection.
///
/// ### Zoom factor
/// Keyboard and programmatic zoom steps use [zoomFactor] (1.5×) so each step
/// is predictable and reversible.
///
/// ### Pan increments
/// - [panLeft] / [panRight] with `small: false` (default) — 10 % of the
///   visible viewport per step (WASD / A-D key navigation).
/// - `small: true` — 3 % per step (arrow-key fine navigation).
@riverpod
class NavigationNotifier extends _$NavigationNotifier {
  @override
  TimeSelection? build() => null;

  /// Zoom factor applied per keyboard or programmatic zoom step.
  static const double zoomFactor = 1.5;

  static const double _panFractionLarge = 0.10;
  static const double _panFractionSmall = 0.03;

  TimeMapper get _mapper => ref.read(timeMapperProvider);
  TimeMapperNotifier get _mapperNotifier =>
      ref.read(timeMapperProvider.notifier);

  // ── zoom ────────────────────────────────────────────────────────────────────

  /// Zooms in by [zoomFactor]×, centred on [focalPixel].
  ///
  /// When [focalPixel] is null the viewport centre is used (keyboard zoom).
  void zoomIn({double? focalPixel}) {
    final focal = focalPixel ?? _mapper.viewportWidth / 2;
    _mapperNotifier.zoomIn(focalPixel: focal, factor: zoomFactor);
  }

  /// Zooms out by [zoomFactor]×, centred on [focalPixel].
  ///
  /// When [focalPixel] is null the viewport centre is used (keyboard zoom).
  void zoomOut({double? focalPixel}) {
    final focal = focalPixel ?? _mapper.viewportWidth / 2;
    _mapperNotifier.zoomOut(focalPixel: focal, factor: zoomFactor);
  }

  // ── pan ─────────────────────────────────────────────────────────────────────

  /// Pans left (earlier in time) by a fraction of the viewport width.
  ///
  /// Pass `small: true` for fine navigation (arrow keys); default is coarse
  /// navigation (A/D, WASD).
  void panLeft({bool small = false}) {
    final fraction = small ? _panFractionSmall : _panFractionLarge;
    _mapperNotifier.pan(-_mapper.viewportWidth * fraction);
  }

  /// Pans right (later in time) by a fraction of the viewport width.
  void panRight({bool small = false}) {
    final fraction = small ? _panFractionSmall : _panFractionLarge;
    _mapperNotifier.pan(_mapper.viewportWidth * fraction);
  }

  // ── fit / jump ───────────────────────────────────────────────────────────────

  /// Zooms to show the full simulation time range.
  void fitAll() => _mapperNotifier.fitAll();

  /// Pans to show the simulation start time at the left viewport edge.
  void jumpToStart() {
    final mapper = _mapper;
    if (mapper.isEmpty) return;
    _mapperNotifier.panByTime(
      (mapper.startTime - mapper.panOffsetTicks).round(),
    );
  }

  /// Pans to show the simulation end time at the right viewport edge.
  void jumpToEnd() {
    final mapper = _mapper;
    if (mapper.isEmpty) return;
    final targetPan =
        mapper.endTime - mapper.viewportWidth * mapper.ticksPerPixel;
    _mapperNotifier.panByTime((targetPan - mapper.panOffsetTicks).round());
  }

  /// Centres the viewport on [time] without changing the zoom level.
  void jumpToTime(int time) {
    final mapper = _mapper;
    if (mapper.isEmpty) return;
    final targetPan = time - (mapper.viewportWidth / 2) * mapper.ticksPerPixel;
    _mapperNotifier.panByTime((targetPan - mapper.panOffsetTicks).round());
  }

  // ── zoom-to-selection ────────────────────────────────────────────────────────

  /// Zooms to show the explicit tick range [[start], [end]].
  void fitRange(int start, int end) => _mapperNotifier.zoomToRange(start, end);

  /// Zooms to show the current [TimeSelection] and clears it.
  ///
  /// No-op when the selection is null or empty.
  void zoomToSelection() {
    final sel = state?.normalized();
    if (sel == null || sel.isEmpty) return;
    _mapperNotifier.zoomToRange(sel.startTime, sel.endTime);
    state = null;
  }

  /// Updates the active drag selection.
  ///
  /// Pass `null` to clear the selection.
  // A setter cannot be named 'selection' because _$NavigationNotifier already
  // exposes 'state'; a named method is clearer at the call site.
  // ignore: use_setters_to_change_properties
  void setSelection(TimeSelection? selection) => state = selection;

  /// Clears the active drag selection without zooming.
  void clearSelection() => state = null;
}
