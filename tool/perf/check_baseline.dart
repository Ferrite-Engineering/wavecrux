// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Compares the latest perf-benchmark metrics against a committed baseline and
// fails (exit 1) on a *material* regression. Hosted CI runners are noisy, so
// the gate is deliberately generous (default 1.5x) — it catches real
// regressions, not run-to-run jitter.
//
// Inputs (all optional; missing inputs are skipped, not failed):
//   build/perf/results.jsonl        engine_bench rows (one per fixture/label)
//   build/perf/paint_results.jsonl  waveform_paint_benchmark rows (per signals)
//   tool/perf/baseline.json         committed baseline (absent → report-only)
//
// baseline.json shape:
//   {
//     "threshold": 1.5,        // fallback, for any metric not named below
//     "thresholds": { "open_ms": 2.0, "rss_peak_mb": 1.25 },
//     "engine": { "<label>": { "open_ms": N, "value_query_us": N,
//                              "range_query_us": N, "rss_peak_mb": N } },
//     "paint":  { "1000": { "culled_p95_us": N }, "2000": { "culled_p95_us": N } }
//   }
//
// Each metric takes its multiplier from `thresholds` when named there and
// from `threshold` otherwise, because the metrics are not equally noisy:
// wall-clock opens swing ~2x run to run on a hosted runner while peak RSS
// holds inside 1.05x. See baseline.json's `_thresholds_rationale`.
//
// Env: PERF_THRESHOLD overrides the multiplier for EVERY metric.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const _engineMetrics = [
  'open_ms',
  'value_query_us',
  'range_query_us',
  'rss_peak_mb',
];
const _paintMetrics = ['culled_p95_us'];

List<Map<String, dynamic>> _readJsonl(String path) {
  final f = File(path);
  if (!f.existsSync()) return const [];
  return f
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
}

void main() {
  final baselineFile = File('tool/perf/baseline.json');
  final baselineMap = baselineFile.existsSync()
      ? jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>
      : null;

  // One threshold for every metric was the wrong shape. Measured over six
  // weekly runs on hosted runners, the timing metrics swing 1.6-1.97x
  // peak-to-trough while `rss_peak_mb` holds inside 1.05x — so a single
  // figure is simultaneously too tight for a wall-clock open (it fired on
  // 2026-09-23 at 1.52x, with the 490 MB fixture FASTER than the week
  // before) and far too loose for memory, where a real 30% leak would have
  // sailed through. `thresholds` gives each metric its own multiplier;
  // `threshold` remains the fallback for any metric not listed.
  //
  // PERF_THRESHOLD still overrides everything — it is the escape hatch for
  // a one-off investigation, and applies to every metric.
  final envThreshold = double.tryParse(
    Platform.environment['PERF_THRESHOLD'] ?? '',
  );
  final globalThreshold =
      envThreshold ?? (baselineMap?['threshold'] as num?)?.toDouble() ?? 1.5;
  final perMetric =
      (baselineMap?['thresholds'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  double thresholdFor(String metric) =>
      envThreshold ??
      (perMetric[metric] as num?)?.toDouble() ??
      globalThreshold;

  final engine = _readJsonl('build/perf/results.jsonl');
  final paint = _readJsonl('build/perf/paint_results.jsonl');

  final shownThresholds = [
    ...{...perMetric.keys, ..._engineMetrics, ..._paintMetrics},
  ]..sort();
  print(
    '── Perf check (thresholds: '
    '${shownThresholds.map((m) => '$m ${thresholdFor(m)}x').join(', ')}) ──',
  );
  for (final row in engine) {
    print(
      'engine[${row['label']}]: open=${row['open_ms']}ms '
      'valueQ=${row['value_query_us']}us rangeQ=${row['range_query_us']}us '
      'rssPeak=${row['rss_peak_mb']}MB size=${row['file_size_mb']}MB',
    );
  }
  for (final row in paint) {
    print(
      'paint[${row['signals']} signals]: culled_p95=${row['culled_p95_us']}us '
      'culled_avg=${row['culled_avg_us']}us',
    );
  }

  if (baselineMap == null) {
    print(
      '\nNo tool/perf/baseline.json yet — REPORT ONLY (no gate). '
      'Commit a baseline from these numbers to enable regression gating.',
    );
    return;
  }

  final baseline = baselineMap;
  final regressions = <String>[];

  void check(String scope, num? cur, num? base, String metric) {
    if (cur == null || base == null || base <= 0) return;
    final limit = thresholdFor(metric);
    final ratio = cur / base;
    final flag = ratio > limit ? '  <-- REGRESSION' : '';
    print(
      '  $scope.$metric: $cur vs baseline $base  '
      '(${ratio.toStringAsFixed(2)}x, limit ${limit}x)$flag',
    );
    if (ratio > limit) {
      regressions.add('$scope.$metric $cur > ${limit}x baseline $base');
    }
  }

  final engineBase =
      (baseline['engine'] as Map?)?.cast<String, dynamic>() ?? {};
  for (final row in engine) {
    final label = '${row['label']}';
    final b = (engineBase[label] as Map?)?.cast<String, dynamic>();
    if (b == null) continue;
    for (final m in _engineMetrics) {
      check('engine[$label]', row[m] as num?, b[m] as num?, m);
    }
  }

  final paintBase = (baseline['paint'] as Map?)?.cast<String, dynamic>() ?? {};
  for (final row in paint) {
    final key = '${row['signals']}';
    final b = (paintBase[key] as Map?)?.cast<String, dynamic>();
    if (b == null) continue;
    for (final m in _paintMetrics) {
      check('paint[$key]', row[m] as num?, b[m] as num?, m);
    }
  }

  if (regressions.isNotEmpty) {
    print('\n::error::perf regression(s) beyond the per-metric threshold:');
    for (final r in regressions) {
      print('  - $r');
    }
    exit(1);
  }
  print('\nNo material perf regressions vs baseline.');
}
