// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Print-based benchmark output is intentional — these prints are the test
// artifact, not log noise.
// ignore_for_file: avoid_print

// Timed harness for work that runs on the UI isolate in response to input:
// the canvas's per-pan data refresh, the signal tree's per-keystroke filter,
// and the X-trace's history walk.
//
// Usage (from the repo root):
//
//     flutter test --dart-define=RUN_BENCHMARKS=true \
//         test/benchmarks/ui_thread_blocking_benchmark.dart
//
// Numbers are wall-clock on the test VM (JIT), so they overstate a release
// build; the ratios between rows are what carry across.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/rendering/scalar_signal_painter.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/signal_query/x_trace_service.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

const _runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');
const Object _skip = _runBenchmarks
    ? false
    : 'Pass --dart-define=RUN_BENCHMARKS=true to run; informational only.';

/// Median of [samples], in milliseconds.
double _medianMs(List<int> samplesUs) {
  final sorted = [...samplesUs]..sort();
  return sorted[sorted.length ~/ 2] / 1000.0;
}

/// A toggling 1-bit signal with [n] changes spread over [0, end).
List<SignalChange> _clock(int n, int end) => [
  for (var i = 0; i < n; i++)
    SignalChange(time: (i * (end / n)).floor(), value: i.isEven ? '1' : '0'),
];

/// A 32-bit counter with [n] changes spread over [0, end).
List<SignalChange> _bus(int n, int end) => [
  for (var i = 0; i < n; i++)
    SignalChange(
      time: (i * (end / n)).floor(),
      value: 'b${i.toRadixString(2).padLeft(32, '0')}',
    ),
];

void main() {
  group('UI-thread blocking benchmark', () {
    // ── canvas: the data refresh one pan/zoom frame triggers ───────────────
    //
    // What `_rebuildVisibleCaches` does for every loaded lane in the
    // vertically over-scanned band, and what the scalar painter then walks.
    test('canvas refresh per pan frame', () {
      const end = 10000000;
      const lanes = 60;
      const width = 1600.0;
      const perLane = 200000;
      final source = WellenProvider();
      for (var i = 0; i < lanes; i++) {
        source.injectLoadedSignal(
          '$i',
          i.isEven ? _clock(perLane, end) : _bus(perLane ~/ 4, end),
        );
      }

      for (final (label, visStart, visEnd) in <(String, int, int)>[
        ('fit-all (whole trace visible)', 0, end),
        ('zoomed to 5% of the trace', end ~/ 2, end ~/ 2 + end ~/ 20),
      ]) {
        final mapper = TimeMapper(
          startTime: 0,
          endTime: end,
          viewportWidth: width,
          ticksPerPixel: (visEnd - visStart) / width,
          panOffsetTicks: visStart.toDouble(),
        );
        // Before: every change in the visible range, as objects.
        List<SignalChange> legacy(String r, int start, int end) =>
            source.changesInRange(r, start, end);
        // After: the visible range plus half a view either side, reduced to
        // the zoom's pixel columns.
        final span = (visEnd - visStart) ~/ 2;
        final bandStart = (visStart - span).clamp(0, end);
        final bandEnd = (visEnd + span).clamp(0, end);
        List<SignalChange> reduced(String r, int _, int _) =>
            source.changesForDisplay(
              r,
              bandStart,
              bandEnd + 1,
              ticksPerColumn: mapper.ticksPerPixel,
              columnOrigin: mapper.panOffsetTicks,
            );

        for (final (path, query, from)
            in <
              (
                String,
                List<SignalChange> Function(String, int, int),
                int,
              )
            >[
              ('changesInRange, visible range', legacy, visStart),
              ('changesForDisplay, 2-view band', reduced, bandStart),
            ]) {
          final dataUs = <int>[];
          final paintUs = <int>[];
          var materialized = 0;
          for (var frame = 0; frame < 5; frame++) {
            final sw = Stopwatch()..start();
            final caches = <String, List<SignalChange>>{};
            final initial = <String, String?>{};
            for (var i = 0; i < lanes; i++) {
              caches['$i'] = query('$i', visStart, visEnd + 1);
              initial['$i'] = source.valueAt('$i', from);
            }
            dataUs.add(sw.elapsedMicroseconds);
            materialized = caches.values.fold(0, (a, l) => a + l.length);
            sw
              ..reset()
              ..start();
            for (var i = 0; i < lanes; i++) {
              ScalarSignalPainter.debugBuildSegments(
                changes: caches['$i']!,
                valueAtStart: initial['$i'],
                timeMapper: mapper,
                xMin: 0,
                xMax: width,
              );
            }
            paintUs.add(sw.elapsedMicroseconds);
          }
          print(
            'canvas refresh, $label, $path: data ${_medianMs(dataUs)} ms, '
            'segment build ${_medianMs(paintUs)} ms, '
            '$materialized SignalChange objects '
            '($lanes lanes, ${width.toInt()} px)',
          );
        }
      }
    }, skip: _skip);

    // ── X-trace: finding where the current X streak began ───────────────────
    test('X-trace origin on a long history', () {
      const n = 1000000;
      final changes = <SignalChange>[
        for (var i = 0; i < n; i++)
          SignalChange(time: i * 10, value: i.isEven ? '1' : '0'),
        const SignalChange(time: n * 10, value: 'x'),
      ];
      final source = WellenProvider()..injectLoadedSignal('7', changes);
      const service = XTraceService();
      final samples = <int>[];
      for (var run = 0; run < 7; run++) {
        final sw = Stopwatch()..start();
        final origin = service.findXOrigin('7', 'top.sig', n * 10 + 5, source);
        samples.add(sw.elapsedMicroseconds);
        expect(origin?.originTime, n * 10);
      }
      print(
        'X-trace findXOrigin, 1M-change history: ${_medianMs(samples)} ms',
      );
    }, skip: _skip);

    // ── signal tree: one keystroke into the search box ──────────────────────
    testWidgets('signal tree search, per keystroke', (tester) async {
      // 64 blocks × 8 sub-blocks × 1000 nets = 512k variables.
      final scopes = <Scope>[
        Scope(
          name: 'top',
          path: 'top',
          type: ScopeType.module,
          childScopes: [
            for (var b = 0; b < 64; b++)
              Scope(
                name: 'blk$b',
                path: 'top.blk$b',
                type: ScopeType.module,
                childScopes: [
                  for (var s = 0; s < 8; s++)
                    Scope(
                      name: 'sub$s',
                      path: 'top.blk$b.sub$s',
                      type: ScopeType.module,
                      variables: [
                        for (var v = 0; v < 1000; v++)
                          Variable(
                            name: 'net_${b}_${s}_$v',
                            varType: VarType.wire,
                            direction: VarDirection.unknown,
                            signalRef: 'top.blk$b.sub$s.net_$v',
                            scopePath: 'top.blk$b.sub$s',
                            bitWidth: 1,
                          ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ];
      // The filter work one settled query costs, outside the widget: before,
      // the expansion and the row list each walked the hierarchy; now they
      // share one walk.
      for (final (label, shared) in [
        ('two walks', false),
        ('one walk', true),
      ]) {
        final samples = <int>[];
        for (var run = 0; run < 5; run++) {
          final sw = Stopwatch()..start();
          final first = ScopeMatchIndex.build(scopes, 'net_63_7_99');
          final second = shared
              ? first
              : ScopeMatchIndex.build(scopes, 'net_63_7_99');
          signalTreeRowsInOrder(
            scopes,
            expandedPaths: first.matchingScopePaths,
            searchQuery: 'net_63_7_99',
            matchIndex: second,
          );
          samples.add(sw.elapsedMicroseconds);
        }
        print(
          'signal tree filter per settled query ($label): '
          '${_medianMs(samples)} ms',
        );
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: SignalTreePanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Typed at ~15 characters a second: each keystroke gets 66 ms of frames
      // before the next one arrives.
      const typed = 'net_63_7_99';
      final perKey = <int>[];
      final sw = Stopwatch()..start();
      for (var i = 1; i <= typed.length; i++) {
        final k = Stopwatch()..start();
        await tester.enterText(find.byType(TextField), typed.substring(0, i));
        await tester.pump(const Duration(milliseconds: 66));
        perKey.add(k.elapsedMicroseconds);
      }
      final burst = sw.elapsedMicroseconds;
      final settle = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      final settleUs = settle.elapsedMicroseconds;
      // The search field and the one matching leaf row.
      expect(find.text('net_63_7_99'), findsNWidgets(2));
      print(
        'signal tree search, 512k variables: '
        'median keystroke ${_medianMs(perKey)} ms, '
        'max keystroke ${(perKey.reduce((a, b) => a > b ? a : b)) / 1000} ms, '
        '${typed.length}-key burst ${burst / 1000} ms, '
        'settle after burst ${settleUs / 1000} ms',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, skip: !_runBenchmarks);
  });
}
