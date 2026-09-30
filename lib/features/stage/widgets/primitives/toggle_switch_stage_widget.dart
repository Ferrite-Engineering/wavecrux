// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Pure logic: returns the target slider position as a fraction in [0, 1]
/// where 0 = OFF (left) and 1 = ON (right). X/Z values pin the knob halfway
/// so the user can immediately see something is wrong.
double toggleTargetPosition(StageSignalSnapshot snapshot) {
  if (!snapshot.hasValue) return 0;
  if (snapshot.hasX || snapshot.hasZ) return 0.5;
  final bits = snapshot.cleanBits;
  if (bits.isEmpty) return 0;
  return bits[bits.length - 1] == '1' ? 1 : 0;
}

/// Definition for the toggle-switch primitive Stage widget.
class ToggleSwitchStageWidget extends StageWidget {
  const ToggleSwitchStageWidget();

  static const String widgetId = 'toggle_switch';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Toggle Switch';

  @override
  String? get displayNameKey => 'stageToggleSwitchDisplayName';

  @override
  String get description =>
      'Slide-switch indicator that animates between on / off as the cursor moves.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'in',
      description: '1-bit signal driving the switch position',
      bitWidth: 1,
    ),
  ];

  @override
  (double, double) get defaultSize => (140, 80);

  /// Toggle switches need enough room for the knob to translate
  /// visibly. The minimum is square so a user can drag the tile into
  /// either orientation — the renderer chooses horizontal vs vertical
  /// from the actual slot aspect.
  @override
  (double, double) get minSize => (44, 44);
}

/// Renders a [ToggleSwitchStageWidget] instance.
class ToggleSwitchStageRenderer extends ConsumerWidget {
  const ToggleSwitchStageRenderer({required this.instance, super.key});

  final StageInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final binding = instance.signalBindings['in'];
    final snapshot = ref.watch(stageBoundSignalProvider(binding));
    final target = toggleTargetPosition(snapshot);
    final visual = ledVisualStateFor(snapshot);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Choose orientation from the slot's aspect ratio. Real Basys 3
        // / DE10-Lite slide switches are physically vertical (slid up
        // = on, down = off), and the board slots are tall-narrow, so
        // we render vertical when the slot is meaningfully taller
        // than wide. The 1.2 fudge factor avoids flapping near
        // square sizes.
        final isVertical =
            constraints.hasBoundedHeight &&
            constraints.hasBoundedWidth &&
            constraints.maxHeight > constraints.maxWidth * 1.2;
        final aspect = isVertical ? 1 / 2.5 : 2.5;

        return Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: target, end: target),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                builder: (context, position, _) => CustomPaint(
                  painter: _ToggleSwitchPainter(
                    position: position,
                    visual: visual,
                    isVertical: isVertical,
                  ),
                  child: SizedBox.expand(
                    child: Semantics(
                      label: l10n.stageToggleSemanticLabel(
                        switch (visual) {
                          LedVisualState.on => '1',
                          LedVisualState.off => '0',
                          LedVisualState.unknown => 'X',
                          LedVisualState.highImpedance => 'Z',
                          LedVisualState.inactive => '–',
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToggleSwitchPainter extends CustomPainter {
  _ToggleSwitchPainter({
    required this.position,
    required this.visual,
    this.isVertical = false,
  });

  final double position;
  final LedVisualState visual;
  final bool isVertical;

  @override
  void paint(Canvas canvas, Size size) {
    // Major axis = the long dimension (slide direction). Minor axis =
    // the track width. For horizontal mode major=width; for vertical
    // mode major=height (slid up=on, down=off — Basys 3 style).
    final major = isVertical ? size.height : size.width;
    final minor = isVertical ? size.width : size.height;
    final trackMajor = major * 0.85;
    final trackMinor = minor * 0.45;
    final centerOffset = Offset(size.width / 2, size.height / 2);
    final track = Rect.fromCenter(
      center: centerOffset,
      width: isVertical ? trackMinor : trackMajor,
      height: isVertical ? trackMajor : trackMinor,
    );
    final radius = Radius.circular(
      (isVertical ? track.width : track.height) / 2,
    );

    final isOn = visual == LedVisualState.on;
    final trackColor = switch (visual) {
      LedVisualState.on => const Color(0xFF1B5E20),
      LedVisualState.off => const Color(0xFF263238),
      LedVisualState.unknown => const Color(0xFF7C4A00),
      LedVisualState.highImpedance => const Color(0xFF37474F),
      LedVisualState.inactive => const Color(0xFF263238),
    };

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(track, radius),
        Paint()..color = trackColor,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(track, radius),
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    final knobR = (isVertical ? track.width : track.height) / 2 * 0.9;
    final Offset knobCenter;
    if (isVertical) {
      // position=0 (off) → knob at the BOTTOM of the track,
      // position=1 (on) → knob at the TOP. Matches a real slide
      // switch where pushing the slider up turns the input on.
      final bottomY = track.bottom - knobR - 2;
      final topY = track.top + knobR + 2;
      knobCenter = Offset(
        track.center.dx,
        bottomY * (1 - position) + topY * position,
      );
    } else {
      final lx = track.left + knobR + 2;
      final rx = track.right - knobR - 2;
      knobCenter = Offset(lx + (rx - lx) * position, track.center.dy);
    }
    final knobColor = isOn ? const Color(0xFFE0F2F1) : const Color(0xFFB0BEC5);

    canvas
      ..drawCircle(knobCenter, knobR, Paint()..color = knobColor)
      ..drawCircle(
        knobCenter,
        knobR,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
  }

  @override
  bool shouldRepaint(covariant _ToggleSwitchPainter old) =>
      old.position != position ||
      old.visual != visual ||
      old.isVertical != isVertical;
}
