// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/services/signal_query/x_trace_service.dart';

// ── Fakes & mocks ─────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

// ── Fixture helpers ───────────────────────────────────────────────────────────

Variable _variable(
  String name,
  String ref,
  String scopePath, {
  int bitWidth = 1,
}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: scopePath,
  bitWidth: bitWidth,
);

Scope _scope(String name, String path, List<Variable> variables) => Scope(
  name: name,
  type: ScopeType.module,
  path: path,
  variables: variables,
);

// Container with a mock source injected via the WaveformSourceNotifier override.
// The signalVariablesMap and hierarchy providers derive automatically from the
// mock source's rootScopes, so no extra overrides are needed.
ProviderContainer _container({WaveformDataSource? source}) {
  final c = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(
        () => _FakeSourceNotifier(source),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  // ── XTraceState unit tests ──────────────────────────────────────────────────

  group('XTraceState', () {
    test('default state is idle', () {
      const s = XTraceState();
      expect(s.isActive, isFalse);
      expect(s.rootNode, isNull);
      expect(s.involvedSignalPaths, isEmpty);
      expect(s.error, isNull);
    });

    test('isActive when rootNode is set', () {
      const node = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      const s = XTraceState(rootNode: node);
      expect(s.isActive, isTrue);
    });

    test('copyWith preserves unspecified fields', () {
      const node = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      const s = XTraceState(
        rootNode: node,
        involvedSignalPaths: {'top.s'},
      );
      final copy = s.copyWith(error: XTraceFailure.notXAtTime);
      expect(copy.rootNode, node);
      expect(copy.involvedSignalPaths, {'top.s'});
      expect(copy.error, XTraceFailure.notXAtTime);
    });

    test('copyWith clearRoot removes rootNode', () {
      const node = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      const s = XTraceState(rootNode: node);
      final cleared = s.copyWith(clearRoot: true);
      expect(cleared.rootNode, isNull);
      expect(cleared.isActive, isFalse);
    });

    test('copyWith clearError removes error', () {
      const s = XTraceState(error: XTraceFailure.notXAtTime);
      final cleared = s.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });

    test('equality holds for same fields', () {
      const a = XTraceState(error: XTraceFailure.notXAtTime);
      const b = XTraceState(error: XTraceFailure.notXAtTime);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when rootNode differs', () {
      const node = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      const a = XTraceState(rootNode: node);
      const b = XTraceState();
      expect(a, isNot(equals(b)));
    });

    test('inequality when error differs', () {
      const a = XTraceState(error: XTraceFailure.notXAtTime);
      const b = XTraceState(error: XTraceFailure.signalNotFound);
      expect(a, isNot(equals(b)));
    });

    test('hasContent is true for a chain or a failure, false when idle', () {
      const node = XCausalNode(
        signalPath: 'top.s',
        signalRef: 'ref',
        xStartTime: 100,
      );
      expect(const XTraceState().hasContent, isFalse);
      expect(const XTraceState(rootNode: node).hasContent, isTrue);
      const refused = XTraceState(error: XTraceFailure.notXAtTime);
      expect(refused.hasContent, isTrue);
      expect(refused.isActive, isFalse);
    });

    test('toString contains active status', () {
      const s = XTraceState();
      expect(s.toString(), contains('active: false'));
    });
  });

  // ── XTraceNotifier — basic state management ────────────────────────────────

  group('XTraceNotifier', () {
    ProviderContainer makeContainer() => ProviderContainer();

    test('initial state is idle', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final state = container.read(xTraceProvider);
      expect(state.isActive, isFalse);
    });

    test('clearTrace resets state to idle', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(xTraceProvider.notifier).clearTrace();

      final state = container.read(xTraceProvider);
      expect(state, equals(const XTraceState()));
    });

    test('traceX on missing waveform source sets no state', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(xTraceProvider.notifier).traceX('top.clk', 500);

      final state = container.read(xTraceProvider);
      expect(state.isActive, isFalse);
      expect(state.error, isNull);
    });

    test('clearTrace after hypothetical active state resets to default', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(xTraceProvider.notifier)
        ..clearTrace()
        ..clearTrace();

      expect(container.read(xTraceProvider), const XTraceState());
    });

    test('provider is keepAlive — survives container read cycles', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier1 = container.read(xTraceProvider.notifier);
      final notifier2 = container.read(xTraceProvider.notifier);
      expect(identical(notifier1, notifier2), isTrue);
    });
  });

  // ── XTraceNotifier — traceX with mock waveform source ─────────────────────

  group('XTraceNotifier.traceX — initiating a trace', () {
    test('traceX calls source with the correct signal ref', () async {
      final src = _MockSource();
      final variable = _variable('status', 'ref_status', 'top.cpu');
      final scope = _scope('cpu', 'top.cpu', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_status')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      when(() => src.endTime).thenReturn(1000);
      // Signal is X at t=500.
      when(() => src.valueAt('ref_status', 500)).thenReturn('x');
      // History: was '0' at t=100, became 'x' at t=200.
      when(() => src.changesInRange('ref_status', 0, 501)).thenReturn([
        const SignalChange(time: 100, value: '0'),
        const SignalChange(time: 200, value: 'x'),
      ]);
      // No additional valueAt calls needed for origin computation above startTime.

      final c = _container(source: src);
      await c.read(xTraceProvider.notifier).traceX('ref_status', 500);

      // Verify valueAt was called with the exact ref (called by both the
      // provider guard and XTraceService.findXOrigin).
      verify(
        () => src.valueAt('ref_status', 500),
      ).called(greaterThanOrEqualTo(1));
      // Verify changesInRange was called to trace the X history.
      verify(() => src.changesInRange('ref_status', 0, 501)).called(1);
    });

    test(
      'traceX when signalRef is absent from variables map reports it',
      () async {
        final src = _MockSource();
        // Scope has no variables — so the variables map will be empty.
        when(() => src.rootScopes).thenReturn([]);

        final c = _container(source: src);
        await c.read(xTraceProvider.notifier).traceX('missing_ref', 500);

        final state = c.read(xTraceProvider);
        expect(state.isActive, isFalse);
        expect(state.error, XTraceFailure.signalNotFound);
      },
    );

    test('traceX loads signal data when it is not already loaded', () async {
      final src = _MockSource();
      final variable = _variable('clk', 'ref_clk', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      // Signal is NOT loaded yet.
      when(() => src.isSignalLoaded('ref_clk')).thenReturn(false);
      when(() => src.loadSignal('ref_clk')).thenAnswer((_) async {});
      when(() => src.startTime).thenReturn(0);
      when(() => src.valueAt('ref_clk', 300)).thenReturn('x');
      when(
        () => src.changesInRange('ref_clk', 0, 301),
      ).thenReturn([const SignalChange(time: 300, value: 'x')]);

      final c = _container(source: src);
      await c.read(xTraceProvider.notifier).traceX('ref_clk', 300);

      verify(() => src.loadSignal('ref_clk')).called(1);
    });
  });

  // ── XTraceNotifier.traceX — result state ──────────────────────────────────

  group('XTraceNotifier.traceX — displaying trace results', () {
    test(
      'successful trace populates rootNode with correct signalPath and ref',
      () async {
        final src = _MockSource();
        final variable = _variable('status', 'ref_status', 'top.cpu');
        final scope = _scope('cpu', 'top.cpu', [variable]);

        when(() => src.rootScopes).thenReturn([scope]);
        when(() => src.isSignalLoaded('ref_status')).thenReturn(true);
        when(() => src.startTime).thenReturn(0);
        when(() => src.valueAt('ref_status', 500)).thenReturn('x');
        when(() => src.changesInRange('ref_status', 0, 501)).thenReturn([
          const SignalChange(time: 100, value: '0'),
          const SignalChange(time: 200, value: 'x'),
        ]);

        final c = _container(source: src);
        await c.read(xTraceProvider.notifier).traceX('ref_status', 500);

        final state = c.read(xTraceProvider);
        expect(state.isActive, isTrue);
        expect(state.error, isNull);
        expect(state.rootNode!.signalRef, 'ref_status');
        expect(state.rootNode!.signalPath, 'top.cpu.status');
      },
    );

    test(
      'rootNode xStartTime is the first tick the signal entered X',
      () async {
        final src = _MockSource();
        final variable = _variable('data', 'ref_data', 'top');
        final scope = _scope('top', 'top', [variable]);

        when(() => src.rootScopes).thenReturn([scope]);
        when(() => src.isSignalLoaded('ref_data')).thenReturn(true);
        when(() => src.startTime).thenReturn(0);
        when(() => src.valueAt('ref_data', 800)).thenReturn('x');
        // Was '1' at t=300, became 'x' at t=400.
        when(() => src.changesInRange('ref_data', 0, 801)).thenReturn([
          const SignalChange(time: 300, value: '1'),
          const SignalChange(time: 400, value: 'x'),
        ]);

        final c = _container(source: src);
        await c.read(xTraceProvider.notifier).traceX('ref_data', 800);

        final state = c.read(xTraceProvider);
        expect(state.rootNode!.xStartTime, 400);
        expect(state.rootNode!.previousValue, '1');
      },
    );

    test(
      'rootNode xStartTime is startTime when signal is X from simulation start',
      () async {
        final src = _MockSource();
        final variable = _variable('q', 'ref_q', 'top');
        final scope = _scope('top', 'top', [variable]);

        when(() => src.rootScopes).thenReturn([scope]);
        when(() => src.isSignalLoaded('ref_q')).thenReturn(true);
        when(() => src.startTime).thenReturn(0);
        // X from the very first recorded change.
        when(() => src.valueAt('ref_q', 600)).thenReturn('x');
        when(() => src.changesInRange('ref_q', 0, 601)).thenReturn([
          const SignalChange(time: 0, value: 'x'),
          const SignalChange(time: 100, value: 'x'),
        ]);

        final c = _container(source: src);
        await c.read(xTraceProvider.notifier).traceX('ref_q', 600);

        final state = c.read(xTraceProvider);
        expect(state.rootNode!.xStartTime, 0);
        expect(state.rootNode!.previousValue, isNull);
      },
    );

    test('involved signal paths includes root signal path', () async {
      final src = _MockSource();
      final variable = _variable('out', 'ref_out', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_out')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      when(() => src.valueAt('ref_out', 200)).thenReturn('x');
      when(() => src.changesInRange('ref_out', 0, 201)).thenReturn([
        const SignalChange(time: 200, value: 'x'),
      ]);

      final c = _container(source: src);
      await c.read(xTraceProvider.notifier).traceX('ref_out', 200);

      final state = c.read(xTraceProvider);
      expect(state.involvedSignalPaths, contains('top.out'));
    });

    test(
      'involved paths includes sibling signals that are also X at xStartTime',
      () async {
        final src = _MockSource();
        final varA = _variable('sigA', 'ref_a', 'top.dut');
        final varB = _variable('sigB', 'ref_b', 'top.dut');
        final scope = _scope('dut', 'top.dut', [varA, varB]);

        when(() => src.rootScopes).thenReturn([scope]);
        when(() => src.isSignalLoaded('ref_a')).thenReturn(true);
        when(() => src.isSignalLoaded('ref_b')).thenReturn(true);
        when(() => src.startTime).thenReturn(0);
        // sigA is X at t=700.
        when(() => src.valueAt('ref_a', 700)).thenReturn('x');
        when(() => src.changesInRange('ref_a', 0, 701)).thenReturn([
          const SignalChange(time: 500, value: '1'),
          const SignalChange(time: 600, value: 'x'),
        ]);
        // sigB is also X at the xStartTime=600 of sigA.
        when(() => src.valueAt('ref_b', 600)).thenReturn('x');
        when(() => src.changesInRange('ref_b', 0, 601)).thenReturn([
          const SignalChange(time: 600, value: 'x'),
        ]);

        final c = _container(source: src);
        await c.read(xTraceProvider.notifier).traceX('ref_a', 700);

        final state = c.read(xTraceProvider);
        expect(
          state.involvedSignalPaths,
          containsAll(['top.dut.sigA', 'top.dut.sigB']),
        );
        expect(state.rootNode!.children, hasLength(1));
        expect(state.rootNode!.children.first.signalRef, 'ref_b');
      },
    );

    test('sibling not X at xStartTime is excluded from children', () async {
      final src = _MockSource();
      final varA = _variable('sigA', 'ref_a', 'top.dut');
      final varC = _variable('sigC', 'ref_c', 'top.dut');
      final scope = _scope('dut', 'top.dut', [varA, varC]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_a')).thenReturn(true);
      when(() => src.isSignalLoaded('ref_c')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      when(() => src.valueAt('ref_a', 400)).thenReturn('x');
      when(() => src.changesInRange('ref_a', 0, 401)).thenReturn([
        const SignalChange(time: 300, value: 'x'),
      ]);
      // sigC is '1' (not X) at xStartTime=300.
      when(() => src.valueAt('ref_c', 300)).thenReturn('1');

      final c = _container(source: src);
      await c.read(xTraceProvider.notifier).traceX('ref_a', 400);

      final state = c.read(xTraceProvider);
      expect(state.rootNode!.children, isEmpty);
      expect(state.involvedSignalPaths, isNot(contains('top.dut.sigC')));
    });

    test('primary cursor moves to xStartTime after successful trace', () async {
      final src = _MockSource();
      final variable = _variable('sig', 'ref_sig', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_sig')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      when(() => src.endTime).thenReturn(2000);
      when(() => src.valueAt('ref_sig', 1000)).thenReturn('x');
      when(() => src.changesInRange('ref_sig', 0, 1001)).thenReturn([
        const SignalChange(time: 750, value: '0'),
        const SignalChange(time: 800, value: 'x'),
      ]);

      final c = _container(source: src);
      // Initialize the time mapper so navigation works.
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 2000,
            viewportWidth: 1000,
          );

      await c.read(xTraceProvider.notifier).traceX('ref_sig', 1000);

      final cursorState = c.read(cursorStateProvider);
      expect(cursorState.primaryCursorTime, 800);
    });
  });

  // ── XTraceNotifier.traceX — error handling ─────────────────────────────────

  group('XTraceNotifier.traceX — error handling', () {
    test('sets error when signal is not X at the requested time', () async {
      final src = _MockSource();
      final variable = _variable('good', 'ref_good', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_good')).thenReturn(true);
      // Signal is '1', not X.
      when(() => src.valueAt('ref_good', 500)).thenReturn('1');

      final c = _container(source: src);
      await c.read(xTraceProvider.notifier).traceX('ref_good', 500);

      final state = c.read(xTraceProvider);
      expect(state.isActive, isFalse);
      expect(state.error, XTraceFailure.notXAtTime);
    });

    test(
      'sets error when signal value is null at the requested time',
      () async {
        final src = _MockSource();
        final variable = _variable('undriven', 'ref_ud', 'top');
        final scope = _scope('top', 'top', [variable]);

        when(() => src.rootScopes).thenReturn([scope]);
        when(() => src.isSignalLoaded('ref_ud')).thenReturn(true);
        // valueAt returns null (no recorded value before this time).
        when(() => src.valueAt('ref_ud', 100)).thenReturn(null);

        final c = _container(source: src);
        await c.read(xTraceProvider.notifier).traceX('ref_ud', 100);

        final state = c.read(xTraceProvider);
        expect(state.isActive, isFalse);
        expect(state.error, isNotNull);
      },
    );

    test('error state does not contain a rootNode', () async {
      final src = _MockSource();
      final variable = _variable('sig', 'ref_e', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_e')).thenReturn(true);
      when(() => src.valueAt('ref_e', 50)).thenReturn('0');

      final c = _container(source: src);
      await c.read(xTraceProvider.notifier).traceX('ref_e', 50);

      final state = c.read(xTraceProvider);
      expect(state.rootNode, isNull);
      expect(state.involvedSignalPaths, isEmpty);
    });

    test('second traceX after error overwrites the previous error', () async {
      final src = _MockSource();
      final variable = _variable('s', 'ref_s', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_s')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      // First call: not X.
      when(() => src.valueAt('ref_s', 100)).thenReturn('0');
      // Second call: X.
      when(() => src.valueAt('ref_s', 200)).thenReturn('x');
      when(
        () => src.changesInRange('ref_s', 0, 201),
      ).thenReturn([const SignalChange(time: 200, value: 'x')]);
      when(() => src.endTime).thenReturn(1000);

      final c = _container(source: src);
      final notifier = c.read(xTraceProvider.notifier);
      await notifier.traceX('ref_s', 100);
      expect(c.read(xTraceProvider).error, isNotNull);

      c
          .read(timeMapperProvider.notifier)
          .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);

      await notifier.traceX('ref_s', 200);
      final state = c.read(xTraceProvider);
      expect(state.isActive, isTrue);
      expect(state.error, isNull);
    });
  });

  // ── XTraceNotifier — clearing the trace ───────────────────────────────────

  group('XTraceNotifier.clearTrace', () {
    test('clearTrace from idle is a no-op (stays idle)', () {
      final c = _container();
      c.read(xTraceProvider.notifier).clearTrace();
      expect(c.read(xTraceProvider), const XTraceState());
    });

    test('clearTrace after error resets error field', () async {
      final src = _MockSource();
      final variable = _variable('n', 'ref_n', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_n')).thenReturn(true);
      when(() => src.valueAt('ref_n', 10)).thenReturn('1');

      final c = _container(source: src);
      await c.read(xTraceProvider.notifier).traceX('ref_n', 10);
      expect(c.read(xTraceProvider).error, isNotNull);

      c.read(xTraceProvider.notifier).clearTrace();
      expect(c.read(xTraceProvider), const XTraceState());
    });

    test('clearTrace after successful trace resets all fields', () async {
      final src = _MockSource();
      final variable = _variable('sig', 'ref_ct', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_ct')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      when(() => src.endTime).thenReturn(1000);
      when(() => src.valueAt('ref_ct', 500)).thenReturn('x');
      when(
        () => src.changesInRange('ref_ct', 0, 501),
      ).thenReturn([const SignalChange(time: 500, value: 'x')]);

      final c = _container(source: src);
      c
          .read(timeMapperProvider.notifier)
          .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);

      await c.read(xTraceProvider.notifier).traceX('ref_ct', 500);
      expect(c.read(xTraceProvider).isActive, isTrue);

      c.read(xTraceProvider.notifier).clearTrace();
      final state = c.read(xTraceProvider);
      expect(state.isActive, isFalse);
      expect(state.rootNode, isNull);
      expect(state.involvedSignalPaths, isEmpty);
      expect(state.error, isNull);
    });

    test('clearTrace is idempotent', () {
      final c = _container();
      c.read(xTraceProvider.notifier)
        ..clearTrace()
        ..clearTrace()
        ..clearTrace();
      expect(c.read(xTraceProvider), const XTraceState());
    });
  });

  // ── XTraceNotifier.traceXAndReveal — run, then show the result ─────────────

  group('XTraceNotifier.traceXAndReveal', () {
    _MockSource xSource() {
      final src = _MockSource();
      final variable = _variable('sig', 'ref_rv', 'top');
      when(() => src.rootScopes).thenReturn([
        _scope('top', 'top', [variable]),
      ]);
      when(() => src.isSignalLoaded('ref_rv')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      when(() => src.endTime).thenReturn(1000);
      when(() => src.valueAt('ref_rv', 100)).thenReturn('0');
      when(() => src.valueAt('ref_rv', 500)).thenReturn('x');
      when(
        () => src.changesInRange('ref_rv', 0, 501),
      ).thenReturn([const SignalChange(time: 500, value: 'x')]);
      return src;
    }

    test('a successful trace selects the X-Trace tab and opens the '
        'collapsed bottom dock', () async {
      final c = _container(source: xSource());
      c
          .read(timeMapperProvider.notifier)
          .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);
      c
          .read(panelLayoutProvider.notifier)
          .setTransactionViewVisible(visible: false);

      await c.read(xTraceProvider.notifier).traceXAndReveal('ref_rv', 500);

      expect(c.read(xTraceProvider).isActive, isTrue);
      final layout = c.read(panelLayoutProvider);
      expect(layout.transactionViewVisible, isTrue);
      expect(layout.effectiveBottomDockTab, kBottomDockTabXTrace);
    });

    test('a refused trace is revealed too, so its reason is seen', () async {
      final c = _container(source: xSource());
      c
          .read(panelLayoutProvider.notifier)
          .setTransactionViewVisible(visible: false);

      await c.read(xTraceProvider.notifier).traceXAndReveal('ref_rv', 100);

      expect(c.read(xTraceProvider).error, XTraceFailure.notXAtTime);
      final layout = c.read(panelLayoutProvider);
      expect(layout.transactionViewVisible, isTrue);
      expect(layout.effectiveBottomDockTab, kBottomDockTabXTrace);
    });

    test('a trace with no source leaves the dock alone', () async {
      final c = _container();
      c
          .read(panelLayoutProvider.notifier)
          .setTransactionViewVisible(visible: false);

      await c.read(xTraceProvider.notifier).traceXAndReveal('ref_rv', 500);

      expect(c.read(panelLayoutProvider).transactionViewVisible, isFalse);
    });

    test('a tab dragged to the right dock is revealed there', () async {
      final c = _container(source: xSource());
      c
          .read(timeMapperProvider.notifier)
          .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);
      c.read(panelLayoutProvider.notifier)
        ..moveDockTab(kBottomDockTabXTrace, kDockRegionRight)
        ..setTransactionViewVisible(visible: false);

      await c.read(xTraceProvider.notifier).traceXAndReveal('ref_rv', 500);

      final layout = c.read(panelLayoutProvider);
      expect(layout.rightDockTab, kBottomDockTabXTrace);
      expect(layout.transactionViewVisible, isFalse);
    });
  });

  // ── XTraceNotifier.jumpToNode — navigating the trace chain ────────────────

  group('XTraceNotifier.jumpToNode', () {
    test('jumpToNode moves primary cursor to the node xStartTime', () {
      final c = _container();
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 5000,
            viewportWidth: 1000,
          );

      const node = XCausalNode(
        signalPath: 'top.a',
        signalRef: 'ref_a',
        xStartTime: 1234,
      );
      c.read(xTraceProvider.notifier).jumpToNode(node);

      final cursor = c.read(cursorStateProvider);
      expect(cursor.primaryCursorTime, 1234);
    });

    test('jumpToNode centres the viewport on the node xStartTime', () {
      final c = _container();
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 1000,
          );
      // Zoom in so the visible window is smaller than the full range, giving
      // the navigator room to pan and truly centre on the target time.
      for (var i = 0; i < 4; i++) {
        c
            .read(timeMapperProvider.notifier)
            .zoomIn(focalPixel: 500, factor: 1.5);
      }

      const node = XCausalNode(
        signalPath: 'top.b',
        signalRef: 'ref_b',
        xStartTime: 4000,
      );
      c.read(xTraceProvider.notifier).jumpToNode(node);

      final mapper = c.read(timeMapperProvider);
      final centre = (mapper.visibleStartTime + mapper.visibleEndTime) / 2;
      expect(centre, closeTo(4000, 1.0));
    });

    test('jumpToNode on a child node uses child xStartTime', () {
      final c = _container();
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 5000,
            viewportWidth: 1000,
          );

      const childNode = XCausalNode(
        signalPath: 'top.cpu.child',
        signalRef: 'ref_child',
        xStartTime: 750,
      );
      c.read(xTraceProvider.notifier).jumpToNode(childNode);

      final cursor = c.read(cursorStateProvider);
      expect(cursor.primaryCursorTime, 750);
    });

    test('jumpToNode does not alter the trace state itself', () async {
      final src = _MockSource();
      final variable = _variable('sig', 'ref_jn', 'top');
      final scope = _scope('top', 'top', [variable]);

      when(() => src.rootScopes).thenReturn([scope]);
      when(() => src.isSignalLoaded('ref_jn')).thenReturn(true);
      when(() => src.startTime).thenReturn(0);
      when(() => src.endTime).thenReturn(2000);
      when(() => src.valueAt('ref_jn', 1000)).thenReturn('x');
      when(
        () => src.changesInRange('ref_jn', 0, 1001),
      ).thenReturn([const SignalChange(time: 1000, value: 'x')]);

      final c = _container(source: src);
      c
          .read(timeMapperProvider.notifier)
          .initialize(startTime: 0, endTime: 2000, viewportWidth: 1000);

      await c.read(xTraceProvider.notifier).traceX('ref_jn', 1000);
      final stateBefore = c.read(xTraceProvider);
      expect(stateBefore.isActive, isTrue);

      const siblingNode = XCausalNode(
        signalPath: 'top.other',
        signalRef: 'ref_other',
        xStartTime: 900,
      );
      c.read(xTraceProvider.notifier).jumpToNode(siblingNode);

      final stateAfter = c.read(xTraceProvider);
      expect(stateAfter, equals(stateBefore));
    });
  });

  // ── XTraceNotifier — signal selection interaction ──────────────────────────
  //
  // The SelectedVariablesNotifier tracks which signals are highlighted in the
  // signal tree.  After a successful traceX, the involved signal paths include
  // the root and any co-temporal siblings.  Callers that need to highlight those
  // signals can read `involvedSignalPaths` and call `selectOnly` on
  // `SelectedVariablesNotifier`.  These tests verify the integration path:
  // that `involvedSignalPaths` is correctly populated so consumers can drive
  // signal selection.

  group('XTraceNotifier — involvedSignalPaths for signal selection', () {
    test(
      'involvedSignalPaths contains only root path when no siblings are X',
      () async {
        final src = _MockSource();
        final varA = _variable('alone', 'ref_alone', 'top');
        final scope = _scope('top', 'top', [varA]);

        when(() => src.rootScopes).thenReturn([scope]);
        when(() => src.isSignalLoaded('ref_alone')).thenReturn(true);
        when(() => src.startTime).thenReturn(0);
        when(() => src.endTime).thenReturn(1000);
        when(() => src.valueAt('ref_alone', 500)).thenReturn('x');
        when(() => src.changesInRange('ref_alone', 0, 501)).thenReturn([
          const SignalChange(time: 400, value: 'x'),
        ]);

        final c = _container(source: src);
        c
            .read(timeMapperProvider.notifier)
            .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);

        await c.read(xTraceProvider.notifier).traceX('ref_alone', 500);

        final paths = c.read(xTraceProvider).involvedSignalPaths;
        expect(paths, {'top.alone'});
      },
    );

    test(
      'involvedSignalPaths is empty after clearTrace — consumers deselect signals',
      () async {
        final src = _MockSource();
        final variable = _variable('s', 'ref_s2', 'top');
        final scope = _scope('top', 'top', [variable]);

        when(() => src.rootScopes).thenReturn([scope]);
        when(() => src.isSignalLoaded('ref_s2')).thenReturn(true);
        when(() => src.startTime).thenReturn(0);
        when(() => src.endTime).thenReturn(1000);
        when(() => src.valueAt('ref_s2', 200)).thenReturn('x');
        when(
          () => src.changesInRange('ref_s2', 0, 201),
        ).thenReturn([const SignalChange(time: 200, value: 'x')]);

        final c = _container(source: src);
        c
            .read(timeMapperProvider.notifier)
            .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);

        await c.read(xTraceProvider.notifier).traceX('ref_s2', 200);
        expect(c.read(xTraceProvider).involvedSignalPaths, isNotEmpty);

        c.read(xTraceProvider.notifier).clearTrace();
        expect(
          c.read(xTraceProvider).involvedSignalPaths,
          isEmpty,
        );
      },
    );

    test(
      'involvedSignalPaths reflects all children that a viewer should highlight',
      () async {
        final src = _MockSource();
        final varR = _variable('root', 'ref_r', 'top.mod');
        final varX1 = _variable('xSib1', 'ref_x1', 'top.mod');
        final varX2 = _variable('xSib2', 'ref_x2', 'top.mod');
        final scope = _scope('mod', 'top.mod', [varR, varX1, varX2]);

        when(() => src.rootScopes).thenReturn([scope]);
        for (final ref in ['ref_r', 'ref_x1', 'ref_x2']) {
          when(() => src.isSignalLoaded(ref)).thenReturn(true);
        }
        when(() => src.startTime).thenReturn(0);
        when(() => src.endTime).thenReturn(2000);

        when(() => src.valueAt('ref_r', 1000)).thenReturn('x');
        when(() => src.changesInRange('ref_r', 0, 1001)).thenReturn([
          const SignalChange(time: 900, value: '0'),
          const SignalChange(time: 950, value: 'x'),
        ]);
        // Both siblings are X at xStartTime=950.
        when(() => src.valueAt('ref_x1', 950)).thenReturn('x');
        when(
          () => src.changesInRange('ref_x1', 0, 951),
        ).thenReturn([const SignalChange(time: 950, value: 'x')]);
        when(() => src.valueAt('ref_x2', 950)).thenReturn('x');
        when(
          () => src.changesInRange('ref_x2', 0, 951),
        ).thenReturn([const SignalChange(time: 950, value: 'x')]);

        final c = _container(source: src);
        c
            .read(timeMapperProvider.notifier)
            .initialize(startTime: 0, endTime: 2000, viewportWidth: 1000);

        await c.read(xTraceProvider.notifier).traceX('ref_r', 1000);

        final paths = c.read(xTraceProvider).involvedSignalPaths;
        expect(
          paths,
          containsAll(['top.mod.root', 'top.mod.xSib1', 'top.mod.xSib2']),
        );
      },
    );
  });
}
