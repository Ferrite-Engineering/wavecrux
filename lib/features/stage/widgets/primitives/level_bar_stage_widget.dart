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

/// Level bar fill state derived from the bound signal.
@immutable
class LevelBarReading {
  const LevelBarReading({
    required this.fraction,
    required this.value,
    required this.zone,
    required this.isError,
  });

  /// Fill fraction clamped to `[0, 1]`. Zero when there is no value.
  final double fraction;

  /// Raw numeric value, or null when unbound / unknown.
  final double? value;

  /// Color zone for the current fill level.
  final LevelBarZone zone;

  /// True when the signal is X / Z so the renderer should show an error
  /// pattern instead of a bar fill.
  final bool isError;
}

/// Color zone reported by [computeLevelBarReading].
enum LevelBarZone { normal, warning, critical }

/// Pure logic: compute fraction + zone for a level bar.
LevelBarReading computeLevelBarReading(
  StageSignalSnapshot snapshot, {
  required double minValue,
  required double maxValue,
  double? warningThreshold,
  double? criticalThreshold,
}) {
  if (!snapshot.hasValue) {
    return const LevelBarReading(
      fraction: 0,
      value: null,
      zone: LevelBarZone.normal,
      isError: false,
    );
  }
  if (snapshot.hasX || snapshot.hasZ) {
    return const LevelBarReading(
      fraction: 0,
      value: null,
      zone: LevelBarZone.normal,
      isError: true,
    );
  }
  final v = snapshot.realValue;
  if (v == null) {
    return const LevelBarReading(
      fraction: 0,
      value: null,
      zone: LevelBarZone.normal,
      isError: false,
    );
  }
  final span = maxValue - minValue;
  final raw = span == 0 ? 0.0 : (v - minValue) / span;
  final fraction = raw.isNaN ? 0.0 : raw.clamp(0.0, 1.0);

  var zone = LevelBarZone.normal;
  if (criticalThreshold != null && v >= criticalThreshold) {
    zone = LevelBarZone.critical;
  } else if (warningThreshold != null && v >= warningThreshold) {
    zone = LevelBarZone.warning;
  }

  return LevelBarReading(
    fraction: fraction,
    value: v,
    zone: zone,
    isError: false,
  );
}

/// Definition for the level-bar / gauge primitive.
class LevelBarStageWidget extends StageWidget {
  const LevelBarStageWidget();

  static const String widgetId = 'level_bar';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Level Bar';

  @override
  String? get displayNameKey => 'stageLevelBarDisplayName';

  @override
  String get description =>
      'Bar that fills proportionally to a signal value within a configurable range.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'value',
      description: 'Integer or real signal driving the bar fill',
    ),
  ];

  @override
  (double, double) get defaultSize => (140, 120);

  @override
  (double, double) get minSize => (80, 80);
}

/// Renders a [LevelBarStageWidget] instance.
class LevelBarStageRenderer extends ConsumerWidget {
  const LevelBarStageRenderer({
    required this.instance,
    this.minValue = 0,
    this.maxValue = 255,
    this.warningThreshold,
    this.criticalThreshold,
    this.orientation = Axis.vertical,
    super.key,
  });

  final StageInstance instance;
  final double minValue;
  final double maxValue;
  final double? warningThreshold;
  final double? criticalThreshold;
  final Axis orientation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final binding = instance.signalBindings['value'];
    final snapshot = ref.watch(stageBoundSignalProvider(binding));
    final reading = computeLevelBarReading(
      snapshot,
      minValue: minValue,
      maxValue: maxValue,
      warningThreshold: warningThreshold,
      criticalThreshold: criticalThreshold,
    );

    final label = reading.isError
        ? 'X'
        : reading.value == null
        ? '–'
        : reading.value!.toStringAsFixed(
            reading.value! % 1 == 0 ? 0 : 2,
          );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        label: l10n.stageLevelBarSemanticLabel(
          label,
          (reading.fraction * 100).round().toString(),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reading.fraction, end: reading.fraction),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, fraction, _) => CustomPaint(
            painter: _LevelBarPainter(
              fraction: fraction,
              zone: reading.zone,
              isError: reading.isError,
              label: label,
              orientation: orientation,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _LevelBarPainter extends CustomPainter {
  _LevelBarPainter({
    required this.fraction,
    required this.zone,
    required this.isError,
    required this.label,
    required this.orientation,
  });

  final double fraction;
  final LevelBarZone zone;
  final bool isError;
  final String label;
  final Axis orientation;

  @override
  void paint(Canvas canvas, Size size) {
    const trackColor = Color(0xFF1B1B1B);
    final fillColor = switch (zone) {
      LevelBarZone.normal => const Color(0xFF26A69A),
      LevelBarZone.warning => const Color(0xFFFFB300),
      LevelBarZone.critical => const Color(0xFFE53935),
    };

    final radius = Radius.circular(orientation == Axis.vertical ? 6 : 4);
    final track = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = trackColor,
    );

    if (!isError) {
      final fill = orientation == Axis.vertical
          ? Rect.fromLTWH(
              0,
              size.height * (1 - fraction),
              size.width,
              size.height * fraction,
            )
          : Rect.fromLTWH(0, 0, size.width * fraction, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, radius),
        Paint()..color = fillColor,
      );
    } else {
      // X/Z error: red diagonal hatching across the full track.
      const errColor = Color(0xFFE53935);
      final paint = Paint()
        ..color = errColor
        ..strokeWidth = 1.4;
      const step = 6.0;
      for (var d = -size.width; d < size.width * 2; d += step) {
        canvas.drawLine(
          Offset(d, 0),
          Offset(d + size.height, size.height),
          paint,
        );
      }
    }

    // Track outline.
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Center value label.
    final span = TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
      ),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _LevelBarPainter old) =>
      old.fraction != fraction ||
      old.zone != zone ||
      old.isError != isError ||
      old.label != label ||
      old.orientation != orientation;
}
