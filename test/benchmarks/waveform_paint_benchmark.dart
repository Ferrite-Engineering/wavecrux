// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Print-based benchmark output is intentional — these prints are the test
// artifact, not log noise.
// ignore_for_file: avoid_print

//
// Runnable benchmark for the waveform canvas paint pipeline.
//
// Usage (from the repo root):
//
//     flutter test --dart-define=RUN_BENCHMARKS=true \
//         test/benchmarks/waveform_paint_benchmark.dart
//
// (The gate uses `bool.fromEnvironment`, which is compile-time and only
// accepts the literal string `true` — a process env var like
// `RUN_BENCHMARKS=1` is silently ignored.)
//
// Reports avg / p95 / p99 / min / max paint times in milliseconds for
// representative signal counts (100 / 500 / 1000 / 2000), comparing the
// "viewport-culled" path (typical real-world usage where only a slice of
// lanes is visible) against the "all-lanes" path (legacy behavior, useful
// to quantify the win from culling).
//
// This file lives under test/benchmarks/ and uses the standard
// flutter_test runner so it runs without any additional tooling.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/render_benchmark_service.dart';

void main() {
  // Skip on automated CI runs by default — benchmarks are noisy and not a
  // pass/fail signal. To enable:
  //   flutter test --dart-define=RUN_BENCHMARKS=true \
  //       test/benchmarks/waveform_paint_benchmark.dart
  const runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');

  test(
    'waveform paint benchmark — avg/p95/p99 across signal counts',
    () {
      const service = RenderBenchmarkService();

      // Realistic landscape canvas at common laptop resolution.
      const canvasWidth = 1920.0;
      const canvasHeight = 800.0;

      // Tablet (~500 lanes visible) and phone (~100 lanes visible) targets
      // for the mobile layouts; desktop is 1000+ visible.
      const signalCounts = [100, 500, 1000, 2000];

      const ruler =
          '──────────────────────────────────────────────────────────────────────────────';

      print(
        '\nWaveform paint benchmark — '
        'canvas=${canvasWidth.toInt()}x${canvasHeight.toInt()}',
      );
      print('  $ruler');

      // When PERF_PAINT_OUT is set (CI), append one JSONL row per signal count
      // so tool/perf/check_baseline.dart can gate render perf against the
      // committed baseline. No-op for local/manual runs.
      final paintOut = Platform.environment['PERF_PAINT_OUT'];
      final rows = <Map<String, Object?>>[];

      for (final count in signalCounts) {
        final lanes = service.buildLanes(signalCount: count);

        final culledResult = service.run(
          lanes: lanes,
          // Real-world usage: only the portion visible on screen is painted.
          viewportTop: 0,
          viewportBottom: canvasHeight,
        );

        // Legacy: paint every lane regardless of scroll position.
        final fullResult = service.run(lanes: lanes);

        print('  signals=$count');
        print('    culled (visible window): ${culledResult.summary()}');
        print('    no culling             : ${fullResult.summary()}');

        rows.add(<String, Object?>{
          'signals': count,
          'culled_avg_us': culledResult.avgUs,
          'culled_p95_us': culledResult.p95Us,
          'full_avg_us': fullResult.avgUs,
          'full_p95_us': fullResult.p95Us,
        });
      }

      print('  $ruler\n');

      if (paintOut != null && paintOut.isNotEmpty) {
        final f = File(paintOut);
        f.parent.createSync(recursive: true);
        final buf = StringBuffer();
        for (final r in rows) {
          buf.writeln(jsonEncode(r));
        }
        f.writeAsStringSync(buf.toString());
        print('  wrote paint metrics → $paintOut');
      }
    },
    skip: !runBenchmarks
        ? 'Pass --dart-define=RUN_BENCHMARKS=true to run; '
              'this benchmark is informational.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
