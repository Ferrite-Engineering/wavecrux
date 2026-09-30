// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

/// Scroll `dragDevices` set with `trackpad` (and `mouse`) removed.
///
/// The app-wide `ScrollConfiguration` in `app.dart` puts `trackpad` back into
/// `dragDevices` so every plain list/panel scrolls under a two-finger trackpad
/// pan. A handful of widgets instead own trackpad gestures themselves — the
/// waveform canvas (pinch-zoom / pan / lane-scroll via [WaveformGestureHandler])
/// and the [TrackpadScrollListener]-wrapped scrollables (signal-list names
/// column, command palette). Those wrap their scroll view in a
/// `ScrollConfiguration` using this set so the native [Scrollable] does NOT also
/// drag-scroll on the same pan-zoom gesture and double-drive the offset.
const Set<PointerDeviceKind> kTrackpadOwnedDragDevices = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

/// Forwards trackpad two-finger vertical scroll gestures (iPad Magic Keyboard,
/// macOS) to a [ScrollController] that controls the [child].
///
/// Flutter's [Scrollable] handles mouse-wheel [PointerScrollEvent] natively
/// but does NOT respond to [PointerPanZoomUpdateEvent] — the gesture iPadOS
/// emits when you swipe two fingers on the trackpad. Without this wrapper a
/// trackpad swipe over a [ListView] / [ReorderableListView] does nothing on
/// iPad. Wrap the scrollable in this widget and pass its `scrollController`
/// to forward the vertical pan delta to the controller.
///
/// Usage:
/// ```dart
/// TrackpadScrollListener(
///   controller: scrollController,
///   child: ListView(controller: scrollController, ...),
/// )
/// ```
class TrackpadScrollListener extends StatelessWidget {
  const TrackpadScrollListener({
    required this.controller,
    required this.child,
    super.key,
  });

  /// Scroll controller to drive on trackpad pan-zoom events.  Must be
  /// attached to the scrollable rendered inside [child].
  final ScrollController controller;

  /// Child widget — typically a scrollable.
  final Widget child;

  void _scrollBy(double delta) {
    if (!controller.hasClients) return;
    final position = controller.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    controller.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) => Listener(
    // [HitTestBehavior.translucent] ensures we receive pan-zoom events
    // even when the descendant scrollable would otherwise consume the
    // hit. The inner [Scrollable] does not subscribe to PointerPanZoom
    // events (it only handles PointerScrollEvent), so adding our
    // listener as translucent doesn't conflict — both layers can see
    // the event, and only this listener actually does anything with it.
    behavior: HitTestBehavior.translucent,
    onPointerPanZoomUpdate: (event) {
      // PointerPanZoomUpdate carries a `scale` (pinch) and a `panDelta`
      // (two-finger swipe). On iPad/macOS, plain two-finger vertical
      // scroll arrives here. Forward dy negated so swiping down moves
      // the viewport up (natural-scroll convention).
      final dy = event.panDelta.dy;
      if (dy != 0) _scrollBy(-dy);
    },
    child: child,
  );
}
