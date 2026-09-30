// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Standalone WaveCrux engine benchmark, runnable under `flutter test`.
//
// This is intentionally hosted under test/ so it picks up the Flutter
// dart:ui binding that wellen_provider_io.dart transitively requires
// (via package:flutter/foundation). The bench itself is pure Dart and
// does no widget work.
//
// Usage:
//
//   PERF_FIXTURE=build/perf/fixtures/large.vcd \
//   PERF_LABEL=baseline_main \
//   PERF_SIGNALS=1000 \
//     flutter test test/perf/engine_bench.dart
//
// Outputs one JSON object per run to build/perf/results.jsonl with the
// metrics that dominate user-facing performance on multi-GB captures.

// The bench's whole job is to print a one-line summary plus a JSONL row;
// the `print` calls ARE the user-facing artifact, not log noise.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/waveform/wellen_provider_io.dart';

void main() {
  test(
    'engine perf — file open / signal load / cached queries / RSS',
    () async {
      final fixture = Platform.environment['PERF_FIXTURE'];
      if (fixture == null || fixture.isEmpty) {
        print('PERF_FIXTURE not set — skipping benchmark.');
        return;
      }
      if (!File(fixture).existsSync()) {
        fail('Fixture not found: $fixture');
      }

      final label = Platform.environment['PERF_LABEL'] ?? 'untitled';
      final targetSignalLoadCount =
          int.tryParse(Platform.environment['PERF_SIGNALS'] ?? '') ?? 1000;
      final valueQueryCount =
          int.tryParse(Platform.environment['PERF_QUERIES'] ?? '') ?? 100000;
      final rangeQueryCount =
          int.tryParse(Platform.environment['PERF_RANGE_QUERIES'] ?? '') ??
          10000;
      final appendPath =
          Platform.environment['PERF_APPEND'] ?? 'build/perf/results.jsonl';
      final openTimeoutSec =
          int.tryParse(Platform.environment['PERF_OPEN_TIMEOUT'] ?? '') ?? 600;

      final fileSizeMb = File(fixture).lengthSync() / (1024 * 1024);
      final rssStart = ProcessInfo.currentRss;

      print('=== WaveCrux engine benchmark ===');
      print('fixture: $fixture (${fileSizeMb.toStringAsFixed(1)} MB)');
      print('label:   $label');

      final provider = WellenProvider(
        openTimeout: Duration(seconds: openTimeoutSec),
      );
      final openSw = Stopwatch()..start();
      await provider.openFile(fixture);
      openSw.stop();
      final openMs = openSw.elapsedMilliseconds;
      final rssAfterOpen = ProcessInfo.currentRss;

      final allVars = provider.findVariables(const SignalFilter());
      print(
        'open: ${openMs}ms; signals=${allVars.length}; '
        'transitions=${provider.totalTransitions}; '
        'rss=${_mb(rssAfterOpen).toStringAsFixed(0)}MB',
      );

      final loadLatencies = <int>[];
      final perPositionMs = <int, double>{};
      final loadCount = math.min(targetSignalLoadCount, allVars.length);
      for (var i = 0; i < loadCount; i++) {
        final sw = Stopwatch()..start();
        await provider.loadSignal(allVars[i].signalRef);
        sw.stop();
        final us = sw.elapsedMicroseconds;
        loadLatencies.add(us);
        if (i == 0 || i == 9 || i == 99 || i == 999) {
          perPositionMs[i + 1] = us / 1000.0;
        }
      }
      loadLatencies.sort();
      final loadP50 = _percentile(loadLatencies, 0.50);
      final loadP95 = _percentile(loadLatencies, 0.95);
      final loadP99 = _percentile(loadLatencies, 0.99);
      final loadMax = loadLatencies.last;
      final rssAfterAll = ProcessInfo.currentRss;

      print(
        'signal loads: '
        '1st=${perPositionMs[1]?.toStringAsFixed(1)}ms '
        '10th=${perPositionMs[10]?.toStringAsFixed(1)}ms '
        '100th=${perPositionMs[100]?.toStringAsFixed(1)}ms '
        '1000th=${perPositionMs[1000]?.toStringAsFixed(1)}ms',
      );
      print(
        'signal load p50/p95/p99/max: '
        '${(loadP50 / 1000).toStringAsFixed(2)}/'
        '${(loadP95 / 1000).toStringAsFixed(2)}/'
        '${(loadP99 / 1000).toStringAsFixed(2)}/'
        '${(loadMax / 1000).toStringAsFixed(2)} ms',
      );
      print(
        'rss after $loadCount signals: '
        '${_mb(rssAfterAll).toStringAsFixed(0)}MB '
        '(+${_mb(rssAfterAll - rssStart).toStringAsFixed(0)}MB from start)',
      );

      final random = math.Random(42);
      final loadedRefs = allVars
          .take(loadCount)
          .map((v) => v.signalRef)
          .toList();
      final endTime = provider.endTime;

      final valueQuerySw = Stopwatch()..start();
      var valueHits = 0;
      for (var i = 0; i < valueQueryCount; i++) {
        final ref = loadedRefs[random.nextInt(loadedRefs.length)];
        final t = endTime > 0 ? random.nextInt(endTime) : 0;
        if (provider.valueAt(ref, t) != null) valueHits++;
      }
      valueQuerySw.stop();
      final valueUs = valueQueryCount == 0
          ? 0.0
          : valueQuerySw.elapsedMicroseconds / valueQueryCount;
      print(
        'valueAt: ${valueUs.toStringAsFixed(2)} µs/call '
        '($valueHits/$valueQueryCount hits)',
      );

      final windowSize = math.max(1, endTime ~/ 20);
      final rangeQuerySw = Stopwatch()..start();
      var rangeRowCount = 0;
      var sinkSum = 0; // forces the iteration to do real work, not be DCE'd
      for (var i = 0; i < rangeQueryCount; i++) {
        final ref = loadedRefs[random.nextInt(loadedRefs.length)];
        final start = endTime > windowSize
            ? random.nextInt(endTime - windowSize)
            : 0;
        // Iterate the full result reading both .time and .value, since that
        // is what every real caller (canvas paint, fsm_analysis, x_trace,
        // diff, switching_activity, pattern_search) does. A length-only read
        // misrepresents the cost — the view-vs-eager trade-off shows up
        // only when the caller actually touches each element.
        final result = provider.changesInRange(ref, start, start + windowSize);
        for (final change in result) {
          sinkSum += change.time;
          if (change.value.isNotEmpty) sinkSum++;
        }
        rangeRowCount += result.length;
      }
      rangeQuerySw.stop();
      // Keep the sink alive so the compiler can't elide the iteration.
      if (sinkSum < 0) print('unreachable: $sinkSum');
      final rangeUs = rangeQueryCount == 0
          ? 0.0
          : rangeQuerySw.elapsedMicroseconds / rangeQueryCount;
      print(
        'changesInRange: ${rangeUs.toStringAsFixed(2)} µs/call '
        '(avg ${rangeRowCount / math.max(1, rangeQueryCount)} rows)',
      );

      final nativeBytes = await provider.memoryUsageBytes();
      print('wellen native heap: ${_mb(nativeBytes).toStringAsFixed(0)}MB');

      // Capture provider state BEFORE close — close() zeroes the cached
      // hierarchy + diagnostic counters.
      final totalTransitions = provider.totalTransitions;
      final signalCount = allVars.length;

      provider.close();

      final gitSha = await _gitSha();
      final row = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'label': label,
        'fixture': fixture,
        'file_size_mb': double.parse(fileSizeMb.toStringAsFixed(2)),
        'git_sha': gitSha,
        'open_ms': openMs,
        'first_signal_ms': perPositionMs[1],
        'tenth_signal_ms': perPositionMs[10],
        'hundredth_signal_ms': perPositionMs[100],
        'thousandth_signal_ms': perPositionMs[1000],
        'load_p50_ms': double.parse((loadP50 / 1000).toStringAsFixed(3)),
        'load_p95_ms': double.parse((loadP95 / 1000).toStringAsFixed(3)),
        'load_p99_ms': double.parse((loadP99 / 1000).toStringAsFixed(3)),
        'load_max_ms': double.parse((loadMax / 1000).toStringAsFixed(3)),
        'value_query_us': double.parse(valueUs.toStringAsFixed(3)),
        'range_query_us': double.parse(rangeUs.toStringAsFixed(3)),
        'rss_start_mb': double.parse(_mb(rssStart).toStringAsFixed(1)),
        'rss_after_open_mb': double.parse(_mb(rssAfterOpen).toStringAsFixed(1)),
        'rss_peak_mb': double.parse(_mb(rssAfterAll).toStringAsFixed(1)),
        'rss_delta_mb': double.parse(
          _mb(rssAfterAll - rssStart).toStringAsFixed(1),
        ),
        'native_heap_mb': double.parse(_mb(nativeBytes).toStringAsFixed(1)),
        'total_transitions': totalTransitions,
        'signal_count': signalCount,
        'loaded_count': loadCount,
      };

      final outFile = File(appendPath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsStringSync(
        '${jsonEncode(row)}\n',
        mode: FileMode.append,
        flush: true,
      );
      print('\nappended → ${outFile.path}');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

double _mb(int bytes) => bytes / (1024 * 1024);

int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final idx = ((sorted.length - 1) * p).round();
  return sorted[idx];
}

Future<String> _gitSha() async {
  try {
    final r = await Process.run('git', ['rev-parse', '--short', 'HEAD']);
    return (r.stdout as String).trim();
  } on Object {
    return 'unknown';
  }
}
