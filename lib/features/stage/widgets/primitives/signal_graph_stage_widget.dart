// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// One sample point on the signal graph: simulation [time] (ticks) and the
/// numeric value at that time. `null` value indicates an X / Z gap.
@immutable
class SignalGraphSample {
  const SignalGraphSample({required this.time, required this.value});

  final int time;
  final double? value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalGraphSample && time == other.time && value == other.value;

  @override
  int get hashCode => Object.hash(time, value);

  @override
  String toString() => 'SignalGraphSample(t: $time, v: $value)';
}

/// Pure logic: computes nice min/max for the y-axis given a list of samples.
/// Falls back to a reasonable range when all samples are null or the values
/// collapse to a single point.
({double min, double max}) computeSignalGraphYRange(
  Iterable<SignalGraphSample> samples,
) {
  double? lo;
  double? hi;
  for (final s in samples) {
    final v = s.value;
    if (v == null) continue;
    if (lo == null || v < lo) lo = v;
    if (hi == null || v > hi) hi = v;
  }
  if (lo == null || hi == null) return (min: 0, max: 1);
  if (lo == hi) {
    final pad = lo.abs() < 1e-9 ? 1.0 : lo.abs() * 0.1;
    return (min: lo - pad, max: hi + pad);
  }
  // Add a 5 % top/bottom margin so the trace never touches the frame.
  final span = hi - lo;
  return (min: lo - span * 0.05, max: hi + span * 0.05);
}

/// Definition for the signal-graph primitive.
class SignalGraphStageWidget extends StageWidget {
  const SignalGraphStageWidget();

  static const String widgetId = 'signal_graph';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Signal Graph';

  @override
  String? get displayNameKey => 'stageSignalGraphDisplayName';

  @override
  String get description =>
      'Mini scrolling plot of an analog or integer signal around the cursor.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'value',
      description: 'Integer or real signal to plot',
    ),
  ];

  @override
  (double, double) get defaultSize => (260, 140);

  @override
  (double, double) get minSize => (160, 80);
}

/// Renders a [SignalGraphStageWidget] instance.
class SignalGraphStageRenderer extends ConsumerWidget {
  const SignalGraphStageRenderer({
    required this.instance,
    this.windowTicks = 1000,
    super.key,
  });

  final StageInstance instance;
  final int windowTicks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final binding = instance.signalBindings['value'];
    final signalRef = binding?.signalRef;

    // Force the snapshot dependency so the renderer rebuilds on cursor /
    // file change. We don't actually use the cursor-time value directly —
    // the painter pulls a window of changes from the source.
    final snapshot = ref.watch(stageBoundSignalProvider(binding));
    final cursorState = ref.watch(cursorStateProvider);
    final source = ref.watch(waveformSourceProvider).value;
    final variablesMap = ref.watch(signalVariablesMapProvider);

    if (signalRef == null || signalRef.isEmpty) {
      return _GraphPlaceholder(message: l10n.stageSignalGraphUnbound);
    }
    if (source == null) {
      return _GraphPlaceholder(message: l10n.stageSignalGraphNoFile);
    }
    if (snapshot.kind == StageSignalSnapshotKind.loading) {
      return _GraphPlaceholder(message: l10n.stageSignalGraphLoading);
    }

    final variable = variablesMap[signalRef];
    final isReal = variable?.isReal ?? false;
    final bitWidth = variable?.bitWidth ?? 1;

    final cursor = cursorState.primaryCursorTime ?? source.startTime;
    final start = (cursor - windowTicks ~/ 2).clamp(
      source.startTime,
      source.endTime,
    );
    final end = (cursor + windowTicks ~/ 2).clamp(
      source.startTime,
      source.endTime,
    );

    final samples = <SignalGraphSample>[];
    final initial = source.valueAt(signalRef, start);
    if (initial != null) {
      samples.add(
        SignalGraphSample(
          time: start,
          value: _parseValue(initial, bitWidth: bitWidth, isReal: isReal),
        ),
      );
    }
    final changes = source.changesInRange(signalRef, start, end + 1);
    for (final c in changes) {
      samples.add(
        SignalGraphSample(
          time: c.time,
          value: _parseValue(c.value, bitWidth: bitWidth, isReal: isReal),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(6),
      child: CustomPaint(
        painter: _SignalGraphPainter(
          samples: samples,
          startTime: start,
          endTime: end,
          cursorTime: cursor,
          timescale: source.timescale,
        ),
        child: SizedBox.expand(
          child: Semantics(
            label: l10n.stageSignalGraphSemanticLabel(samples.length),
          ),
        ),
      ),
    );
  }

  /// Parses a raw VCD value into a `double`. Returns null on X/Z so the
  /// painter draws a gap rather than dropping to zero.
  static double? _parseValue(
    String raw, {
    required int bitWidth,
    required bool isReal,
  }) {
    if (raw.isEmpty) return null;
    var s = raw.toLowerCase();
    if (s.startsWith('b')) s = s.substring(1);
    if (s.startsWith('r')) s = s.substring(1);

    if (isReal) {
      return double.tryParse(s);
    }
    if (s.contains('x') || s.contains('z')) return null;
    if (s.isEmpty) return null;
    if (bitWidth > 0 && s.length < bitWidth) {
      s = s.padLeft(bitWidth, '0');
    }
    return BigInt.tryParse(s, radix: 2)?.toDouble();
  }
}

class _GraphPlaceholder extends StatelessWidget {
  const _GraphPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SignalGraphPainter extends CustomPainter {
  _SignalGraphPainter({
    required this.samples,
    required this.startTime,
    required this.endTime,
    required this.cursorTime,
    required this.timescale,
  });

  final List<SignalGraphSample> samples;
  final int startTime;
  final int endTime;
  final int cursorTime;
  final Timescale? timescale;

  @override
  void paint(Canvas canvas, Size size) {
    // Background.
    final bgPaint = Paint()..color = const Color(0xFF101820);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    // Gridlines.
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.isEmpty || endTime <= startTime) {
      _drawCursor(canvas, size);
      return;
    }

    final yRange = computeSignalGraphYRange(samples);
    final spanT = (endTime - startTime).toDouble();
    final spanY = yRange.max - yRange.min;
    double xFor(int t) => (t - startTime).toDouble() / spanT * size.width;
    double yFor(double v) =>
        size.height - (v - yRange.min) / spanY * size.height;

    final path = Path();
    final paint = Paint()
      ..color = const Color(0xFF80DEEA)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Step-hold rendering: horizontal segment until next sample, then jump.
    var lastV = samples.first.value;
    var lastX = xFor(samples.first.time);
    if (lastV != null) {
      path.moveTo(lastX, yFor(lastV));
    }

    for (var i = 1; i < samples.length; i++) {
      final s = samples[i];
      final newX = xFor(s.time);
      if (lastV != null) {
        path.lineTo(newX, yFor(lastV)); // horizontal
        if (s.value != null) {
          path.lineTo(newX, yFor(s.value!)); // vertical jump
        }
      } else if (s.value != null) {
        path.moveTo(newX, yFor(s.value!));
      }
      lastV = s.value;
      lastX = newX;
    }
    // Hold the last value until the right edge.
    if (lastV != null) {
      path.lineTo(size.width, yFor(lastV));
    }
    canvas.drawPath(path, paint);

    _drawCursor(canvas, size);
  }

  void _drawCursor(Canvas canvas, Size size) {
    if (cursorTime < startTime || cursorTime > endTime) return;
    final spanT = (endTime - startTime).toDouble();
    if (spanT <= 0) return;
    final x = (cursorTime - startTime).toDouble() / spanT * size.width;
    final cursorPaint = Paint()
      ..color = const Color(0xFFFFB300)
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), cursorPaint);
  }

  @override
  bool shouldRepaint(covariant _SignalGraphPainter old) =>
      old.startTime != startTime ||
      old.endTime != endTime ||
      old.cursorTime != cursorTime ||
      old.samples.length != samples.length ||
      !_sampleListsEqual(old.samples, samples);

  static bool _sampleListsEqual(
    List<SignalGraphSample> a,
    List<SignalGraphSample> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
