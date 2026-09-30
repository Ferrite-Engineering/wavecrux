// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/waveform/streaming_vcd_service.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

const _simpleVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 8 # data $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
b00000000 #
$end
#10
1!
#20
0!
b00000001 #
#30
1!
''';

Stream<List<int>> _toStream(String vcd, {int chunkSize = 1024}) async* {
  final bytes = utf8.encode(vcd);
  for (var i = 0; i < bytes.length; i += chunkSize) {
    yield bytes.sublist(i, (i + chunkSize).clamp(0, bytes.length));
  }
}

StreamingVcdService _service() =>
    StreamingVcdService(updateInterval: Duration.zero);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('StreamingVcdService', () {
    group('header parsing', () {
      test(r'resolves headerParsedFuture after $enddefinitions', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        expect(svc.isHeaderParsed, isTrue);
      });

      test('exposes root scopes after header', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        expect(svc.rootScopes, hasLength(1));
        expect(svc.rootScopes.first.name, 'top');
      });

      test('exposes variables after header', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        final vars = svc.rootScopes.first.variables;
        expect(vars, hasLength(2));
        expect(vars.map((v) => v.name), containsAll(['clk', 'data']));
      });

      test('reads timescale factor', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        expect(svc.timescale, isNotNull);
        expect(svc.timescale!.factor, 1);
      });

      test('startTime is 0 before any value changes', () async {
        const headerOnly = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
''';
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(headerOnly));
        expect(svc.startTime, 0);
      });
    });

    group('value changes', () {
      test('valueAt returns initial dumpvars value', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        final clkRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'clk')
            .signalRef;
        await svc.loadSignal(clkRef);
        expect(svc.valueAt(clkRef, 0), '0');
      });

      test('valueAt returns updated value after transitions', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        final clkRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'clk')
            .signalRef;
        await svc.loadSignal(clkRef);
        expect(svc.valueAt(clkRef, 10), '1');
        expect(svc.valueAt(clkRef, 20), '0');
        expect(svc.valueAt(clkRef, 30), '1');
      });

      test('endTime updates as data arrives', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;
        expect(svc.endTime, greaterThan(0));
        expect(svc.currentEndTime, svc.endTime);
      });

      test('changesInRange returns transitions within range', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        final clkRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'clk')
            .signalRef;
        await svc.loadSignal(clkRef);
        final changes = svc.changesInRange(clkRef, 0, 30);
        expect(changes.length, greaterThanOrEqualTo(2));
        expect(changes.first.value, '0');
      });

      test('vector signal value accessible', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        final dataRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'data')
            .signalRef;
        await svc.loadSignal(dataRef);
        expect(svc.valueAt(dataRef, 0), '00000000');
        expect(svc.valueAt(dataRef, 20), '00000001');
      });
    });

    group('chunk boundary handling', () {
      test('parses VCD split into single-byte chunks', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd, chunkSize: 1));
        await svc.streamEndedFuture;

        expect(svc.rootScopes, hasLength(1));
        expect(svc.rootScopes.first.variables, hasLength(2));
        expect(svc.endTime, greaterThan(0));
      });

      test('parses VCD split into 7-byte chunks', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd, chunkSize: 7));
        await svc.streamEndedFuture;

        expect(svc.isHeaderParsed, isTrue);
        expect(svc.rootScopes.first.variables, hasLength(2));
      });
    });

    group('incremental streaming', () {
      test('onDataUpdated fires after value changes arrive', () async {
        final svc = _service();
        addTearDown(svc.close);

        var updateCount = 0;
        svc.onDataUpdated.listen((_) => updateCount++);

        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        expect(updateCount, greaterThan(0));
      });

      test('can deliver header in first chunk and values in second', () async {
        const header = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
''';
        const values = r'''
$dumpvars
0!
$end
#10
1!
#20
0!
''';

        final controller = StreamController<List<int>>();
        final svc = _service();
        addTearDown(svc.close);

        svc.startFromStream(controller.stream);
        controller.add(utf8.encode(header));
        await svc.headerParsedFuture;
        expect(svc.isHeaderParsed, isTrue);

        controller.add(utf8.encode(values));
        await controller.close();
        await svc.streamEndedFuture;

        final clkRef = svc.rootScopes.first.variables.first.signalRef;
        await svc.loadSignal(clkRef);
        expect(svc.valueAt(clkRef, 10), '1');
        expect(svc.endTime, 20);
      });
    });

    group('stop and close', () {
      test('stop completes streamEndedFuture', () async {
        final controller = StreamController<List<int>>();
        final svc = _service();
        // Swallow the unhandled headerParsedFuture error that close() will raise.
        unawaited(svc.headerParsedFuture.catchError((_) {}));

        svc
          ..startFromStream(controller.stream)
          ..stop();
        await expectLater(svc.streamEndedFuture, completes);
        svc.close();
      });

      test('close releases resources idempotently', () async {
        final svc = _service();
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        svc
          ..close()
          ..close(); // second call must not throw
      });

      test('close errors headerParsedFuture if header not yet seen', () async {
        final controller = StreamController<List<int>>();
        final svc = _service()
          ..startFromStream(controller.stream)
          ..close();
        await expectLater(svc.headerParsedFuture, throwsStateError);
      });
    });

    group('signal loading', () {
      test('isSignalLoaded false before loadSignal', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));

        final clkRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'clk')
            .signalRef;
        expect(svc.isSignalLoaded(clkRef), isFalse);
      });

      test('isSignalLoaded returns true after loadSignal', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));

        final clkRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'clk')
            .signalRef;
        await svc.loadSignal(clkRef);
        expect(svc.isSignalLoaded(clkRef), isTrue);
      });
    });

    group('findVariables', () {
      test('returns all variables with empty filter', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        final vars = svc.findVariables(const SignalFilter());
        expect(vars.length, greaterThanOrEqualTo(2));
      });

      test('filters by name pattern', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));

        final vars = svc.findVariables(const SignalFilter(namePattern: 'clk'));
        expect(vars, hasLength(1));
        expect(vars.first.name, 'clk');
      });
    });

    group('deep hierarchy VCD', () {
      test('parses nested scopes', () async {
        const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$scope module core $end
$var wire 1 ! clk $end
$upscope $end
$upscope $end
$enddefinitions $end
''';
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(vcd));
        expect(svc.rootScopes.first.name, 'top');
        expect(svc.rootScopes.first.childScopes.first.name, 'core');
      });
    });

    group('nextTransition / prevTransition', () {
      test('nextTransition finds next rising edge', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        final clkRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'clk')
            .signalRef;
        await svc.loadSignal(clkRef);
        final next = svc.nextTransition(clkRef, 5);
        expect(next, isNotNull);
        expect(next!.time, 10);
        expect(next.value, '1');
      });

      test('prevTransition finds previous edge', () async {
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(_simpleVcd));
        await svc.streamEndedFuture;

        final clkRef = svc.rootScopes.first.variables
            .firstWhere((v) => v.name == 'clk')
            .signalRef;
        await svc.loadSignal(clkRef);
        final prev = svc.prevTransition(clkRef, 25);
        expect(prev, isNotNull);
        expect(prev!.time, 20);
      });
    });

    group('targeted chunk-boundary splits', () {
      test(
        'split inside vector bits token reconstructs correct value',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 8 @ data $end
$upscope $end
$enddefinitions $end
#0
b11001010 @
''';
          final bytes = utf8.encode(vcd);
          // 'b1100' | '1010 @\n'
          final splitIdx = vcd.indexOf('b11001010') + 5;

          final ctrl = StreamController<List<int>>();
          final svc = _service();
          addTearDown(svc.close);

          svc.startFromStream(ctrl.stream);
          ctrl
            ..add(bytes.sublist(0, splitIdx))
            ..add(bytes.sublist(splitIdx));
          await ctrl.close();
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          expect(svc.valueAt(ref, 0), '11001010');
        },
      );

      test(
        'split between vector bits and idcode reconstructs correctly',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 4 % nibble $end
$upscope $end
$enddefinitions $end
#0
b1101 %
''';
          final bytes = utf8.encode(vcd);
          // 'b1101 ' | '% ...' — split after the space before the idcode
          final splitIdx = vcd.indexOf('b1101 ') + 'b1101 '.length;

          final ctrl = StreamController<List<int>>();
          final svc = _service();
          addTearDown(svc.close);

          svc.startFromStream(ctrl.stream);
          ctrl
            ..add(bytes.sublist(0, splitIdx))
            ..add(bytes.sublist(splitIdx));
          await ctrl.close();
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          expect(svc.valueAt(ref, 0), '1101');
        },
      );

      test('split inside timestamp token reconstructs correct time', () async {
        const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#12345
1!
''';
        final bytes = utf8.encode(vcd);
        final splitIdx = vcd.indexOf('#12345') + 3; // '#12' | '345\n1!\n'

        final ctrl = StreamController<List<int>>();
        final svc = _service();
        addTearDown(svc.close);

        svc.startFromStream(ctrl.stream);
        ctrl
          ..add(bytes.sublist(0, splitIdx))
          ..add(bytes.sublist(splitIdx));
        await ctrl.close();
        await svc.streamEndedFuture;

        expect(svc.endTime, 12345);
      });

      test(
        r'split across $enddefinitions keyword still finalizes header',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! sig $end
$upscope $end
$enddefinitions $end
#5
1!
''';
          final bytes = utf8.encode(vcd);
          // '$enddefi' | 'nitions $end ...'
          final splitIdx = vcd.indexOf(r'$enddefinitions') + 8;

          final ctrl = StreamController<List<int>>();
          final svc = _service();
          addTearDown(svc.close);

          svc.startFromStream(ctrl.stream);
          ctrl
            ..add(bytes.sublist(0, splitIdx))
            ..add(bytes.sublist(splitIdx));
          await ctrl.close();
          await svc.streamEndedFuture;

          expect(svc.isHeaderParsed, isTrue);
          expect(svc.endTime, 5);
        },
      );
    });

    group('stream interruption', () {
      test(
        r'stream closes before $enddefinitions finalizes header gracefully',
        () async {
          // Simulates a simulator that exits before writing $enddefinitions.
          const incomplete = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
''';
          final svc = _service();
          addTearDown(svc.close);

          svc.startFromStream(_toStream(incomplete));
          await svc.streamEndedFuture;

          // _onDone must call _finalizeHeader; unclosed scopes must be popped.
          expect(svc.isHeaderParsed, isTrue);
          expect(svc.rootScopes, hasLength(1));
          expect(svc.rootScopes.first.variables, hasLength(1));
        },
      );

      test(
        'stream closes mid-value-section — partial data accessible',
        () async {
          const header = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
''';
          final ctrl = StreamController<List<int>>();
          final svc = _service();
          addTearDown(svc.close);

          svc.startFromStream(ctrl.stream);
          ctrl.add(utf8.encode(header));
          await svc.headerParsedFuture;

          ctrl.add(utf8.encode('#10\n1!\n')); // first transition only
          await ctrl.close(); // close before #20 arrives
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          expect(svc.valueAt(ref, 10), '1');
          expect(svc.endTime, 10);
        },
      );

      test(
        'streamEndedFuture resolves when stream closes before header is complete',
        () async {
          final ctrl = StreamController<List<int>>();
          final svc = _service();
          unawaited(svc.headerParsedFuture.catchError((_) {}));
          addTearDown(svc.close);

          svc.startFromStream(ctrl.stream);
          ctrl.add(
            utf8.encode(
              r'$timescale 1 ns $end'
              '\n',
            ),
          );
          await ctrl.close(); // close mid-header

          await expectLater(svc.streamEndedFuture, completes);
        },
      );

      test('onStreamEnded fires exactly once on premature close', () async {
        final ctrl = StreamController<List<int>>();
        final svc = _service();
        addTearDown(svc.close);

        var firedCount = 0;
        // onStreamEnded uses a broadcast() controller that delivers events
        // asynchronously. Use a Completer to await the actual callback rather
        // than relying on indirect synchronisation via streamEndedFuture.
        final listenerFired = Completer<void>();
        svc.onStreamEnded.listen((_) {
          firedCount++;
          if (!listenerFired.isCompleted) listenerFired.complete();
        });

        svc.startFromStream(ctrl.stream);
        ctrl.add(utf8.encode(_simpleVcd));
        await ctrl.close();
        await listenerFired.future;

        expect(firedCount, 1);
      });
    });

    group('malformed VCD handling', () {
      test('unknown header directive is silently skipped', () async {
        const vcd = r'''
$timescale 1 ns $end
$garbage some tokens here $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
''';
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(vcd));

        expect(svc.isHeaderParsed, isTrue);
        expect(svc.rootScopes.first.variables, hasLength(1));
      });

      test(r'$comment block in value section is skipped entirely', () async {
        const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#10
1!
$comment this is a mid-simulation comment $end
#20
0!
''';
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(vcd));
        await svc.streamEndedFuture;

        final ref = svc.rootScopes.first.variables.first.signalRef;
        await svc.loadSignal(ref);
        expect(svc.valueAt(ref, 10), '1');
        expect(svc.valueAt(ref, 20), '0');
        expect(svc.endTime, 20);
      });

      test(
        'garbled scalar token (non-01xz first char) is silently ignored',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#10
1!
garbled!
#20
0!
''';
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          // The garbled token is skipped; clk changes on either side are intact.
          expect(svc.valueAt(ref, 10), '1');
          expect(svc.valueAt(ref, 20), '0');
        },
      );

      test(
        'malformed timestamp #abc is ignored — current time is unchanged',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#100
1!
#abc
0!
#200
z!
''';
          // '0!' after '#abc' is recorded at the previous valid time (100).
          // 'z!' is correctly recorded at #200.
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          expect(svc.endTime, 200);
          expect(svc.valueAt(ref, 200), 'z');
        },
      );

      test(r'incomplete $var declaration (< 4 tokens) is skipped', () async {
        const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
''';
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(vcd));

        // Only the valid declaration should appear.
        expect(svc.rootScopes.first.variables, hasLength(1));
        expect(svc.rootScopes.first.variables.first.name, 'clk');
      });

      test(
        'signal with no value changes returns null from all query methods',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
''';
          // No value section — the signal is declared but has an empty change list.
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);

          expect(svc.valueAt(ref, 0), isNull);
          expect(svc.changesInRange(ref, 0, 100), isEmpty);
          expect(svc.nextTransition(ref, 0), isNull);
          expect(svc.prevTransition(ref, 100), isNull);
        },
      );

      test(
        'value changes for undeclared idcodes do not crash the service',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#10
1!
1Z
''';
          // 'Z' was never declared; the service must not throw.
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          expect(svc.valueAt(ref, 10), '1');
          // The undeclared idcode must not appear in the public variable list.
          expect(svc.findVariables(const SignalFilter()), hasLength(1));
        },
      );
    });

    group('timestamp regression', () {
      test('endTime never decreases on a timestamp regression', () async {
        const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#100
1!
#200
0!
#50
1!
''';
        final svc = _service();
        addTearDown(svc.close);
        await svc.startAndWaitForHeader(_toStream(vcd));
        await svc.streamEndedFuture;

        // endTime tracks the maximum timestamp seen, not the most recent.
        expect(svc.endTime, 200);
        expect(svc.currentEndTime, 200);
      });

      test(
        'changes are recorded at regressed timestamp without crashing',
        () async {
          // Regression: #50 arrives after #100. The change list is no longer sorted
          // — this is documented current behaviour, not a guarantee of correctness.
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#100
1!
#50
0!
''';
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);

          final all = svc.changesInRange(ref, 0, 200);
          expect(all.length, greaterThanOrEqualTo(2));
          expect(svc.endTime, 100); // max seen before regression
        },
      );
    });

    group('large burst handling', () {
      test('1000 value changes in one chunk are all recorded', () async {
        final body = StringBuffer('#0\n');
        for (var i = 0; i < 1000; i++) {
          body.write('${i.isEven ? '1' : '0'}!\n');
        }
        const header = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
''';
        final vcd = header + body.toString();
        final svc = _service();
        addTearDown(svc.close);

        await svc.startAndWaitForHeader(_toStream(vcd, chunkSize: vcd.length));
        await svc.streamEndedFuture;

        final ref = svc.rootScopes.first.variables.first.signalRef;
        await svc.loadSignal(ref);
        expect(svc.changesInRange(ref, 0, 1), hasLength(1000));
      });

      test(
        'debounce coalesces rapid burst into fewer onDataUpdated events',
        () async {
          const debounce = Duration(milliseconds: 200);
          final svc = StreamingVcdService(updateInterval: debounce);
          addTearDown(svc.close);

          var updateCount = 0;
          svc.onDataUpdated.listen((_) => updateCount++);

          final ctrl = StreamController<List<int>>();
          svc.startFromStream(ctrl.stream);
          ctrl.add(utf8.encode(_simpleVcd));
          await svc.headerParsedFuture;

          for (var i = 1; i <= 30; i++) {
            ctrl.add(
              utf8.encode('#${1000 + i * 10}\n${i.isEven ? '1' : '0'}!\n'),
            );
          }
          await ctrl.close();
          await svc.streamEndedFuture;

          await Future<void>.delayed(
            debounce + const Duration(milliseconds: 50),
          );

          // 30 rapid changes should be coalesced into far fewer events.
          expect(updateCount, lessThan(30));
        },
      );
    });

    group('real-valued signals', () {
      test(
        r'r prefix records value and isReal is true for $var real',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var real 1 ^ voltage $end
$upscope $end
$enddefinitions $end
$dumpvars
r3.14 ^
$end
#100
r2.71 ^
''';
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final v = svc.rootScopes.first.variables.first;
          expect(v.isReal, isTrue);
          await svc.loadSignal(v.signalRef);
          expect(svc.valueAt(v.signalRef, 0), '3.14');
          expect(svc.valueAt(v.signalRef, 100), '2.71');
        },
      );

      test(
        'uppercase R prefix is treated identically to lowercase r',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var real 1 ^ v $end
$upscope $end
$enddefinitions $end
#0
R1.5 ^
''';
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          expect(svc.valueAt(ref, 0), '1.5');
        },
      );
    });

    group('scope types and var types', () {
      test(
        'task, function, begin, fork scope types are parsed correctly',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope task myTask $end
$var wire 1 ! a $end
$upscope $end
$scope function myFn $end
$var wire 1 @ b $end
$upscope $end
$scope begin myBegin $end
$var wire 1 # c $end
$upscope $end
$scope fork myFork $end
$var wire 1 % d $end
$upscope $end
$enddefinitions $end
''';
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));

          expect(svc.rootScopes, hasLength(4));
          expect(
            svc.rootScopes.map((s) => s.type),
            containsAll([
              ScopeType.task,
              ScopeType.function,
              ScopeType.begin,
              ScopeType.fork,
            ]),
          );
        },
      );

      test(
        'real, event, and parameter var types are parsed correctly',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var real 1 ! v $end
$var event 1 @ e $end
$var parameter 8 # p $end
$upscope $end
$enddefinitions $end
''';
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));

          final vars = svc.rootScopes.first.variables;
          expect(vars, hasLength(3));
          expect(vars.firstWhere((v) => v.name == 'v').varType, VarType.real);
          expect(vars.firstWhere((v) => v.name == 'e').varType, VarType.event);
          expect(
            vars.firstWhere((v) => v.name == 'p').varType,
            VarType.parameter,
          );
        },
      );
    });

    group('post-header signal declarations', () {
      test(
        r'$var after $enddefinitions is not added to the variable hierarchy',
        () async {
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#10
1!
$var wire 1 " late_sig $end
#20
0!
''';
          // The late $var declaration appears in the value section; the service must
          // ignore it without crashing.
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          // Only the original declaration should be visible.
          expect(svc.findVariables(const SignalFilter()), hasLength(1));
          expect(svc.rootScopes.first.variables.first.name, 'clk');
        },
      );

      test(
        'value changes for idcodes not in the header are stored without crash',
        () async {
          // Some simulators emit $dumpvars with additional idcodes that were never
          // in the $var declarations (edge case in real-world VCDs).
          const vcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
bxxxxxxxx ~
$end
#10
1!
''';
          final svc = _service();
          addTearDown(svc.close);
          await svc.startAndWaitForHeader(_toStream(vcd));
          await svc.streamEndedFuture;

          final ref = svc.rootScopes.first.variables.first.signalRef;
          await svc.loadSignal(ref);
          expect(svc.valueAt(ref, 10), '1');
          // The undeclared idcode '~' must not appear in the variable list.
          expect(svc.findVariables(const SignalFilter()), hasLength(1));
        },
      );
    });
  });
}
