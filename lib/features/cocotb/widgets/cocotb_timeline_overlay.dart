// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_visible_markers_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_severity_style.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Height of the cocotb marker strip in logical pixels.
///
/// Sits directly below the time ruler and above the waveform canvas.
const double cocotbTimelineOverlayHeight = 8;

/// Thin colored strip showing one tick per visible cocotb log entry.
///
/// Renders only when a log is loaded. Each entry's [simTimeTicks] maps to a
/// horizontal pixel via the active [TimeMapper]; the colour matches the
/// entry's severity. Adjacent ticks within a single pixel column are merged
/// into a band so dense logs stay readable.
///
/// The overlay is non-interactive — taps still pass through to whatever
/// sits below it (currently the waveform canvas).
class CocotbTimelineOverlay extends ConsumerWidget {
  const CocotbTimelineOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(cocotbLogProvider);
    if (log == null) return const SizedBox.shrink();

    final markers = ref.watch(cocotbVisibleMarkersProvider);
    final timeMapper = ref.watch(timeMapperProvider);

    return IgnorePointer(
      child: SizedBox(
        height: cocotbTimelineOverlayHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return RepaintBoundary(
              child: CustomPaint(
                size: Size(constraints.maxWidth, cocotbTimelineOverlayHeight),
                painter: _CocotbOverlayPainter(
                  markers: markers,
                  timeMapper: timeMapper,
                  background: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CocotbOverlayPainter extends CustomPainter {
  const _CocotbOverlayPainter({
    required this.markers,
    required this.timeMapper,
    required this.background,
  });

  final List<CocotbLogEntry> markers;
  final TimeMapper timeMapper;
  final Color background;

  @override
  bool shouldRepaint(_CocotbOverlayPainter old) =>
      !identical(old.markers, markers) ||
      old.timeMapper != timeMapper ||
      old.background != background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = background,
    );
    if (markers.isEmpty) return;

    // Density management: bucket markers by integer pixel column so we
    // never draw more than one tick per column. The most-severe severity
    // in the bucket wins so error/critical events stay visible in dense
    // logs.
    final buckets = <int, CocotbLogSeverity>{};
    for (final entry in markers) {
      final ticks = entry.simTimeTicks;
      if (ticks == null) continue;
      final px = timeMapper.timeToPixel(ticks).round();
      if (px < 0 || px > size.width.toInt() + 1) continue;
      final existing = buckets[px];
      if (existing == null || entry.severity.index > existing.index) {
        buckets[px] = entry.severity;
      }
    }

    for (final entry in buckets.entries) {
      final px = entry.key.toDouble();
      final severity = entry.value;
      final color = CocotbSeverityStyle.of(severity).color;
      canvas.drawLine(
        Offset(px, 0),
        Offset(px, size.height),
        Paint()
          ..color = color
          ..strokeWidth = 1.5,
      );
    }
  }
}
