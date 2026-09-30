// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/theme/collaborator_palette.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Repaint-isolated overlay that draws remote collaborator cursors above the
/// waveform canvas.
///
/// Structured identically to [CursorOverlay] — [RepaintBoundary] +
/// [IgnorePointer] + [CustomPaint] — so cursor position updates for any
/// participant invalidate only this layer, not the signal-lane GPU cache.
///
/// Renders nothing when [collaborationSessionStateProvider] is in the loading
/// or error state (noop service, no active session, or connection not yet
/// established). Renders nothing for the local participant (identified by
/// [CollabSessionState.myParticipantId]) and for participants whose
/// [ParticipantInfo.primaryCursorTime] is `null`.
class CollaboratorCursorOverlay extends ConsumerWidget {
  const CollaboratorCursorOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(collaborationSessionStateProvider).value;
    if (sessionState == null) return const SizedBox.shrink();

    final timeMapper = ref.watch(timeMapperProvider);
    final labelStyle =
        Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 10);

    final presenterId = sessionState.presenterId;
    final remote = sessionState.participants
        .where(
          (p) =>
              p.id != sessionState.myParticipantId &&
              p.primaryCursorTime != null &&
              p.primaryCursorTime! >= timeMapper.visibleStartTime &&
              p.primaryCursorTime! <= timeMapper.visibleEndTime,
        )
        .toList(growable: false);

    if (remote.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: CollaboratorCursorPainter(
            participants: remote,
            presenterId: presenterId,
            timeMapper: timeMapper,
            labelStyle: labelStyle,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Paints the remote collaborator cursors. Exposed (not private) so the
/// presenter-distinction branch can be unit-tested directly.
@visibleForTesting
class CollaboratorCursorPainter extends CustomPainter {
  CollaboratorCursorPainter({
    required this.participants,
    required this.presenterId,
    required this.timeMapper,
    required this.labelStyle,
  });

  final List<ParticipantInfo> participants;

  /// The participant currently driving the shared viewport. Their
  /// cursor is rendered with a halo + a ▶ badge so the room can tell at a glance
  /// who is presenting versus who is merely present.
  final String presenterId;
  final TimeMapper timeMapper;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in participants) {
      final cursorTime = p.primaryCursorTime;
      if (cursorTime == null) continue;
      if (cursorTime < timeMapper.visibleStartTime ||
          cursorTime > timeMapper.visibleEndTime) {
        continue;
      }

      final x = timeMapper.timeToPixel(cursorTime);
      // Defensive guard: a degenerate time-mapper (e.g. a directly-constructed
      // mapper with ticksPerPixel == 0) would make timeToPixel divide by zero
      // and return NaN/Infinity. Drawing at a non-finite coordinate hard-crashes
      // the Windows renderer (ANGLE/Direct3D) with no Dart exception, where macOS
      // Metal tolerates it — a silent, platform-specific process exit. Skip such
      // cursors so a malformed remote position can never take the process down.
      if (!x.isFinite) continue;
      final color = collaboratorColor(p.colorIndex);
      final isPresenter = p.id == presenterId;

      // Presenter halo: a wide, low-alpha line behind the cursor so the
      // presenter's position reads as "the one we're all following".
      if (isPresenter) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = color.withValues(alpha: 0.25)
            ..strokeWidth = 6,
        );
      }

      // Draw cursor line (the presenter's is a touch bolder).
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = color.withValues(alpha: isPresenter ? 1 : 0.8)
          ..strokeWidth = isPresenter ? 2.5 : 1.5,
      );

      // Draw name label chip above the cursor line — prefixed with a ▶ badge
      // glyph for the presenter (a symbol, not translatable text).
      final tp = TextPainter(
        text: TextSpan(
          text: isPresenter ? ' ▶ ${p.displayName} ' : ' ${p.displayName} ',
          style: labelStyle.copyWith(color: Colors.white, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const chipPadding = 2.0;
      final chipRect = Rect.fromLTWH(
        x + 2,
        chipPadding,
        tp.width,
        tp.height + chipPadding * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3)),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(chipRect.left, chipRect.top + chipPadding));
    }
  }

  @override
  bool shouldRepaint(covariant CollaboratorCursorPainter old) {
    return old.participants != participants ||
        old.presenterId != presenterId ||
        old.timeMapper != timeMapper ||
        old.labelStyle != labelStyle;
  }
}
