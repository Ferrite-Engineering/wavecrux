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
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Maps a [StageSignalSnapshot] to one of four LED visual states.
enum LedVisualState {
  /// Pin is unbound or no waveform is loaded.
  inactive,

  /// Bit is `1` — LED glows in its on-color.
  on,

  /// Bit is `0` — LED is dim in its off-color.
  off,

  /// Bit is `x` — LED renders amber to flag the unknown.
  unknown,

  /// Bit is `z` — LED renders with diagonal hatching.
  highImpedance,
}

/// Pure logic: choose [LedVisualState] from a snapshot and bit-string.
///
/// 1-bit signals look at the cleaned bit value directly. Wider signals are
/// reduced to their least-significant bit, matching GTKWave behavior when
/// users wire a multi-bit bus to a 1-bit indicator.
LedVisualState ledVisualStateFor(StageSignalSnapshot snapshot) {
  if (!snapshot.hasValue) return LedVisualState.inactive;
  final bits = snapshot.cleanBits;
  if (bits.isEmpty) return LedVisualState.inactive;
  final lsb = bits[bits.length - 1];
  return switch (lsb) {
    '1' => LedVisualState.on,
    '0' => LedVisualState.off,
    'x' => LedVisualState.unknown,
    'z' => LedVisualState.highImpedance,
    _ => LedVisualState.inactive,
  };
}

/// Definition for the LED primitive Stage widget.
class LedStageWidget extends StageWidget {
  const LedStageWidget();

  static const String widgetId = 'led';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'LED';

  @override
  String? get displayNameKey => 'stageLedDisplayName';

  @override
  String get description =>
      'Single bit signal rendered as a glowing indicator.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'in',
      description: '1-bit signal driving the LED',
      bitWidth: 1,
    ),
  ];

  @override
  (double, double) get defaultSize => (96, 96);

  @override
  (double, double) get minSize => (32, 32);
}

/// Renders a [LedStageWidget] instance.
class LedStageRenderer extends ConsumerWidget {
  const LedStageRenderer({
    required this.instance,
    this.onColor = const Color(0xFF00E676),
    this.offColor = const Color(0xFF1B1B1B),
    super.key,
  });

  final StageInstance instance;
  final Color onColor;
  final Color offColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final binding = instance.signalBindings['in'];
    final snapshot = ref.watch(stageBoundSignalProvider(binding));
    final visual = ledVisualStateFor(snapshot);

    final label = switch (visual) {
      LedVisualState.on => '1',
      LedVisualState.off => '0',
      LedVisualState.unknown => 'X',
      LedVisualState.highImpedance => 'Z',
      LedVisualState.inactive => '–',
    };

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          // Tight 2dp inset — the AspectRatio already centers the
          // bulb in the available space; the larger 8dp padding used
          // to be eaten entirely at small slot sizes (e.g. inside a
          // shrunk Basys 3) leaving no room for the painter.
          padding: const EdgeInsets.all(2),
          child: CustomPaint(
            painter: _LedPainter(
              visual: visual,
              onColor: onColor,
              offColor: offColor,
            ),
            child: Center(
              // FittedBox scales the label down to fit inside the
              // bulb, regardless of slot size. Without this the
              // 14 sp glyph spilled out of small LEDs (the minus
              // sign in particular extended below the circle).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    label,
                    semanticsLabel: l10n.stageLedSemanticLabel(label),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: visual == LedVisualState.on
                          ? Colors.black87
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LedPainter extends CustomPainter {
  _LedPainter({
    required this.visual,
    required this.onColor,
    required this.offColor,
  });

  final LedVisualState visual;
  final Color onColor;
  final Color offColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final fill = switch (visual) {
      LedVisualState.on => onColor,
      LedVisualState.off => offColor,
      LedVisualState.unknown => const Color(0xFFFFB300),
      LedVisualState.highImpedance => const Color(0xFF455A64),
      LedVisualState.inactive => const Color(0xFF263238),
    };

    if (visual == LedVisualState.on) {
      // Soft glow.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = onColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    canvas.drawCircle(center, radius * 0.85, Paint()..color = fill);

    // Z-state: diagonal hatched overlay over the dim bulb.
    if (visual == LedVisualState.highImpedance) {
      final hatchPaint = Paint()
        ..color = const Color(0xFFB0BEC5)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas
        ..save()
        ..clipPath(
          Path()
            ..addOval(Rect.fromCircle(center: center, radius: radius * 0.85)),
        );
      const step = 4.0;
      for (var d = -size.width; d < size.width * 2; d += step) {
        canvas.drawLine(
          Offset(d, 0),
          Offset(d + size.height, size.height),
          hatchPaint,
        );
      }
      canvas.restore();
    }

    // Outer rim.
    canvas.drawCircle(
      center,
      radius * 0.85,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _LedPainter old) =>
      old.visual != visual ||
      old.onColor != onColor ||
      old.offColor != offColor;
}
