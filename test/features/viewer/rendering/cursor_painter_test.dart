// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/features/viewer/rendering/cursor_painter.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

const _mapper = TimeMapper(
  startTime: 0,
  endTime: 1000,
  viewportWidth: 1000,
  ticksPerPixel: 1,
  panOffsetTicks: 0,
);

const _bounds = Rect.fromLTWH(0, 0, 1000, 300);
const _primaryColor = Color(0xFFFFFF00);
const _secondaryColor = Color(0xFFFF8800);
const _labelStyle = TextStyle(fontSize: 11);

// ── recording canvas ──────────────────────────────────────────────────────────

/// A [Canvas] that records the draw calls made against it instead of
/// rasterizing them.
///
/// These tests previously called the painter against a throwaway
/// `Canvas(PictureRecorder())` and asserted nothing at all — they proved only
/// that painting did not throw, so any regression that drew the wrong thing
/// (or nothing) still passed. `Picture` exposes no op log to Dart, so the
/// recorder cannot answer "what got drawn"; this stand-in can.
///
/// Implemented via [noSuchMethod] so it survives additions to the [Canvas]
/// interface: unrecorded methods are silently accepted rather than breaking
/// the build.
class _RecordingCanvas implements Canvas {
  final List<_Op> ops = <_Op>[];

  List<_Op> opsNamed(String name) =>
      ops.where((o) => o.name == name).toList(growable: false);

  List<_Op> get lines => opsNamed('drawLine');
  List<_Op> get rRects => opsNamed('drawRRect');
  List<_Op> get paragraphs => opsNamed('drawParagraph');

  /// Draw calls that put ink on the canvas, in invocation order. Excludes
  /// bookkeeping ops (save/restore/transform/clip) so ordering assertions
  /// read against the marks themselves.
  List<_Op> get drawOps =>
      ops.where((o) => o.name.startsWith('draw')).toList(growable: false);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    ops.add(_Op('drawLine', <Object?>[p1, p2, paint]));
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    ops.add(_Op('drawRRect', <Object?>[rrect, paint]));
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    ops.add(_Op('drawParagraph', <Object?>[paragraph, offset]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    // Symbol("drawFoo") → drawFoo
    final start = name.indexOf('"');
    final end = name.lastIndexOf('"');
    final member = (start >= 0 && end > start)
        ? name.substring(start + 1, end)
        : name;
    ops.add(_Op(member, invocation.positionalArguments));
    return null;
  }
}

class _Op {
  _Op(this.name, this.args);
  final String name;
  final List<Object?> args;

  Offset get from => args[0]! as Offset;
  Offset get to => args[1]! as Offset;
  Paint get paint => args.last! as Paint;

  /// `Paint.color` round-trips through floating-point channels, so it never
  /// compares equal to an `int`-constructed [Color] literal. Compare packed
  /// ARGB instead.
  int get colorArgb => paint.color.toARGB32();
  RRect get rrect => args[0]! as RRect;

  @override
  String toString() => '$name(${args.join(', ')})';
}

_RecordingCanvas _paint(
  CursorState state, {
  String? deltaLabel,
  TimeMapper mapper = _mapper,
  Rect bounds = _bounds,
}) {
  final canvas = _RecordingCanvas();
  CursorPainter.paint(
    canvas: canvas,
    bounds: bounds,
    cursorState: state,
    timeMapper: mapper,
    primaryColor: _primaryColor,
    secondaryColor: _secondaryColor,
    deltaLabel: deltaLabel,
    labelStyle: _labelStyle,
  );
  return canvas;
}

/// The single full-height stroke the primary cursor draws. The secondary
/// cursor is dashed, so it never produces a full-height segment.
Iterable<_Op> _fullHeightLines(_RecordingCanvas c) => c.lines.where(
  (o) => o.from.dy == _bounds.top && o.to.dy == _bounds.bottom,
);

void main() {
  group('CursorPainter', () {
    test('no-op when no cursors placed', () {
      final c = _paint(const CursorState());
      expect(c.drawOps, isEmpty);
    });

    test('primary cursor paints one full-height line at the cursor x', () {
      final c = _paint(const CursorState(primaryCursorTime: 500));
      expect(c.lines, hasLength(1));
      final line = c.lines.single;
      expect(line.from, const Offset(500, 0));
      expect(line.to, const Offset(500, 300));
      expect(line.colorArgb, _primaryColor.toARGB32());
      expect(line.paint.strokeWidth, 1.5);
    });

    test('primary cursor at left edge is painted at x = 0', () {
      final c = _paint(const CursorState(primaryCursorTime: 0));
      expect(c.lines, hasLength(1));
      expect(c.lines.single.from.dx, 0);
    });

    test('primary cursor at right edge is painted at the right bound', () {
      final c = _paint(const CursorState(primaryCursorTime: 1000));
      expect(c.lines, hasLength(1));
      expect(c.lines.single.from.dx, _bounds.right);
    });

    test('primary cursor out of bounds draws nothing', () {
      // panOffset=500 shifts the visible window to [500..1500], so time 100
      // maps to x = -400 — left of `bounds` and therefore culled.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 1000,
        ticksPerPixel: 1,
        panOffsetTicks: 500,
      );
      final c = _paint(
        const CursorState(primaryCursorTime: 100),
        mapper: mapper,
      );
      expect(c.drawOps, isEmpty);
    });

    test('secondary cursor paints a dashed run of same-x segments', () {
      final c = _paint(const CursorState(secondaryCursorTime: 300));
      // 6px dash + 4px gap over a 300px height → 30 segments.
      expect(c.lines, hasLength(30));
      expect(c.lines.every((o) => o.from.dx == 300 && o.to.dx == 300), isTrue);
      expect(
        c.lines.every((o) => o.colorArgb == _secondaryColor.toARGB32()),
        isTrue,
      );
      // Dashes, not one continuous stroke: every segment is one dash long
      // (6px), and the 4px gaps mean they do not tile the full height.
      for (final o in c.lines) {
        expect(o.to.dy - o.from.dy, closeTo(6.0, 1e-6));
      }
      expect(_fullHeightLines(c), isEmpty);
    });

    test('both cursors paint the dashed run plus one solid line', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 400, secondaryCursorTime: 700),
      );
      final solid = _fullHeightLines(c).toList();
      expect(solid, hasLength(1));
      expect(solid.single.from.dx, 400);
      expect(solid.single.colorArgb, _primaryColor.toARGB32());
      final dashed = c.lines.where((o) => o.from.dx == 700);
      expect(dashed, hasLength(30));
    });

    test('secondary is drawn before primary so primary renders on top', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 600, secondaryCursorTime: 200),
        deltaLabel: '400 ns',
      );
      final firstPrimary = c.lines.indexWhere(
        (o) => o.colorArgb == _primaryColor.toARGB32(),
      );
      final lastSecondary = c.lines.lastIndexWhere(
        (o) => o.colorArgb == _secondaryColor.toARGB32(),
      );
      expect(firstPrimary, greaterThan(lastSecondary));
    });

    test('both cursors at the same position paint at the same x', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 500, secondaryCursorTime: 500),
      );
      expect(c.lines.every((o) => o.from.dx == 500), isTrue);
      expect(_fullHeightLines(c), hasLength(1));
    });

    test('delta label paints a chip centered between the cursors', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 200, secondaryCursorTime: 600),
        deltaLabel: '400 ns',
      );
      expect(c.rRects, hasLength(1));
      expect(c.paragraphs, hasLength(1));
      final chip = c.rRects.single.rrect.outerRect;
      // Midpoint of 200..600 is 400; the chip is centered on it.
      expect(chip.center.dx, closeTo(400, 0.5));
      expect(chip.top, _bounds.top + 4.0);
      expect(_bounds.contains(chip.topLeft), isTrue);
      expect(_bounds.contains(chip.bottomRight), isTrue);
    });

    test('delta label is clamped inside bounds when cursors hug the edge', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 0, secondaryCursorTime: 10),
        deltaLabel: '10 ns',
      );
      expect(c.rRects, hasLength(1));
      final chip = c.rRects.single.rrect.outerRect;
      // Unclamped, a chip centered on x=5 would start at a negative x.
      expect(chip.left, greaterThanOrEqualTo(_bounds.left));
      expect(chip.right, lessThanOrEqualTo(_bounds.right));
    });

    test('delta label is suppressed when only the primary cursor is set', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 500),
        deltaLabel: '100 ns',
      );
      expect(c.rRects, isEmpty);
      expect(c.paragraphs, isEmpty);
    });

    test('null deltaLabel suppresses the chip even with both cursors', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 300, secondaryCursorTime: 700),
      );
      expect(c.rRects, isEmpty);
      expect(c.paragraphs, isEmpty);
    });

    test('empty deltaLabel suppresses the chip', () {
      final c = _paint(
        const CursorState(primaryCursorTime: 300, secondaryCursorTime: 700),
        deltaLabel: '',
      );
      expect(c.rRects, isEmpty);
    });

    test('label is skipped rather than throwing when bounds are too narrow', () {
      // The canvas can collapse to a few pixels mid-resize. `num.clamp` throws
      // when min > max, so the painter must bail out instead of crashing.
      const narrow = Rect.fromLTWH(0, 0, 8, 300);
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 8,
        ticksPerPixel: 125,
        panOffsetTicks: 0,
      );
      final c = _paint(
        const CursorState(primaryCursorTime: 0, secondaryCursorTime: 1000),
        deltaLabel: '1000 ns',
        mapper: mapper,
        bounds: narrow,
      );
      expect(c.rRects, isEmpty);
      expect(c.paragraphs, isEmpty);
    });
  });
}
