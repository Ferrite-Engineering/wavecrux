// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

// ── Mocks & fakes ─────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

// ── Fixture helpers ───────────────────────────────────────────────────────────

Variable _v(String name, String ref, {int bitWidth = 2}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top',
  bitWidth: bitWidth,
);

Scope _scopeWith(List<Variable> vars) => Scope(
  name: 'top',
  type: ScopeType.module,
  path: 'top',
  variables: vars,
);

void _stub(
  _MockSource ds,
  String ref,
  String? initValue,
  List<SignalChange> changes,
) {
  when(() => ds.valueAt(ref, any())).thenAnswer((inv) {
    final t = inv.positionalArguments[1] as int;
    var current = initValue;
    for (final c in changes) {
      if (c.time <= t) current = c.value;
    }
    return current;
  });
  when(() => ds.changesInRange(ref, any(), any())).thenAnswer((inv) {
    final start = inv.positionalArguments[1] as int;
    final end = inv.positionalArguments[2] as int;
    return changes.where((c) => c.time >= start && c.time < end).toList();
  });
  when(() => ds.isSignalLoaded(ref)).thenReturn(true);
  when(() => ds.loadSignal(ref)).thenAnswer((_) async {});
}

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
  group('FsmViewState', () {
    test('default is idle', () {
      const s = FsmViewState();
      expect(s.isActive, isFalse);
      expect(s.signalRef, isNull);
      expect(s.model, isNull);
      expect(s.layout, isNull);
      expect(s.error, isNull);
    });

    test('copyWith updates fields', () {
      const s = FsmViewState();
      final updated = s.copyWith(signalRef: 'r', error: 'oops');
      expect(updated.signalRef, 'r');
      expect(updated.error, 'oops');
    });

    test('copyWith clearAll resets to default', () {
      const s = FsmViewState(signalRef: 'r', error: 'oops');
      final reset = s.copyWith(clearAll: true);
      expect(reset.signalRef, isNull);
      expect(reset.error, isNull);
    });

    test('equality is structural', () {
      const a = FsmViewState(signalRef: 'r');
      const b = FsmViewState(signalRef: 'r');
      const c = FsmViewState(signalRef: 'q');
      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('FsmAnnotationNotifier', () {
    test('starts empty', () {
      final c = _container();
      expect(c.read(fsmAnnotationProvider), isEmpty);
    });

    test('setAnnotation stores by signalRef', () {
      final c = _container();
      c
          .read(fsmAnnotationProvider.notifier)
          .setAnnotation(
            'r',
            const FsmAnnotation(
              signalRef: 'r',
              stateLabels: {'0': 'IDLE'},
            ),
          );
      final state = c.read(fsmAnnotationProvider);
      expect(state['r']?.labelFor('0'), 'IDLE');
    });

    test('setStateLabel preserves prior labels', () {
      final c = _container();
      c.read(fsmAnnotationProvider.notifier)
        ..setStateLabel('r', '0', 'IDLE')
        ..setStateLabel('r', '1', 'RUN');
      final ann = c.read(fsmAnnotationProvider)['r']!;
      expect(ann.stateLabels, {'0': 'IDLE', '1': 'RUN'});
    });

    test('setStateLabel with empty string removes the entry', () {
      final c = _container();
      c.read(fsmAnnotationProvider.notifier)
        ..setStateLabel('r', '0', 'IDLE')
        ..setStateLabel('r', '0', '');
      // The annotation map for r should be removed entirely (no remaining
      // labels).
      expect(c.read(fsmAnnotationProvider)['r'], isNull);
    });

    test('removeAnnotation deletes the entry', () {
      final c = _container();
      c.read(fsmAnnotationProvider.notifier)
        ..setAnnotation(
          'r',
          const FsmAnnotation(signalRef: 'r', stateLabels: {'0': 'IDLE'}),
        )
        ..removeAnnotation('r');
      expect(c.read(fsmAnnotationProvider)['r'], isNull);
    });

    test('clearAll empties the map', () {
      final c = _container();
      c.read(fsmAnnotationProvider.notifier)
        ..setAnnotation(
          'r',
          const FsmAnnotation(signalRef: 'r', stateLabels: {'0': 'A'}),
        )
        ..clearAll();
      expect(c.read(fsmAnnotationProvider), isEmpty);
    });

    test('getAnnotation returns the stored annotation or null', () {
      final c = _container();
      final n = c.read(fsmAnnotationProvider.notifier);
      expect(n.getAnnotation('r'), isNull);
      n.setAnnotation(
        'r',
        const FsmAnnotation(signalRef: 'r', stateLabels: {'0': 'X'}),
      );
      expect(n.getAnnotation('r')?.labelFor('0'), 'X');
    });

    test(
      'restoreFromSession replaces the map with the persisted annotations',
      () {
        final c = _container();
        c.read(fsmAnnotationProvider.notifier)
          // Pre-existing annotation that restore must REPLACE (not merge).
          ..setAnnotation(
            'stale',
            const FsmAnnotation(signalRef: 'stale', stateLabels: {'0': 'OLD'}),
          )
          ..restoreFromSession(const {
            'top.fsm.state': FsmAnnotation(
              signalRef: 'top.fsm.state',
              stateLabels: {'0': 'IDLE', '1': 'RUN'},
            ),
          });
        final state = c.read(fsmAnnotationProvider);
        expect(state.keys, ['top.fsm.state']);
        expect(state['top.fsm.state']!.stateLabels['1'], 'RUN');
        expect(state.containsKey('stale'), isFalse);
      },
    );

    test('restoreFromSession with an empty map clears all annotations', () {
      final c = _container();
      c.read(fsmAnnotationProvider.notifier)
        ..setAnnotation(
          'r',
          const FsmAnnotation(signalRef: 'r', stateLabels: {'0': 'A'}),
        )
        ..restoreFromSession(const {});
      expect(c.read(fsmAnnotationProvider), isEmpty);
    });
  });

  group('FsmNotifier.analyzeSignal', () {
    test('produces a model and layout for a two-state signal', () async {
      final ds = _MockSource();
      _stub(ds, 'r', '00', const [
        SignalChange(time: 10, value: '01'),
        SignalChange(time: 20, value: '00'),
      ]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.endTime).thenReturn(100);
      when(() => ds.rootScopes).thenReturn([
        _scopeWith([_v('s', 'r')]),
      ]);

      final c = _container(source: ds);
      await c.read(fsmProvider.notifier).analyzeSignal('r');

      final state = c.read(fsmProvider);
      expect(state.isActive, isTrue);
      expect(state.error, isNull);
      expect(state.model!.states.length, 2);
      expect(state.layout!.positions.length, 2);
    });

    test('flags noWaveform when no source loaded', () async {
      final c = _container();
      await c.read(fsmProvider.notifier).analyzeSignal('r');
      final state = c.read(fsmProvider);
      expect(state.isActive, isFalse);
      // Guidance for "no waveform" is a typed flag (panel renders a localized
      // message), not a hard-coded English string in `error`.
      expect(state.noWaveform, isTrue);
      expect(state.error, isNull);
    });

    test('clearFsm resets state', () async {
      final ds = _MockSource();
      _stub(ds, 'r', '00', const [SignalChange(time: 10, value: '01')]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.endTime).thenReturn(100);
      when(() => ds.rootScopes).thenReturn([
        _scopeWith([_v('s', 'r')]),
      ]);

      final c = _container(source: ds);
      await c.read(fsmProvider.notifier).analyzeSignal('r');
      expect(c.read(fsmProvider).isActive, isTrue);
      c.read(fsmProvider.notifier).clearFsm();
      expect(c.read(fsmProvider).isActive, isFalse);
    });

    test('jumpToFirstOccurrence moves the primary cursor', () async {
      final ds = _MockSource();
      _stub(ds, 'r', '00', const [
        SignalChange(time: 50, value: '01'),
      ]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.endTime).thenReturn(100);
      when(() => ds.rootScopes).thenReturn([
        _scopeWith([_v('s', 'r')]),
      ]);

      final c = _container(source: ds);
      await c.read(fsmProvider.notifier).analyzeSignal('r');

      final ok = c.read(fsmProvider.notifier).jumpToFirstOccurrence('1');
      expect(ok, isTrue);
      expect(
        c.read(cursorStateProvider).primaryCursorTime,
        50,
      );
    });

    test('jumpToFirstOccurrence returns false for unknown state', () async {
      final ds = _MockSource();
      _stub(ds, 'r', '00', const []);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.endTime).thenReturn(100);
      when(() => ds.rootScopes).thenReturn([
        _scopeWith([_v('s', 'r')]),
      ]);

      final c = _container(source: ds);
      await c.read(fsmProvider.notifier).analyzeSignal('r');
      final ok = c.read(fsmProvider.notifier).jumpToFirstOccurrence('99');
      expect(ok, isFalse);
    });

    test('refresh re-runs analysis (picks up new annotation)', () async {
      final ds = _MockSource();
      _stub(ds, 'r', '00', const [
        SignalChange(time: 10, value: '01'),
      ]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.endTime).thenReturn(100);
      when(() => ds.rootScopes).thenReturn([
        _scopeWith([_v('s', 'r')]),
      ]);

      final c = _container(source: ds);
      await c.read(fsmProvider.notifier).analyzeSignal('r');
      // Original labels are raw numbers.
      expect(c.read(fsmProvider).model!.stateById('0')!.label, '0');

      // Now annotate and refresh.
      c
          .read(fsmAnnotationProvider.notifier)
          .setAnnotation(
            'r',
            const FsmAnnotation(
              signalRef: 'r',
              stateLabels: {'0': 'IDLE', '1': 'RUN'},
            ),
          );
      await c.read(fsmProvider.notifier).refresh();
      final m = c.read(fsmProvider).model!;
      expect(m.stateById('0')!.label, 'IDLE');
      expect(m.stateById('1')!.label, 'RUN');
    });

    test('refresh is a no-op when no FSM is active', () async {
      final c = _container();
      await c.read(fsmProvider.notifier).refresh();
      expect(c.read(fsmProvider).isActive, isFalse);
    });
  });

  group('fsmCurrentStateIdProvider', () {
    test('returns null when no FSM active', () {
      final c = _container();
      expect(c.read(fsmCurrentStateIdProvider), isNull);
    });

    test('returns the state id at the cursor when FSM is active', () async {
      final ds = _MockSource();
      _stub(ds, 'r', '00', const [
        SignalChange(time: 10, value: '01'),
        SignalChange(time: 20, value: '10'),
      ]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.endTime).thenReturn(100);
      when(() => ds.rootScopes).thenReturn([
        _scopeWith([_v('s', 'r')]),
      ]);

      final c = _container(source: ds);
      await c.read(fsmProvider.notifier).analyzeSignal('r');

      // Place cursor at t=15 → value is '01' = state '1'.
      c.read(cursorStateProvider.notifier).placePrimary(15);
      expect(c.read(fsmCurrentStateIdProvider), '1');

      // Move to t=25 → value is '10' = state '2'.
      c.read(cursorStateProvider.notifier).placePrimary(25);
      expect(c.read(fsmCurrentStateIdProvider), '2');
    });
  });

  group('fsmRecentTransitionProvider', () {
    test('returns null when no FSM is active', () {
      final c = _container();
      expect(c.read(fsmRecentTransitionProvider), isNull);
    });

    test('returns the most recent transition before/at the cursor', () async {
      final ds = _MockSource();
      _stub(ds, 'r', '00', const [
        SignalChange(time: 10, value: '01'),
        SignalChange(time: 20, value: '10'),
        SignalChange(time: 30, value: '00'),
      ]);
      when(() => ds.startTime).thenReturn(0);
      when(() => ds.endTime).thenReturn(100);
      when(() => ds.rootScopes).thenReturn([
        _scopeWith([_v('s', 'r')]),
      ]);

      final c = _container(source: ds);
      await c.read(fsmProvider.notifier).analyzeSignal('r');

      // Cursor at 25 → most recent transition is 1→2 at t=20.
      c.read(cursorStateProvider.notifier).placePrimary(25);
      final t = c.read(fsmRecentTransitionProvider)!;
      expect(t.fromId, '1');
      expect(t.toId, '2');
    });
  });
}
