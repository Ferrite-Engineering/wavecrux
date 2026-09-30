// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';

const _base = RenderPipelineStats(
  visibleSignalRows: 42,
  visibleTransitions: 18400,
  lineSegmentsDrawn: 9200,
  layoutTimeUs: 200,
  scalarPaintTimeUs: 1500,
  vectorPaintTimeUs: 3200,
  analogPaintTimeUs: 800,
  cursorPaintTimeUs: 50,
  transactionPaintTimeUs: 400,
  totalPaintTimeUs: 8200,
  canvasWidth: 1280,
  canvasHeight: 720,
);

void main() {
  group('RenderPipelineStats', () {
    test('stores all fields', () {
      expect(_base.visibleSignalRows, 42);
      expect(_base.visibleTransitions, 18400);
      expect(_base.lineSegmentsDrawn, 9200);
      expect(_base.layoutTimeUs, 200);
      expect(_base.scalarPaintTimeUs, 1500);
      expect(_base.vectorPaintTimeUs, 3200);
      expect(_base.analogPaintTimeUs, 800);
      expect(_base.cursorPaintTimeUs, 50);
      expect(_base.transactionPaintTimeUs, 400);
      expect(_base.totalPaintTimeUs, 8200);
      expect(_base.canvasWidth, 1280);
      expect(_base.canvasHeight, 720);
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      expect(_base.copyWith(), equals(_base));
    });

    test('copyWith changes only visibleSignalRows', () {
      final updated = _base.copyWith(visibleSignalRows: 10);
      expect(updated.visibleSignalRows, 10);
      expect(updated.visibleTransitions, _base.visibleTransitions);
      expect(updated.totalPaintTimeUs, _base.totalPaintTimeUs);
      expect(updated.canvasWidth, _base.canvasWidth);
    });

    test('copyWith changes only canvasWidth and canvasHeight', () {
      final updated = _base.copyWith(canvasWidth: 1920, canvasHeight: 1080);
      expect(updated.canvasWidth, 1920);
      expect(updated.canvasHeight, 1080);
      expect(updated.visibleSignalRows, _base.visibleSignalRows);
    });

    test('copyWith changes only totalPaintTimeUs', () {
      final updated = _base.copyWith(totalPaintTimeUs: 16000);
      expect(updated.totalPaintTimeUs, 16000);
      expect(updated.scalarPaintTimeUs, _base.scalarPaintTimeUs);
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal objects compare as equal', () {
      final a = _base.copyWith();
      final b = _base.copyWith();
      expect(a, equals(b));
    });

    test('differing visibleTransitions makes objects unequal', () {
      final a = _base.copyWith(visibleTransitions: 100);
      final b = _base.copyWith(visibleTransitions: 200);
      expect(a, isNot(equals(b)));
    });

    test('differing canvasHeight makes objects unequal', () {
      final a = _base.copyWith(canvasHeight: 600);
      final b = _base.copyWith(canvasHeight: 720);
      expect(a, isNot(equals(b)));
    });

    // ── hashCode ──────────────────────────────────────────────────────────────

    test('equal objects have equal hashCodes', () {
      final a = _base.copyWith();
      final b = _base.copyWith();
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains visibleSignalRows and totalPaintTimeUs', () {
      final s = _base.toString();
      expect(s, contains('42'));
      expect(s, contains('8200'));
    });

    test('toString contains canvas dimensions', () {
      final s = _base.toString();
      expect(s, contains('1280'));
      expect(s, contains('720'));
    });
  });
}
