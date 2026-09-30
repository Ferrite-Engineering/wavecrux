// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/painting.dart';

/// A sealed class representing a single logical draw operation captured
/// during a [WaveformCanvasRenderObject.paint] call.
///
/// The render object populates [WaveformCanvasRenderObject.lastPaintCommands]
/// with a snapshot of these commands when [WaveformCanvasView.recordPaintCommands]
/// is `true`. Widget tests use the snapshot to assert on rendered content
/// (error transaction coloring, XOR lane presence, selection overlays) without
/// comparing pixel images.
///
/// Commands are captured at the render-object level, not at the raw
/// [Canvas] call level. Each variant corresponds to a semantic draw
/// operation: a transaction block, a signal path, a lane divider, etc.
sealed class CanvasDrawCommand {
  const CanvasDrawCommand();
}

/// A filled or stroked rectangle (covers both [Canvas.drawRect] and
/// [Canvas.drawRRect] operations, using the outer bounds of the rounded rect).
final class DrawRect extends CanvasDrawCommand {
  const DrawRect(this.rect, this.paint);

  final Rect rect;
  final Paint paint;
}

/// A path drawn on the canvas (signal waveforms, XOR diff traces).
final class DrawPath extends CanvasDrawCommand {
  const DrawPath(this.path, this.paint);

  final Path path;
  final Paint paint;
}

/// A line segment (lane dividers, cursor lines, marker lines).
final class DrawLine extends CanvasDrawCommand {
  const DrawLine(this.p1, this.p2, this.paint);

  final Offset p1;
  final Offset p2;
  final Paint paint;
}
