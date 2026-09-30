// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/fsm_layout.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';

/// CustomPainter that renders an FSM bubble diagram from an [FsmModel] and
/// its computed [FsmLayout].
///
/// State nodes are drawn as filled circles with a label below. The currently
/// active state (from the cursor) glows with a thicker outline and brighter
/// fill. Transitions are drawn as straight directed arrows; self-loops are
/// drawn as small arcs above the originating state. Each transition edge is
/// labelled with its observation count, optionally followed by the
/// percentage of the total transition count.
class FsmBubblePainter extends CustomPainter {
  FsmBubblePainter({
    required this.model,
    required this.layout,
    required this.colorScheme,
    this.activeStateId,
    this.activeTransition,
    this.showPercentages = true,
  });

  final FsmModel model;
  final FsmLayout layout;
  final ColorScheme colorScheme;

  /// Id of the state currently entered by the cursor, or null.
  final String? activeStateId;

  /// (fromId, toId) of the most recent transition at the cursor, or null.
  final ({String fromId, String toId})? activeTransition;

  /// When true, edge labels include the count and percentage; otherwise
  /// only the count.
  final bool showPercentages;

  // Visual constants — tuned to balance density vs. readability across
  // the device classes WaveCrux supports.
  static const double _stateRadiusPx = 28;
  static const double _arrowHeadLengthPx = 8;
  static const double _arrowHeadAngle = math.pi / 7;
  static const double _selfLoopRadiusPx = 18;
  static const double _stateLabelFontSize = 11;
  static const double _edgeLabelFontSize = 10;

  @override
  void paint(Canvas canvas, Size size) {
    if (model.states.isEmpty || layout.isEmpty) {
      _paintEmpty(canvas, size);
      return;
    }

    // 1. Edges first so node circles overlap them at endpoints.
    for (final transition in model.transitions) {
      _paintTransition(canvas, size, transition);
    }

    // 2. State nodes on top.
    for (final state in model.states) {
      _paintState(canvas, size, state);
    }
  }

  // ── empty state (no states) ─────────────────────────────────────────────────

  void _paintEmpty(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = colorScheme.surface
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);
  }

  // ── state node ──────────────────────────────────────────────────────────────

  void _paintState(Canvas canvas, Size size, FsmState state) {
    final pos = layout[state.id];
    if (pos == null) return;
    final center = Offset(pos.x * size.width, pos.y * size.height);

    final isActive = state.id == activeStateId;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isActive
          ? colorScheme.primary.withValues(alpha: 0.85)
          : colorScheme.surfaceContainerHighest;
    canvas.drawCircle(center, _stateRadiusPx, fillPaint);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isActive ? 3 : 1.5
      ..color = isActive ? colorScheme.primary : colorScheme.outline;
    canvas.drawCircle(center, _stateRadiusPx, outlinePaint);

    // Label inside the circle.
    final textColor = isActive ? colorScheme.onPrimary : colorScheme.onSurface;
    final tp = TextPainter(
      text: TextSpan(
        text: state.label,
        style: TextStyle(
          color: textColor,
          fontSize: _stateLabelFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: _stateRadiusPx * 1.8);
    tp.paint(
      canvas,
      Offset(
        center.dx - tp.width / 2,
        center.dy - tp.height / 2,
      ),
    );

    // Entry-count badge below the circle.
    final countTp = TextPainter(
      text: TextSpan(
        text: '×${state.entryCount}',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: _edgeLabelFontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    countTp.paint(
      canvas,
      Offset(
        center.dx - countTp.width / 2,
        center.dy + _stateRadiusPx + 2,
      ),
    );
  }

  // ── transition edge ─────────────────────────────────────────────────────────

  void _paintTransition(Canvas canvas, Size size, FsmTransition transition) {
    final from = layout[transition.fromId];
    final to = layout[transition.toId];
    if (from == null || to == null) return;

    final isActive =
        activeTransition != null &&
        activeTransition!.fromId == transition.fromId &&
        activeTransition!.toId == transition.toId;

    final color = isActive ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final strokeWidth = isActive ? 2.5 : 1.2;

    final fromCenter = Offset(from.x * size.width, from.y * size.height);
    final toCenter = Offset(to.x * size.width, to.y * size.height);

    if (transition.isSelfLoop) {
      _paintSelfLoop(canvas, fromCenter, transition, color, strokeWidth);
    } else {
      _paintEdge(
        canvas,
        fromCenter,
        toCenter,
        transition,
        color,
        strokeWidth,
      );
    }
  }

  void _paintEdge(
    Canvas canvas,
    Offset fromCenter,
    Offset toCenter,
    FsmTransition transition,
    Color color,
    double strokeWidth,
  ) {
    // Trim the line to start/end at the circle perimeters (not the centres).
    final delta = toCenter - fromCenter;
    final distance = delta.distance;
    if (distance == 0) return;
    final unit = delta / distance;
    final start = fromCenter + unit * _stateRadiusPx;
    final end = toCenter - unit * _stateRadiusPx;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);

    // Arrowhead at the destination end.
    _paintArrowhead(canvas, end, unit, paint);

    // Edge label at the midpoint, offset perpendicular to the line so it
    // doesn't sit on top of the line.
    final mid = (start + end) / 2;
    final perp = Offset(-unit.dy, unit.dx) * 8;
    _paintEdgeLabel(canvas, mid + perp, transition, color);
  }

  void _paintSelfLoop(
    Canvas canvas,
    Offset center,
    FsmTransition transition,
    Color color,
    double strokeWidth,
  ) {
    // Draw a small circle above the state, tangent to the state circle.
    final loopCenter = center.translate(0, -_stateRadiusPx - _selfLoopRadiusPx);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(loopCenter, _selfLoopRadiusPx, paint);

    // Arrowhead pointing down-right back into the state.
    final arrowTip = Offset(
      center.dx + math.cos(-math.pi / 4) * _stateRadiusPx,
      center.dy + math.sin(-math.pi / 4) * _stateRadiusPx,
    );
    final unit = Offset(math.cos(math.pi / 4), math.sin(math.pi / 4));
    _paintArrowhead(canvas, arrowTip, unit, paint);

    // Label above the loop.
    _paintEdgeLabel(
      canvas,
      loopCenter.translate(0, -_selfLoopRadiusPx - 6),
      transition,
      color,
    );
  }

  void _paintArrowhead(Canvas canvas, Offset tip, Offset unit, Paint paint) {
    final baseAngle = math.atan2(unit.dy, unit.dx);
    final left =
        tip -
        Offset(
          math.cos(baseAngle - _arrowHeadAngle) * _arrowHeadLengthPx,
          math.sin(baseAngle - _arrowHeadAngle) * _arrowHeadLengthPx,
        );
    final right =
        tip -
        Offset(
          math.cos(baseAngle + _arrowHeadAngle) * _arrowHeadLengthPx,
          math.sin(baseAngle + _arrowHeadAngle) * _arrowHeadLengthPx,
        );
    canvas
      ..drawLine(tip, left, paint)
      ..drawLine(tip, right, paint);
  }

  void _paintEdgeLabel(
    Canvas canvas,
    Offset position,
    FsmTransition transition,
    Color color,
  ) {
    final pct = model.totalTransitionCount > 0
        ? (transition.count / model.totalTransitionCount * 100)
        : 0.0;
    final label = showPercentages && model.totalTransitionCount > 0
        ? '${transition.count} (${pct.toStringAsFixed(0)}%)'
        : '${transition.count}';

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: _edgeLabelFontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Background pill so the label remains legible over edges.
    const padding = 3.0;
    final rect = Rect.fromLTWH(
      position.dx - tp.width / 2 - padding,
      position.dy - tp.height / 2 - padding / 2,
      tp.width + 2 * padding,
      tp.height + padding,
    );
    final bgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = colorScheme.surface.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      bgPaint,
    );

    tp.paint(
      canvas,
      Offset(position.dx - tp.width / 2, position.dy - tp.height / 2),
    );
  }

  /// Hit-test helper: returns the [FsmState.id] under [point], or null.
  ///
  /// Used by the widget to dispatch tap-to-jump interactions.
  String? hitTestState(Offset point, Size size) {
    for (final state in model.states) {
      final pos = layout[state.id];
      if (pos == null) continue;
      final center = Offset(pos.x * size.width, pos.y * size.height);
      if ((center - point).distance <= _stateRadiusPx) {
        return state.id;
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant FsmBubblePainter oldDelegate) =>
      model != oldDelegate.model ||
      layout != oldDelegate.layout ||
      colorScheme != oldDelegate.colorScheme ||
      activeStateId != oldDelegate.activeStateId ||
      activeTransition != oldDelegate.activeTransition ||
      showPercentages != oldDelegate.showPercentages;
}
