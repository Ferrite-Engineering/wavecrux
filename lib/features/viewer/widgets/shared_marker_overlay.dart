// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Colour for shared collaboration markers — distinct from the collaborator
/// cursor palette and the local cursor/measurement colours so a shared marker
/// reads as "the group placed this" rather than "someone's cursor is here".
const _kSharedMarkerColor = Color(0xFF26A69A); // teal-400

/// Repaint-isolated overlay that draws the session's **shared markers** above
/// the waveform canvas.
///
/// Shared markers are session-wide annotations (a named tick everyone in the
/// room agrees on), carried in [CollabSessionState.sharedMarkers]. They are
/// rendered as a dashed teal vertical line with a name flag pinned to the
/// bottom of the canvas, so they sit clear of the collaborator-cursor name
/// chips at the top.
///
/// Structured like [CollaboratorCursorOverlay] — [RepaintBoundary] +
/// [IgnorePointer] + [CustomPaint] — so marker churn invalidates only this
/// layer. Renders nothing when there is no active session (the open-core
/// no-op service produces none) or when the session has no shared markers, so
/// the layer is inert in Open Core and idle Pro builds.
class SharedMarkerOverlay extends ConsumerWidget {
  const SharedMarkerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(collaborationSessionStateProvider).value;
    if (sessionState == null || sessionState.sharedMarkers.isEmpty) {
      return const SizedBox.shrink();
    }

    final timeMapper = ref.watch(timeMapperProvider);
    final labelStyle =
        Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 10);

    // Only the markers currently within the visible window need painting.
    final visible = <MapEntry<String, int>>[
      for (final e in sessionState.sharedMarkers.entries)
        if (e.value >= timeMapper.visibleStartTime &&
            e.value <= timeMapper.visibleEndTime)
          e,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _SharedMarkerPainter(
            markers: visible,
            timeMapper: timeMapper,
            labelStyle: labelStyle,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SharedMarkerPainter extends CustomPainter {
  _SharedMarkerPainter({
    required this.markers,
    required this.timeMapper,
    required this.labelStyle,
  });

  final List<MapEntry<String, int>> markers;
  final TimeMapper timeMapper;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = _kSharedMarkerColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;

    for (final marker in markers) {
      final time = marker.value;
      if (time < timeMapper.visibleStartTime ||
          time > timeMapper.visibleEndTime) {
        continue;
      }
      final x = timeMapper.timeToPixel(time);

      // Dashed vertical line (distinguishes shared markers from solid cursors).
      const dash = 5.0;
      const gap = 4.0;
      for (var y = 0.0; y < size.height; y += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, (y + dash).clamp(0, size.height)),
          linePaint,
        );
      }

      // Name flag pinned to the bottom so it clears the cursor chips up top.
      final tp = TextPainter(
        text: TextSpan(
          text: ' ⚑ ${marker.key} ',
          style: labelStyle.copyWith(color: Colors.white, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const pad = 2.0;
      final chipRect = Rect.fromLTWH(
        x + 2,
        size.height - tp.height - pad * 2 - 2,
        tp.width,
        tp.height + pad * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3)),
        Paint()..color = _kSharedMarkerColor,
      );
      tp.paint(canvas, Offset(chipRect.left, chipRect.top + pad));
    }
  }

  @override
  bool shouldRepaint(covariant _SharedMarkerPainter old) =>
      old.markers != markers ||
      old.timeMapper != timeMapper ||
      old.labelStyle != labelStyle;
}
