// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/time_selection.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

/// Wraps [child] with all pointer and gesture handling for the waveform canvas.
///
/// ### Mouse gestures
/// | Interaction | Effect |
/// |---|---|
/// | Left click | Place primary cursor |
/// | Shift + left click | Place secondary cursor |
/// | Alt/Option + left click | Author a callout at that point |
/// | Alt/Option + left drag | Author an arrow from that point to the release |
/// | Right click | Place secondary cursor |
/// | Left drag | Move primary cursor |
/// | Middle mouse drag | Pan the time window |
/// | Ctrl/Cmd + left drag | Pan the time window |
/// | Shift + left drag | Drag-select a time range (for zoom-to-selection) |
/// | Scroll wheel up/down | Scroll signal-lane list vertically |
/// | Ctrl/Cmd + scroll wheel | Zoom in / out around pointer position |
/// | Shift + scroll wheel | Pan the time window left / right |
/// | Horizontal tilt-wheel | Pan the time window left / right |
///
/// ### Touch / trackpad gestures
/// | Interaction | Effect |
/// |---|---|
/// | Single-finger tap | Place primary cursor |
/// | Single-finger drag | Pan the time window |
/// | Two-finger pinch | Zoom in / out around pinch centre |
/// | Two-finger horizontal drag | Pan the time window |
/// | Two-finger vertical scroll | Zoom in / out (via PointerScrollEvent fallback) |
///
/// Cursor placement and zoom/pan delegate to [NavigationNotifier] and
/// [CursorStateNotifier] via Riverpod providers. Using [Listener] (not
/// [GestureDetector]) gives full access to button flags and modifier keys
/// without competing with the [SingleChildScrollView] that handles vertical
/// scrolling inside [child].
class WaveformGestureHandler extends ConsumerStatefulWidget {
  const WaveformGestureHandler({
    required this.child,
    this.onPrimaryTap,
    this.onLongPress,
    this.onAltTap,
    this.onAltDragStart,
    this.onAltDragUpdate,
    this.onAltDragEnd,
    this.onVerticalScroll,
    super.key,
  });

  /// The widget that receives pointer events — typically the waveform canvas
  /// content wrapped in a [SingleChildScrollView].
  final Widget child;

  /// Called with the viewport-local tap position when a non-shift, non-right
  /// primary tap is finalized (i.e. the pointer was not dragged beyond slop).
  ///
  /// Fires *after* [CursorStateNotifier.placePrimary] so the cursor is already
  /// updated when the callback runs.  Callers can use the [Offset.dy] to
  /// hit-test transaction lanes.
  final void Function(Offset localPosition)? onPrimaryTap;

  /// Called when a touch pointer is held stationary (within slop) for
  /// [_kLongPressDuration].  Mouse and trackpad inputs never fire this —
  /// desktop users get a context menu via right-click (which the canvas does
  /// not currently consume).  When this fires, the pending touch is canceled
  /// so it does not also fire [onPrimaryTap] on release.
  ///
  /// [globalPosition] is the screen-relative position of the press (for
  /// anchoring popup menus).  [localPosition] is the canvas-local position
  /// (for computing the time at the press point via the time mapper).
  final void Function(Offset globalPosition, Offset localPosition)? onLongPress;

  /// Called with the canvas-local position of an Alt/Option + primary click.
  ///
  /// Placed on Alt because the other primary-button modifiers on this canvas
  /// are taken: shift+click seeds a time selection and right-click places the
  /// secondary cursor. When this fires no cursor is placed — the click was a
  /// deliberate authoring gesture, not navigation.
  final void Function(Offset localPosition)? onAltTap;

  /// Called when an Alt/Option + primary press turns into a **drag**, with the
  /// canvas-local position the press started at.
  ///
  /// Alt-click authors a callout at a point; Alt-drag authors an arrow from
  /// that point to wherever the pointer is released. Same modifier, same
  /// anchor, and the shape falls out of whether the user moved — which is how
  /// the gesture teaches itself without a mode switch or a toolbar.
  final void Function(Offset localPosition)? onAltDragStart;

  /// Called with each pointer delta while an Alt-drag is in flight.
  final void Function(Offset delta)? onAltDragUpdate;

  /// Called when an Alt-drag finishes or is cancelled.
  final VoidCallback? onAltDragEnd;

  /// Called with a positive-down vertical pixel delta when the user performs a
  /// trackpad two-finger vertical scroll (iPad Magic Keyboard, macOS) or
  /// receives momentum vertical scroll inertia.  The host widget should scroll
  /// its lane-list `ScrollController` by [delta] so the signal list, value
  /// column, and waveform canvas stay synchronized.
  ///
  /// Mouse-wheel vertical scroll falls through to the inner
  /// [SingleChildScrollView] and does NOT call this — the Scrollable's native
  /// pointer-signal handling already deals with mouse wheels correctly.
  final void Function(double delta)? onVerticalScroll;

  @override
  ConsumerState<WaveformGestureHandler> createState() =>
      _WaveformGestureHandlerState();
}

/// Standard long-press hold time, matching Flutter's [LongPressGestureRecognizer].
const Duration _kLongPressDuration = Duration(milliseconds: 500);

// ── Drag mode ─────────────────────────────────────────────────────────────────

enum _DragMode { pan, select, cursor, annotate }

// ── State ─────────────────────────────────────────────────────────────────────

class _WaveformGestureHandlerState
    extends ConsumerState<WaveformGestureHandler> {
  // Distance a pointer must travel before a drag is detected (mouse / stylus).
  static const double _tapSlop = 8;

  // Larger slop for touch input: natural finger movement during a tap can
  // easily exceed 8 px, so we require more distance before committing to a drag.
  static const double _touchTapSlop = 16;

  // Whether the current down-move-up sequence was initiated by a touch pointer.
  // Used to select the appropriate slop value and drag default.
  bool _currentIsTouch = false;

  // Horizontal distance (px) within which a hover is considered "on" a cursor
  // line and the resize cursor is shown.
  static const int _cursorHitRadius = 5;

  // True while the pointer is hovering within [_cursorHitRadius] of any cursor.
  bool _hoveringCursor = false;

  void _onHover(PointerHoverEvent event) {
    final timeMapper = ref.read(timeMapperProvider);
    final cursorState = ref.read(cursorStateProvider);
    final x = event.localPosition.dx;

    var near = false;
    final primTime = cursorState.primaryCursorTime;
    if (primTime != null &&
        (x - timeMapper.timeToPixel(primTime)).abs() <= _cursorHitRadius) {
      near = true;
    }
    if (!near) {
      final secTime = cursorState.secondaryCursorTime;
      if (secTime != null &&
          (x - timeMapper.timeToPixel(secTime)).abs() <= _cursorHitRadius) {
        near = true;
      }
    }
    if (near != _hoveringCursor) setState(() => _hoveringCursor = near);
  }

  // ── edge auto-scroll (cursor drag) ────────────────────────────────────────

  // Pixels from the edge at which auto-scroll begins.
  static const double _edgeScrollZone = 40;
  // Maximum pan speed (pixels/frame) at the extreme edge.
  static const double _edgeScrollMaxSpeed = 8;

  Timer? _edgeScrollTimer;
  Offset? _lastPointerPosition;

  void _startEdgeScroll() {
    _edgeScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickEdgeScroll(),
    );
  }

  void _stopEdgeScroll() {
    _edgeScrollTimer?.cancel();
    _edgeScrollTimer = null;
  }

  void _tickEdgeScroll() {
    if (!mounted) {
      _stopEdgeScroll();
      return;
    }
    final pos = _lastPointerPosition;
    if (pos == null) {
      _stopEdgeScroll();
      return;
    }
    final mapper = ref.read(timeMapperProvider);
    final vw = mapper.viewportWidth;

    double panDelta = 0;
    if (pos.dx > vw - _edgeScrollZone) {
      panDelta =
          ((pos.dx - (vw - _edgeScrollZone)) / _edgeScrollZone) *
          _edgeScrollMaxSpeed;
    } else if (pos.dx < _edgeScrollZone) {
      panDelta =
          -((_edgeScrollZone - pos.dx) / _edgeScrollZone) * _edgeScrollMaxSpeed;
    }

    if (panDelta == 0) {
      _stopEdgeScroll();
      return;
    }

    ref.read(timeMapperProvider.notifier).pan(panDelta);
    final newMapper = ref.read(timeMapperProvider);
    final time = newMapper.pixelToTime(pos.dx);
    ref.read(cursorStateProvider.notifier).placePrimary(time);
  }

  // ── mouse / single-touch state ─────────────────────────────────────────────

  Offset? _pointerDownPosition;
  Offset? _pointerDownGlobalPosition;
  bool _movedSignificantly = false;
  int _mouseButtons = 0;
  bool _wasShiftOnDown = false;

  // Whether Alt/Option was held when the pointer went down. Captured on down
  // rather than read on up so releasing the modifier mid-click cannot turn an
  // authoring gesture into a cursor placement.
  bool _wasAltOnDown = false;
  _DragMode? _dragMode;

  // ── long-press state (touch only) ──────────────────────────────────────────

  // Fires after [_kLongPressDuration] of a stationary touch.  Cancelled if
  // the pointer moves beyond slop, lifts, or is cancelled before then.
  Timer? _longPressTimer;
  // True after [_longPressTimer] has fired and we have suppressed the rest
  // of this touch sequence (no tap on release, no pan on subsequent moves).
  bool _longPressFired = false;

  // ── multi-touch state ──────────────────────────────────────────────────────

  final Map<int, Offset> _touches = {};
  double? _lastPinchDistance;
  double? _lastTwoFingerCenterX;

  // ── trackpad pan-zoom state (macOS PointerPanZoom* events) ─────────────────

  // Tracks the cumulative scale from the start of a trackpad pinch gesture so
  // we can compute per-event delta ratios for zoom.
  double _panZoomScale = 1;

  // ── modifier key helpers ───────────────────────────────────────────────────

  bool get _shiftPressed => HardwareKeyboard.instance.isShiftPressed;
  bool get _altPressed => HardwareKeyboard.instance.isAltPressed;
  bool get _ctrlPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  static bool _isTouchKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;

  // ── pointer down ──────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    // An annotation affordance claimed this sequence. Pointer events dispatch
    // deepest-first, so the balloon's Listener has already run and this handler
    // must stand down for the whole gesture — otherwise dragging a note also
    // drags the primary cursor, because a raw Listener sees every event in its
    // subtree regardless of what a descendant GestureDetector does.
    if (ref.read(annotationGestureActiveProvider)) return;

    if (_isTouchKind(event.kind)) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length == 1) {
        _pointerDownPosition = event.localPosition;
        _pointerDownGlobalPosition = event.position;
        _movedSignificantly = false;
        _wasShiftOnDown = false;
        _wasAltOnDown = false;
        _currentIsTouch = true;
        _longPressFired = false;
        // Don't commit to pan yet — wait for either movement (→ pan) or the
        // long-press timer to fire (→ context menu).  Tap on release without
        // movement still places the primary cursor.
        _dragMode = null;
        if (widget.onLongPress != null) _startLongPressTimer();
      } else if (_touches.length == 2) {
        _cancelLongPressTimer();
        _initTwoFingerState();
      }
      return;
    }

    // ── mouse ────────────────────────────────────────────────────────────────

    // Right-click is handled as a secondary-cursor placement gesture; record
    // the button and position so the up event can place the cursor.
    _mouseButtons = event.buttons;
    _wasShiftOnDown = _shiftPressed;
    _wasAltOnDown = _altPressed;
    _pointerDownPosition = event.localPosition;
    _movedSignificantly = false;
    _currentIsTouch = false;

    final isMiddle = event.buttons & kMiddleMouseButton != 0;
    final isPrimary = event.buttons & kPrimaryMouseButton != 0;
    final isSecondary = event.buttons & kSecondaryMouseButton != 0;

    if (isSecondary) {
      // Right click: treated as a simple tap — no drag mode.
      _dragMode = null;
    } else if (isMiddle || (isPrimary && _ctrlPressed)) {
      // Middle button or Ctrl+left: force pan from the start.
      _dragMode = _DragMode.pan;
    } else if (isPrimary && _shiftPressed) {
      // Shift+left: start a selection drag; seed selection at current position.
      _dragMode = _DragMode.select;
      final time = ref
          .read(timeMapperProvider)
          .pixelToTime(event.localPosition.dx);
      ref
          .read(navigationProvider.notifier)
          .setSelection(TimeSelection(startTime: time, endTime: time));
    } else {
      // Plain left click: drag resolves to cursor-move once slop is crossed.
      _dragMode = null;
    }
  }

  // ── long-press timer ──────────────────────────────────────────────────────

  void _startLongPressTimer() {
    _cancelLongPressTimer();
    _longPressTimer = Timer(_kLongPressDuration, _firelongPress);
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _firelongPress() {
    final globalPos = _pointerDownGlobalPosition;
    final localPos = _pointerDownPosition;
    final cb = widget.onLongPress;
    if (globalPos == null || localPos == null || cb == null || !mounted) {
      return;
    }
    _longPressFired = true;
    // Suppress the rest of this touch sequence so release doesn't fire
    // onPrimaryTap and any movement that follows doesn't pan the timeline.
    _dragMode = null;
    _movedSignificantly = false;
    cb(globalPos, localPos);
  }

  // ── pointer move ──────────────────────────────────────────────────────────

  void _onPointerMove(PointerMoveEvent event) {
    if (ref.read(annotationGestureActiveProvider)) return;
    if (_isTouchKind(event.kind)) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length >= 2) {
        _handleTwoFingerMove();
      } else {
        _handleSinglePointerMove(event.localPosition, event.delta);
      }
      return;
    }

    _handleSinglePointerMove(event.localPosition, event.delta);
  }

  void _handleSinglePointerMove(Offset position, Offset delta) {
    final dx = delta.dx;
    if (_longPressFired) return; // Suppress drag after a long-press fired.
    final origin = _pointerDownPosition;
    if (origin == null) return;

    if (!_movedSignificantly) {
      final slop = _currentIsTouch ? _touchTapSlop : _tapSlop;
      if ((position - origin).distance >= slop) {
        _movedSignificantly = true;
        _cancelLongPressTimer();
        if (_currentIsTouch) {
          // Touch drag (after slop) pans the timeline.  Cursor placement on
          // touch happens via tap-on-release, not drag.
          _dragMode ??= _DragMode.pan;
        } else if (_wasAltOnDown && widget.onAltDragStart != null) {
          // Alt+drag authors an arrow rather than moving the cursor. Resolved
          // here rather than at pointer-down because Alt+*click* must stay a
          // callout — the shape is decided by whether the pointer travelled.
          _dragMode = _DragMode.annotate;
          widget.onAltDragStart!(origin);
        } else {
          // Mouse: plain left drag moves cursor; Middle/Ctrl+drag uses pan
          // (already resolved at pointer-down).
          _dragMode ??= _DragMode.cursor;
        }
      }
    }

    if (!_movedSignificantly) return;

    switch (_dragMode) {
      case _DragMode.pan:
        if (dx != 0) ref.read(timeMapperProvider.notifier).pan(-dx);
      case _DragMode.cursor:
        _lastPointerPosition = position;
        final time = ref.read(timeMapperProvider).pixelToTime(position.dx);
        ref.read(cursorStateProvider.notifier).placePrimary(time);
        final vw = ref.read(timeMapperProvider).viewportWidth;
        if (position.dx > vw - _edgeScrollZone ||
            position.dx < _edgeScrollZone) {
          _startEdgeScroll();
        } else {
          _stopEdgeScroll();
        }
      case _DragMode.annotate:
        widget.onAltDragUpdate?.call(delta);
      case _DragMode.select:
        final time = ref.read(timeMapperProvider).pixelToTime(position.dx);
        final current = ref.read(navigationProvider);
        if (current != null) {
          ref
              .read(navigationProvider.notifier)
              .setSelection(
                TimeSelection(startTime: current.startTime, endTime: time),
              );
        }
      case null:
        break;
    }
  }

  // ── pointer up ────────────────────────────────────────────────────────────

  void _onPointerUp(PointerUpEvent event) {
    // The claim is released by the annotation's own Listener on this same
    // event; bailing here keeps the release from also placing a cursor.
    if (ref.read(annotationGestureActiveProvider)) return;
    if (_isTouchKind(event.kind)) {
      _touches.remove(event.pointer);
      if (_touches.isEmpty) {
        _cancelLongPressTimer();
        _finalizeSinglePointer(event.localPosition);
        _resetSinglePointerState();
      }
      _lastPinchDistance = null;
      _lastTwoFingerCenterX = null;
      return;
    }

    _finalizeSinglePointer(event.localPosition);
    _resetSinglePointerState();
  }

  void _finalizeSinglePointer(Offset position) {
    // An Alt-drag authored an arrow; it places no cursor and is not a tap.
    if (_dragMode == _DragMode.annotate) {
      widget.onAltDragEnd?.call();
      return;
    }
    // If a long-press already fired, the touch sequence is consumed — no tap.
    if (_longPressFired) return;
    // Treat this as a tap only when the pointer-up position is within _tapSlop
    // of the pointer-down position.  Checking the final displacement — rather
    // than the _movedSignificantly flag — is more robust on macOS trackpads,
    // where a physical click can produce brief pointer-move events that set
    // _movedSignificantly even though the finger ends up at the same spot.
    final origin = _pointerDownPosition;
    if (origin != null && (position - origin).distance >= _tapSlop) return;

    final isSecondary = _mouseButtons & kSecondaryMouseButton != 0;

    // Alt+click authors an annotation at the click point and places no cursor.
    // Right-click is already secondary-cursor placement and shift+click is
    // already a selection seed, so neither was available; Alt is the one
    // unclaimed primary-button modifier on this canvas.
    if (!isSecondary && _wasAltOnDown && widget.onAltTap != null) {
      widget.onAltTap!(position);
      return;
    }

    // It was a tap — place cursor.
    final time = ref.read(timeMapperProvider).pixelToTime(position.dx);

    if (isSecondary || _wasShiftOnDown) {
      ref.read(cursorStateProvider.notifier).placeSecondary(time);
    } else {
      ref.read(cursorStateProvider.notifier).placePrimary(time);
      widget.onPrimaryTap?.call(position);
    }
  }

  void _resetSinglePointerState() {
    _pointerDownPosition = null;
    _pointerDownGlobalPosition = null;
    _movedSignificantly = false;
    _mouseButtons = 0;
    _wasShiftOnDown = false;
    _wasAltOnDown = false;
    _dragMode = null;
    _currentIsTouch = false;
    _lastPointerPosition = null;
    _longPressFired = false;
    _cancelLongPressTimer();
    _stopEdgeScroll();
  }

  // ── pointer cancel ────────────────────────────────────────────────────────

  void _onPointerCancel(PointerCancelEvent event) {
    if (_dragMode == _DragMode.annotate) widget.onAltDragEnd?.call();
    _touches.remove(event.pointer);
    _resetSinglePointerState();
    _lastPinchDistance = null;
    _lastTwoFingerCenterX = null;
  }

  // ── two-finger gestures ───────────────────────────────────────────────────

  void _initTwoFingerState() {
    if (_touches.length < 2) return;
    final pts = _touches.values.toList();
    _lastPinchDistance = (pts[0] - pts[1]).distance;
    _lastTwoFingerCenterX = (pts[0].dx + pts[1].dx) / 2;
  }

  void _handleTwoFingerMove() {
    if (_touches.length < 2) return;
    final pts = _touches.values.toList();
    final newDistance = (pts[0] - pts[1]).distance;
    final newCenterX = (pts[0].dx + pts[1].dx) / 2;

    final lastDist = _lastPinchDistance;
    final lastCenterX = _lastTwoFingerCenterX;
    final notifier = ref.read(timeMapperProvider.notifier);

    // Pinch zoom: ratio of new to old finger distance is the zoom factor.
    if (lastDist != null && lastDist > 0 && newDistance > 0) {
      final ratio = newDistance / lastDist;
      final centerX = newCenterX;
      if (ratio >= 1.0) {
        notifier.zoomIn(focalPixel: centerX, factor: ratio);
      } else {
        notifier.zoomOut(focalPixel: centerX, factor: 1.0 / ratio);
      }
    }

    // Two-finger pan: horizontal component of the centre point movement.
    if (lastCenterX != null) {
      final dx = newCenterX - lastCenterX;
      if (dx.abs() > 0.5) notifier.pan(-dx);
    }

    _lastPinchDistance = newDistance;
    _lastTwoFingerCenterX = newCenterX;
  }

  // ── trackpad pan-zoom (macOS native gesture events) ──────────────────────

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomScale = 1.0;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final notifier = ref.read(timeMapperProvider.notifier);

    // Horizontal component → pan the waveform.
    // Negate so swiping right moves backward in time (grab-and-pull convention).
    final dx = event.panDelta.dx;
    if (dx != 0) notifier.pan(-dx);

    // Vertical component → scroll the lane list. Without this, two-finger
    // vertical scroll on the iPad Magic Keyboard trackpad does nothing inside
    // the canvas because the [Listener] consumes the pan-zoom event before the
    // inner [SingleChildScrollView] sees it. Negate so swiping up moves the
    // viewport up (natural-scroll convention matches macOS/iPad defaults).
    final dy = event.panDelta.dy;
    if (dy != 0) widget.onVerticalScroll?.call(-dy);

    // Scale component → pinch zoom around the gesture focal point.
    final scale = event.scale;
    if (scale > 0 && _panZoomScale > 0 && scale != _panZoomScale) {
      final ratio = scale / _panZoomScale;
      if (ratio > 1.0) {
        notifier.zoomIn(focalPixel: event.localPosition.dx, factor: ratio);
      } else if (ratio < 1.0) {
        notifier.zoomOut(
          focalPixel: event.localPosition.dx,
          factor: 1.0 / ratio,
        );
      }
    }
    _panZoomScale = scale;
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomScale = 1.0;
  }

  // ── scroll wheel ─────────────────────────────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final notifier = ref.read(timeMapperProvider.notifier);
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;

    if (event.kind == PointerDeviceKind.mouse) {
      // Ctrl/Cmd + scroll and Shift + scroll are claimed exclusively by
      // _ScrollModifierInterceptor (inside SingleChildScrollView in
      // WaveformCanvas). That widget registers via pointerSignalResolver before
      // Scrollable does, preventing the lane list from also scrolling. Do NOT
      // handle those cases here — doing so would cause a double zoom/pan.
      //
      // Plain vertical scroll: do nothing; SingleChildScrollView handles it.
      // Horizontal tilt-wheel without a modifier: pan.
      if (dx != 0 && !_ctrlPressed && !_shiftPressed) notifier.pan(dx);
      return;
    }

    // Trackpad / other device (e.g. momentum PointerScrollEvent on macOS).
    // Two-finger pinch and horizontal swipe generate PointerPanZoomUpdate
    // events (handled in _onPointerPanZoomUpdate). PointerScrollEvent from the
    // trackpad primarily carries inertia/momentum scrolling.
    // Horizontal → pan the time window; vertical → scroll the lane list.
    // (The previous zoom-on-vertical behavior fought the platform default —
    // every other macOS / iPadOS app scrolls a list with two-finger vertical
    // swipes; pinch-zoom is the dedicated zoom gesture, handled via
    // PointerPanZoomUpdate.scale.)
    if (dx != 0) notifier.pan(dx);
    if (dy != 0) widget.onVerticalScroll?.call(dy);
  }

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cancelLongPressTimer();
    _stopEdgeScroll();
    super.dispose();
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: _hoveringCursor
        ? SystemMouseCursors.resizeLeftRight
        : MouseCursor.defer,
    onHover: _onHover,
    onExit: (_) {
      if (_hoveringCursor) setState(() => _hoveringCursor = false);
    },
    child: Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomStart: _onPointerPanZoomStart,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      child: widget.child,
    ),
  );
}
