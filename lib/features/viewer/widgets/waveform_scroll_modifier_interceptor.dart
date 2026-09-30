// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

/// Intercepts mouse [PointerScrollEvent]s that should drive the waveform rather
/// than scroll the signal list, claiming them via
/// [GestureBinding.pointerSignalResolver] before the enclosing
/// [SingleChildScrollView] can register.
///
/// **Placement rule:** this widget must be the **direct child** of
/// [SingleChildScrollView] (i.e. between the scroll view and its content).
/// Flutter dispatches pointer events innermost-widget-first, so this listener
/// is dispatched before the [Scrollable] ancestor. Registering first in
/// [GestureBinding.pointerSignalResolver] means the scroll view's vertical
/// scroll is suppressed while the waveform zooms or pans.
///
/// The plain-wheel / Shift-wheel mapping depends on the `wheelNavigatesTime`
/// setting:
///
/// | Modifier      | scroll-signals (default) | navigate-time (GTKWave) |
/// |---------------|--------------------------|-------------------------|
/// | Ctrl/Cmd      | zoom around pointer      | zoom around pointer     |
/// | Shift         | pan time                 | scroll signal list      |
/// | (none)        | scroll signal list       | pan time                |
///
/// "Scroll signal list" in the default-mode plain-wheel case is achieved by
/// *not* claiming the event so it reaches the [SingleChildScrollView]; in every
/// claimed case the lane list is driven through [onVerticalScroll] (the same
/// callback the gesture handler uses) so it works regardless of how the host OS
/// reports a Shift+wheel delta.
class WaveformScrollModifierInterceptor extends ConsumerWidget {
  const WaveformScrollModifierInterceptor({
    required this.child,
    this.onVerticalScroll,
    super.key,
  });

  final Widget child;

  /// Drives the lane-list scroll controller by [delta] pixels (positive scrolls
  /// down). Supplied by [WaveformCanvas]; when null, claimed vertical-scroll
  /// intents are simply dropped.
  final void Function(double delta)? onVerticalScroll;

  static const double _zoomFactor = 1.1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigatesTime = ref.watch(wheelNavigatesTimeProvider);
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (event.kind != PointerDeviceKind.mouse) return;

        final ctrl =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;

        // Decide what this event does. `null` means "let it fall through" so
        // the SingleChildScrollView scrolls the lane list natively.
        final _WheelIntent? intent;
        if (ctrl) {
          intent = _WheelIntent.zoom;
        } else if (navigatesTime) {
          intent = shift ? _WheelIntent.scrollList : _WheelIntent.panTime;
        } else {
          // Default mode: plain wheel falls through to native vertical scroll.
          intent = shift ? _WheelIntent.panTime : null;
        }
        if (intent == null) return;

        // Register before the Scrollable ancestor so the resolver's
        // first-come-first-served policy prevents vertical lane-list scrolling.
        GestureBinding.instance.pointerSignalResolver.register(event, (e) {
          if (e is! PointerScrollEvent) return;
          final notifier = ref.read(timeMapperProvider.notifier);
          final amount = e.scrollDelta.dy != 0
              ? e.scrollDelta.dy
              : e.scrollDelta.dx;
          switch (intent!) {
            case _WheelIntent.zoom:
              if (e.scrollDelta.dy < 0) {
                notifier.zoomIn(
                  focalPixel: e.localPosition.dx,
                  factor: _zoomFactor,
                );
              } else if (e.scrollDelta.dy > 0) {
                notifier.zoomOut(
                  focalPixel: e.localPosition.dx,
                  factor: _zoomFactor,
                );
              }
            case _WheelIntent.panTime:
              if (amount != 0) notifier.pan(amount);
            case _WheelIntent.scrollList:
              if (amount != 0) onVerticalScroll?.call(amount);
          }
        });
      },
      child: child,
    );
  }
}

/// What a claimed mouse-wheel event does this frame.
enum _WheelIntent { zoom, panTime, scrollList }
