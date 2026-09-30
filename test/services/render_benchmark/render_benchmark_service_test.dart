// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';

import '../../helpers/render_benchmark_service.dart';

void main() {
  group('RenderBenchmarkService.buildLanes', () {
    const service = RenderBenchmarkService();

    test('returns the requested number of lanes', () {
      final lanes = service.buildLanes(signalCount: 50);
      expect(lanes, hasLength(50));
    });

    test('lanes are stacked vertically with the requested height', () {
      final lanes = service.buildLanes(signalCount: 5, laneHeight: 30);
      for (var i = 0; i < lanes.length; i++) {
        expect(lanes[i].y, 30.0 * i);
        expect(lanes[i].height, 30.0);
      }
    });

    test('produces a deterministic layout for the same seed', () {
      final a = service.buildLanes(signalCount: 30, seed: 99);
      final b = service.buildLanes(signalCount: 30, seed: 99);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].isScalar, b[i].isScalar);
        expect(a[i].isAnalog, b[i].isAnalog);
        expect(a[i].bitWidth, b[i].bitWidth);
        expect(a[i].changes.length, b[i].changes.length);
      }
    });

    test('mixes scalar, bus, and analog lanes', () {
      final lanes = service.buildLanes(signalCount: 200, seed: 7);
      final scalarCount = lanes.where((l) => l.isScalar).length;
      final analogCount = lanes.where((l) => l.isAnalog).length;
      final busCount = lanes.where((l) => !l.isScalar && !l.isAnalog).length;
      expect(scalarCount, greaterThan(0));
      expect(busCount, greaterThan(0));
      expect(analogCount, greaterThan(0));
      expect(scalarCount + busCount + analogCount, lanes.length);
    });

    test('every signal lane has the requested transition count', () {
      final lanes = service.buildLanes(
        signalCount: 20,
        transitionsPerSignal: 12,
      );
      for (final lane in lanes) {
        expect(lane.kind, WaveformLaneKind.signal);
        expect(lane.changes, hasLength(12));
      }
    });

    test('zero transitions yields lanes with empty change lists', () {
      final lanes = service.buildLanes(signalCount: 5, transitionsPerSignal: 0);
      for (final lane in lanes) {
        expect(lane.changes, isEmpty);
      }
    });
  });

  group('RenderBenchmarkService.run', () {
    const service = RenderBenchmarkService();

    test('returns one timing per measured frame', () {
      final lanes = service.buildLanes(signalCount: 10);
      final result = service.run(
        lanes: lanes,
        framesPerRun: 8,
        warmupFrames: 2,
      );
      expect(result.frames, 8);
      // frameTimesUs includes warmup frames.
      expect(result.frameTimesUs, hasLength(10));
    });

    test('reports non-zero average paint time on a populated canvas', () {
      final lanes = service.buildLanes(signalCount: 50);
      final result = service.run(
        lanes: lanes,
        framesPerRun: 5,
        warmupFrames: 1,
      );
      expect(result.avgUs, greaterThan(0));
      expect(result.minUs, lessThanOrEqualTo(result.maxUs));
      expect(result.p95Us, greaterThanOrEqualTo(result.minUs));
      expect(result.p99Us, greaterThanOrEqualTo(result.p95Us));
    });

    test('summary string includes all key metrics', () {
      final lanes = service.buildLanes(signalCount: 5);
      final result = service.run(
        lanes: lanes,
        framesPerRun: 3,
        warmupFrames: 0,
      );
      final summary = result.summary();
      expect(summary, contains('lanes=5'));
      expect(summary, contains('frames=3'));
      expect(summary, contains('avg='));
      expect(summary, contains('p95='));
      expect(summary, contains('p99='));
      expect(summary, contains('fps≈'));
    });

    test('viewport culling reduces work compared to no culling', () {
      // Build many lanes but only a small visible window.
      final lanes = service.buildLanes(
        signalCount: 500,
        transitionsPerSignal: 30,
      );
      final culled = service.run(
        lanes: lanes,
        framesPerRun: 5,
        warmupFrames: 1,
        viewportTop: 0,
        viewportBottom: 200, // ~8 lanes visible
      );
      final uncluded = service.run(
        lanes: lanes,
        framesPerRun: 5,
        warmupFrames: 1,
      );
      // Allow generous margin — paint time has noise, but culling 99% of
      // lanes must beat painting all of them by some measurable amount.
      expect(
        culled.avgUs,
        lessThan(uncluded.avgUs),
        reason:
            'culled (visible ~8/500): ${culled.summary()} '
            'vs full (500/500): ${uncluded.summary()}',
      );
    });
  });

  group('RenderBenchmarkResult', () {
    test('avgFps reports infinity when avg is zero', () {
      const result = RenderBenchmarkResult(
        signalCount: 0,
        frames: 0,
        frameTimesUs: [],
        avgUs: 0,
        p95Us: 0,
        p99Us: 0,
        minUs: 0,
        maxUs: 0,
      );
      expect(result.avgFps.isInfinite, isTrue);
      expect(result.meets60Fps, isTrue);
    });

    test('meets60Fps is true under the 60 fps budget', () {
      const result = RenderBenchmarkResult(
        signalCount: 100,
        frames: 1,
        frameTimesUs: [10000],
        avgUs: 10000, // 10 ms
        p95Us: 10000,
        p99Us: 10000,
        minUs: 10000,
        maxUs: 10000,
      );
      expect(result.meets60Fps, isTrue);
      expect(result.avgFps, closeTo(100, 0.1));
    });

    test('meets60Fps is false above the 60 fps budget', () {
      const result = RenderBenchmarkResult(
        signalCount: 1000,
        frames: 1,
        frameTimesUs: [20000],
        avgUs: 20000, // 20 ms
        p95Us: 20000,
        p99Us: 20000,
        minUs: 20000,
        maxUs: 20000,
      );
      expect(result.meets60Fps, isFalse);
    });
  });
}
