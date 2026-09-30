// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/diff_result.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../../helpers/wellen_ffi_library_gate.dart';

// Relative path used consistently in existing fixture tests.
const _fixturePath = 'test/fixtures/vcd/scalar_basics.vcd';

// ── mocks & fakes ────────────────────────────────────────────────────────────

class _MockDataSource extends Mock implements WaveformDataSource {}

/// Returns a pre-built source without going through the real openFile flow.
/// This sidesteps platform-channel calls (SecurityScopedBookmarkService) that
/// are not available in the unit-test host process.
class _FakeWaveformSourceNotifier extends WaveformSourceNotifier {
  _FakeWaveformSourceNotifier(this._src);
  final WaveformDataSource _src;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_src);
}

/// Subclass that exposes the protected `state` setter so tests can inject
/// arbitrary [DiffState] values without going through the real loading flow.
class _TestableDiffNotifier extends DiffNotifier {
  // Riverpod's Notifier.state setter is @protected; accessing it from a
  // test-only subclass is the standard pattern for injecting known state.
  // ignore: use_setters_to_change_properties
  void forceState(DiffState s) => state = s;
}

// ── builder helpers ──────────────────────────────────────────────────────────

const _clkPath = 'top.clk';
const _rstPath = 'top.rst';

// signalRef is intentionally distinct from fullPath so tests catch any bug
// that passes pathA/pathB to WaveformDataSource instead of signalRefA/B.
Variable _wire(String scopePath, String name, {int bitWidth = 1}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: scopePath,
  bitWidth: bitWidth,
);

const _clkRef = 'ref_clk'; // distinct from _clkPath = 'top.clk'

Scope _module(
  String path,
  List<Variable> vars, [
  List<Scope> children = const [],
]) => Scope(
  name: path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : path,
  type: ScopeType.module,
  path: path,
  variables: vars,
  childScopes: children,
);

/// Mock primary source with a single `top.clk` signal that always reads '1'.
/// Its Variable has signalRef = 'ref_clk' (distinct from fullPath 'top.clk').
/// The secondary WellenProvider (same VCD) will query by the VCD id code for
/// clk, which differs from '1', producing a divergence from startTime to endTime.
_MockDataSource _mockPrimary({int end = 100}) {
  final mock = _MockDataSource();
  final clk = _wire('top', 'clk');
  when(() => mock.rootScopes).thenReturn([
    _module('top', [clk]),
  ]);
  when(() => mock.startTime).thenReturn(0);
  when(() => mock.endTime).thenReturn(end);
  when(() => mock.isSignalLoaded(any())).thenReturn(false);
  when(() => mock.loadSignal(any())).thenAnswer((_) async {});
  // Stub on signalRef ('ref_clk'), not fullPath ('top.clk').
  when(() => mock.valueAt(_clkRef, any())).thenReturn('1');
  when(() => mock.changesInRange(_clkRef, any(), any())).thenReturn(const []);
  return mock;
}

/// Builds a [DiffResult] with a single matched signal that has two separate
/// divergence regions starting at t=10 and t=50.
DiffResult _twoRegionResult() => const DiffResult(
  matchedSignals: [
    SignalMatch(
      pathA: _clkPath,
      pathB: _clkPath,
      isDifferent: true,
      divergenceRegions: [
        TimeRange(start: 10, end: 20),
        TimeRange(start: 50, end: 100),
      ],
    ),
  ],
  unmatchedA: [],
  unmatchedB: [],
);

// ── container factories ──────────────────────────────────────────────────────

/// Plain container; DiffNotifier starts idle.
ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 200, viewportWidth: 1000);
  return c;
}

/// Container with a fake primary source injected via provider override.
/// Uses [_TestableDiffNotifier] so state can be forced in navigation tests.
ProviderContainer _containerWith(WaveformDataSource src) {
  final c = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(
        () => _FakeWaveformSourceNotifier(src),
      ),
      diffProvider.overrideWith(_TestableDiffNotifier.new),
    ],
  );
  addTearDown(c.dispose);
  c
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 200, viewportWidth: 1000);
  return c;
}

/// Container for navigation tests: overrides DiffNotifier with a testable
/// subclass and immediately forces [state] onto it.
ProviderContainer _navContainer(DiffState state) {
  final c = ProviderContainer(
    overrides: [
      diffProvider.overrideWith(_TestableDiffNotifier.new),
    ],
  );
  addTearDown(c.dispose);
  c
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 200, viewportWidth: 1000);
  (c.read(diffProvider.notifier) as _TestableDiffNotifier).forceState(state);
  return c;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // The groups that load a second file open scalar_basics.vcd through the
  // real parser, so they need the wellen FFI library.
  final realTraces = requireWellenFfiLibrary('DiffNotifier on real traces');

  // ── DiffState unit tests ───────────────────────────────────────────────────

  group('DiffState', () {
    test('default state is idle', () {
      const s = DiffState();
      expect(s.isActive, isFalse);
      expect(s.isLoading, isFalse);
      expect(s.error, isNull);
      expect(s.secondFilePath, isNull);
      expect(s.diffResult, isNull);
      expect(s.xorTraces, isEmpty);
      expect(s.divergenceIndex, 0);
    });

    test('isActive when secondFilePath is set', () {
      const s = DiffState(secondFilePath: '/a.vcd');
      expect(s.isActive, isTrue);
    });

    test('allDivergenceTimes empty when no diffResult', () {
      const s = DiffState();
      expect(s.allDivergenceTimes, isEmpty);
    });

    test('totalDivergences is 0 with no diffResult', () {
      const s = DiffState();
      expect(s.totalDivergences, 0);
    });

    test('currentDivergenceTime is null with no diffResult', () {
      const s = DiffState();
      expect(s.currentDivergenceTime, isNull);
    });

    test('allDivergenceRegions empty with no diffResult', () {
      const s = DiffState();
      expect(s.allDivergenceRegions, isEmpty);
    });

    test('copyWith preserves unspecified fields', () {
      const s = DiffState(
        secondFilePath: '/b.vcd',
        divergenceIndex: 2,
        isLoading: true,
      );
      final copy = s.copyWith(error: 'boom');
      expect(copy.secondFilePath, '/b.vcd');
      expect(copy.divergenceIndex, 2);
      expect(copy.isLoading, true);
      expect(copy.error, 'boom');
    });

    test('copyWith overrides specified fields', () {
      const s = DiffState(secondFilePath: '/a.vcd');
      final copy = s.copyWith(divergenceIndex: 5);
      expect(copy.divergenceIndex, 5);
      expect(copy.secondFilePath, '/a.vcd');
    });

    test('states with identical xorTraces content are equal', () {
      const a = DiffState(secondFilePath: '/a.vcd');
      const b = DiffState(secondFilePath: '/a.vcd');
      expect(a, equals(b));
    });

    test('states differing only in xorTraces are not equal', () {
      const a = DiffState(
        secondFilePath: '/a.vcd',
        xorTraces: {
          '!': [SignalChange(time: 0, value: '1')],
        },
      );
      const b = DiffState(secondFilePath: '/a.vcd');
      expect(a, isNot(equals(b)));
    });

    test('inequality when paths differ', () {
      const a = DiffState(secondFilePath: '/a.vcd');
      const b = DiffState(secondFilePath: '/b.vcd');
      expect(a, isNot(equals(b)));
    });

    test('inequality when error differs', () {
      const a = DiffState(error: 'oops');
      const b = DiffState();
      expect(a, isNot(equals(b)));
    });

    test('hashCode stable for equal states', () {
      const a = DiffState(secondFilePath: '/x.vcd', divergenceIndex: 1);
      const b = DiffState(secondFilePath: '/x.vcd', divergenceIndex: 1);
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes path and loading flag', () {
      const s = DiffState(secondFilePath: '/x.vcd', isLoading: true);
      expect(s.toString(), contains('/x.vcd'));
      expect(s.toString(), contains('true'));
    });
  });

  // ── DiffState.allDivergenceTimes with real DiffResult ─────────────────────
  // Covers lines 61-87 (computed properties on DiffState with a non-null
  // diffResult).

  group('DiffState — computed properties with DiffResult', () {
    test('allDivergenceTimes collects start times from matched signals', () {
      const result = DiffResult(
        matchedSignals: [
          SignalMatch(
            pathA: _clkPath,
            pathB: _clkPath,
            isDifferent: true,
            divergenceRegions: [
              TimeRange(start: 10, end: 20),
              TimeRange(start: 40, end: 60),
            ],
          ),
        ],
        unmatchedA: [],
        unmatchedB: [],
      );
      const s = DiffState(diffResult: result);
      expect(s.allDivergenceTimes, containsAll([10, 40]));
    });

    test(
      'allDivergenceTimes deduplicates when two signals diverge at the same time',
      () {
        const result = DiffResult(
          matchedSignals: [
            SignalMatch(
              pathA: _clkPath,
              pathB: _clkPath,
              isDifferent: true,
              divergenceRegions: [TimeRange(start: 10, end: 20)],
            ),
            SignalMatch(
              pathA: _rstPath,
              pathB: _rstPath,
              isDifferent: true,
              divergenceRegions: [TimeRange(start: 10, end: 30)],
            ),
          ],
          unmatchedA: [],
          unmatchedB: [],
        );
        const s = DiffState(diffResult: result);
        // Both signals start diverging at t=10; after dedup only one entry.
        expect(s.allDivergenceTimes, [10]);
        expect(s.totalDivergences, 1);
      },
    );

    test(
      'allDivergenceTimes is sorted ascending regardless of insertion order',
      () {
        const result = DiffResult(
          matchedSignals: [
            SignalMatch(
              pathA: _clkPath,
              pathB: _clkPath,
              isDifferent: true,
              divergenceRegions: [
                TimeRange(start: 80, end: 90),
                TimeRange(start: 5, end: 15),
                TimeRange(start: 50, end: 70),
              ],
            ),
          ],
          unmatchedA: [],
          unmatchedB: [],
        );
        const s = DiffState(diffResult: result);
        expect(s.allDivergenceTimes, [5, 50, 80]);
      },
    );

    test('allDivergenceTimes ignores signals with no divergence regions', () {
      const result = DiffResult(
        matchedSignals: [
          SignalMatch(pathA: _clkPath, pathB: _clkPath),
          SignalMatch(
            pathA: _rstPath,
            pathB: _rstPath,
            isDifferent: true,
            divergenceRegions: [TimeRange(start: 20, end: 30)],
          ),
        ],
        unmatchedA: [],
        unmatchedB: [],
      );
      const s = DiffState(diffResult: result);
      expect(s.allDivergenceTimes, [20]);
    });

    test('totalDivergences reflects unique start-time count', () {
      final s = DiffState(diffResult: _twoRegionResult());
      expect(s.totalDivergences, 2);
    });

    test('currentDivergenceTime at index 0 returns first divergence time', () {
      // divergenceIndex defaults to 0; omitting the redundant named argument.
      final s = DiffState(diffResult: _twoRegionResult());
      expect(s.currentDivergenceTime, 10);
    });

    test(
      'currentDivergenceTime at last index returns last divergence time',
      () {
        final s = DiffState(diffResult: _twoRegionResult(), divergenceIndex: 1);
        expect(s.currentDivergenceTime, 50);
      },
    );

    test(
      'currentDivergenceTime clamps out-of-bounds divergenceIndex to last',
      () {
        // divergenceIndex = 99 but only 2 divergence times ([10, 50]).
        final s = DiffState(
          diffResult: _twoRegionResult(),
          divergenceIndex: 99,
        );
        expect(s.currentDivergenceTime, 50);
      },
    );

    test(
      'allDivergenceRegions aggregates every region from all matched signals',
      () {
        const result = DiffResult(
          matchedSignals: [
            SignalMatch(
              pathA: _clkPath,
              pathB: _clkPath,
              isDifferent: true,
              divergenceRegions: [TimeRange(start: 10, end: 20)],
            ),
            SignalMatch(
              pathA: _rstPath,
              pathB: _rstPath,
              isDifferent: true,
              divergenceRegions: [
                TimeRange(start: 10, end: 30),
                TimeRange(start: 50, end: 60),
              ],
            ),
          ],
          unmatchedA: [],
          unmatchedB: [],
        );
        const s = DiffState(diffResult: result);
        // Three regions total (may overlap — canvas renders them as overlays).
        expect(s.allDivergenceRegions.length, 3);
      },
    );

    test('allDivergenceRegions is empty when all signals are identical', () {
      const result = DiffResult(
        matchedSignals: [
          SignalMatch(pathA: _clkPath, pathB: _clkPath),
          SignalMatch(pathA: _rstPath, pathB: _rstPath),
        ],
        unmatchedA: [],
        unmatchedB: [],
      );
      const s = DiffState(diffResult: result);
      expect(s.allDivergenceRegions, isEmpty);
    });
  });

  // ── DiffNotifier provider tests ────────────────────────────────────────────

  group('DiffNotifier', () {
    ProviderContainer makeContainer() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('initial state is idle DiffState', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final state = c.read(diffProvider);
      expect(state.isActive, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('clearDiff resets to idle', () {
      final c = makeContainer();
      addTearDown(c.dispose);

      // Manually put a non-idle state.
      c.read(diffProvider.notifier).clearDiff();
      expect(c.read(diffProvider).isActive, isFalse);
    });

    test(
      'loadSecondFile sets isLoading=true then resolves with error for bad path',
      () async {
        final c = makeContainer();
        addTearDown(c.dispose);

        await c.read(diffProvider.notifier).loadSecondFile('/nonexistent.vcd');

        final state = c.read(diffProvider);
        // Should have error, not loading.
        expect(state.isLoading, isFalse);
        expect(state.error, isNotNull);
      },
    );

    test('clearDiff after failed load resets state', () async {
      final c = makeContainer();
      addTearDown(c.dispose);

      await c.read(diffProvider.notifier).loadSecondFile('/bad.vcd');
      c.read(diffProvider.notifier).clearDiff();

      final state = c.read(diffProvider);
      expect(state.isActive, isFalse);
      expect(state.error, isNull);
    });

    test('nextDivergence is no-op when no divergences', () {
      final c = makeContainer();
      addTearDown(c.dispose);

      c.read(diffProvider.notifier).nextDivergence();
      expect(c.read(diffProvider).divergenceIndex, 0);
    });

    test('prevDivergence is no-op when no divergences', () {
      final c = makeContainer();
      addTearDown(c.dispose);

      c.read(diffProvider.notifier).prevDivergence();
      expect(c.read(diffProvider).divergenceIndex, 0);
    });
  });

  if (realTraces) {
    // ── DiffNotifier.loadSecondFile — deferred when primary is not loaded ────
    // Covers lines 174-178: path stored, state set to idle (non-loading),
    // no diff computation attempted.

    group('DiffNotifier.loadSecondFile — deferred (no primary loaded)', () {
      test(
        'stores secondFilePath without computing diff when primary is absent',
        () async {
          final c = _container();

          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          final state = c.read(diffProvider);
          expect(state.secondFilePath, _fixturePath);
          expect(state.isLoading, isFalse);
          expect(state.error, isNull);
          expect(state.diffResult, isNull);
        },
      );

      test(
        'xorTraces and divergences are empty in the deferred state',
        () async {
          final c = _container();

          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          final state = c.read(diffProvider);
          expect(state.xorTraces, isEmpty);
          expect(state.allDivergenceTimes, isEmpty);
        },
      );
    });

    // ── DiffNotifier.loadSecondFile — happy path (same file, both sources) ──
    // Covers the matchSignals, loadSignal loop, computeFullDiff, XOR-trace
    // loop, and final state assignment paths.
    //
    // When both sources are backed by the same VCD, WellenProvider queries by
    // VCD id code (the real signalRef) and returns identical values on both
    // sides, so no divergences are produced and xorTraces is empty.

    group('DiffNotifier.loadSecondFile — happy path same file', () {
      test(
        'diffResult is populated with matched signals after loading',
        () async {
          // Load the primary source manually to avoid platform-channel calls.
          final primary = WellenProvider();
          await primary.openFile(_fixturePath);

          final c = _containerWith(primary);
          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          final state = c.read(diffProvider);
          expect(state.isLoading, isFalse);
          expect(state.error, isNull);
          expect(state.diffResult, isNotNull);
        },
      );

      test('all three signals from scalar_basics.vcd are matched', () async {
        final primary = WellenProvider();
        await primary.openFile(_fixturePath);

        final c = _containerWith(primary);
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        final result = c.read(diffProvider).diffResult!;
        expect(result.matchedSignals.length, 3);
        final paths = result.matchedSignals.map((m) => m.pathA).toSet();
        expect(paths, containsAll(['top.clk', 'top.rst', 'top.data']));
      });

      test('no divergences when comparing a file against itself', () async {
        final primary = WellenProvider();
        await primary.openFile(_fixturePath);

        final c = _containerWith(primary);
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        final state = c.read(diffProvider);
        expect(
          state.diffResult!.matchedSignals.every((m) => !m.isDifferent),
          isTrue,
        );
        expect(state.xorTraces, isEmpty);
        expect(state.allDivergenceTimes, isEmpty);
      });

      test(
        'unmatchedA and unmatchedB are both empty for the same file',
        () async {
          final primary = WellenProvider();
          await primary.openFile(_fixturePath);

          final c = _containerWith(primary);
          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          final result = c.read(diffProvider).diffResult!;
          expect(result.unmatchedA, isEmpty);
          expect(result.unmatchedB, isEmpty);
        },
      );

      test('secondFilePath is set in the final state', () async {
        final primary = WellenProvider();
        await primary.openFile(_fixturePath);

        final c = _containerWith(primary);
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        expect(c.read(diffProvider).secondFilePath, _fixturePath);
      });
    });

    // ── DiffNotifier.loadSecondFile — mock primary produces XOR traces ───────
    // Covers the loop that computes XOR traces for differing signals.  The mock
    // primary always returns '1' for top.clk; the secondary loaded from
    // scalar_basics.vcd via WellenProvider returns the real VCD values for the
    // signal under top.clk's full path.  Any value mismatch — or a missing
    // signal in the secondary keyed by `signalRefA` — creates a divergence
    // region for the rest of the test.

    group('DiffNotifier.loadSecondFile — mock primary with divergences', () {
      test(
        'xorTraces is non-empty when primary and secondary values differ',
        () async {
          final c = _containerWith(_mockPrimary());

          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          expect(c.read(diffProvider).xorTraces, isNotEmpty);
        },
      );

      test(
        'clk signal XOR trace starts with value "1" (always different)',
        () async {
          final c = _containerWith(_mockPrimary());

          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          // Key is signalRefA ('ref_clk'), NOT pathA ('top.clk').
          final trace = c.read(diffProvider).xorTraces[_clkRef];
          expect(trace, isNotNull);
          expect(trace!.first.value, '1');
        },
      );

      test('matched signal is marked isDifferent=true', () async {
        final c = _containerWith(_mockPrimary());

        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        final match = c
            .read(diffProvider)
            .diffResult!
            .matchedSignals
            .singleWhere((m) => m.pathA == _clkPath);
        expect(match.isDifferent, isTrue);
      });

      test(
        'signals present only in secondary VCD appear in unmatchedB',
        () async {
          // Mock primary has only top.clk; scalar_basics.vcd also has rst
          // and data.
          final c = _containerWith(_mockPrimary());

          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          final result = c.read(diffProvider).diffResult!;
          expect(result.unmatchedB, containsAll(['top.rst', 'top.data']));
        },
      );

      test('allDivergenceTimes is non-empty after divergent load', () async {
        final c = _containerWith(_mockPrimary());

        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        expect(c.read(diffProvider).allDivergenceTimes, isNotEmpty);
      });

      test(
        'error is null and isLoading is false after successful divergent load',
        () async {
          final c = _containerWith(_mockPrimary());

          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          final state = c.read(diffProvider);
          expect(state.isLoading, isFalse);
          expect(state.error, isNull);
        },
      );
    });

    // ── DiffNotifier.loadSecondFile — re-triggering ──────────────────────────

    group('DiffNotifier.loadSecondFile — re-triggering', () {
      test(
        'second call with different bad path replaces the first error',
        () async {
          final c = _container();

          await c.read(diffProvider.notifier).loadSecondFile('/bad1.vcd');
          final first = c.read(diffProvider).error;

          await c.read(diffProvider.notifier).loadSecondFile('/bad2.vcd');
          final second = c.read(diffProvider).error;

          // Both fail but the most-recent error is retained, not the original.
          expect(first, isNotNull);
          expect(second, isNotNull);
          // The notifier is idle (no secondFilePath) after a complete failure.
          expect(c.read(diffProvider).secondFilePath, isNull);
        },
      );

      test('clearDiff between calls resets state cleanly', () async {
        final c = _container();

        await c.read(diffProvider.notifier).loadSecondFile('/bad.vcd');
        expect(c.read(diffProvider).error, isNotNull);

        c.read(diffProvider.notifier).clearDiff();
        expect(c.read(diffProvider).isActive, isFalse);
        expect(c.read(diffProvider).error, isNull);

        // Second load from a valid path should succeed.
        final primary = WellenProvider();
        await primary.openFile(_fixturePath);
        final c2 = _containerWith(primary);
        await c2.read(diffProvider.notifier).loadSecondFile(_fixturePath);
        expect(c2.read(diffProvider).diffResult, isNotNull);
      });
    });
  }

  // ── DiffNotifier.nextDivergence ────────────────────────────────────────────
  // Covers lines 244-261: cursor-aware forward navigation through divergence
  // start times with wrap-around.

  group('DiffNotifier.nextDivergence', () {
    // Uses _twoRegionResult() → allDivergenceTimes = [10, 50].

    test('null cursor goes to index 0 (first divergence time)', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      // No cursor placed — reads null from cursorStateProvider.
      c.read(diffProvider.notifier).nextDivergence();

      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 0);
      expect(state.currentDivergenceTime, 10);
    });

    test('cursor before first divergence goes to index 0', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(5);

      c.read(diffProvider.notifier).nextDivergence();

      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 0);
      expect(state.currentDivergenceTime, 10);
    });

    test('cursor between divergences advances to next', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(15);

      c.read(diffProvider.notifier).nextDivergence();

      // Next time after 15 is 50 (index 1).
      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 1);
      expect(state.currentDivergenceTime, 50);
    });

    test('cursor at last divergence time wraps around to index 0', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(50);

      c.read(diffProvider.notifier).nextDivergence();

      // No time > 50 in [10, 50], so wraps to index 0.
      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 0);
      expect(state.currentDivergenceTime, 10);
    });

    test('cursor past all divergences wraps to index 0', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(200);

      c.read(diffProvider.notifier).nextDivergence();

      expect(c.read(diffProvider).divergenceIndex, 0);
    });

    test('primary cursor is placed at the divergence time via _jumpToTime', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));

      c.read(diffProvider.notifier).nextDivergence();

      final cursor = c.read(cursorStateProvider).primaryCursorTime;
      expect(cursor, 10); // first divergence time
    });
  });

  // ── DiffNotifier.prevDivergence ────────────────────────────────────────────
  // Covers lines 263-290: cursor-aware backward navigation with wrap-around.

  group('DiffNotifier.prevDivergence', () {
    // Uses _twoRegionResult() → allDivergenceTimes = [10, 50].

    test('null cursor goes to last index (last divergence time)', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));

      c.read(diffProvider.notifier).prevDivergence();

      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 1);
      expect(state.currentDivergenceTime, 50);
    });

    test('cursor after last divergence goes to last index', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(100);

      c.read(diffProvider.notifier).prevDivergence();

      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 1);
      expect(state.currentDivergenceTime, 50);
    });

    test('cursor between divergences goes to the earlier one', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(30);

      c.read(diffProvider.notifier).prevDivergence();

      // Last time < 30 is 10 (index 0).
      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 0);
      expect(state.currentDivergenceTime, 10);
    });

    test('cursor at first divergence time wraps around to last index', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(10);

      c.read(diffProvider.notifier).prevDivergence();

      // No time < 10 in [10, 50], so wraps to last index (1).
      final state = c.read(diffProvider);
      expect(state.divergenceIndex, 1);
      expect(state.currentDivergenceTime, 50);
    });

    test('cursor before all divergences wraps to last index', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));
      c.read(cursorStateProvider.notifier).placePrimary(3);

      c.read(diffProvider.notifier).prevDivergence();

      expect(c.read(diffProvider).divergenceIndex, 1);
    });

    test('primary cursor is placed at the divergence time via _jumpToTime', () {
      final c = _navContainer(DiffState(diffResult: _twoRegionResult()));

      c.read(diffProvider.notifier).prevDivergence();

      final cursor = c.read(cursorStateProvider).primaryCursorTime;
      expect(cursor, 50); // last divergence time (null cursor → last index)
    });
  });

  if (realTraces) {
    // ── diffXorTraces derived provider ───────────────────────────────────────

    group('diffXorTraces provider', () {
      test('returns empty map when diff is idle', () {
        final c = ProviderContainer();
        addTearDown(c.dispose);

        expect(c.read(diffXorTracesProvider), isEmpty);
      });

      test('returns xorTraces from DiffNotifier state', () async {
        final c = _containerWith(_mockPrimary());

        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        // After a divergent load the derived provider reflects the xorTraces.
        expect(c.read(diffXorTracesProvider), isNotEmpty);
      });

      test('returns empty map after clearDiff', () async {
        final c = _containerWith(_mockPrimary());
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        c.read(diffProvider.notifier).clearDiff();

        expect(c.read(diffXorTracesProvider), isEmpty);
      });
    });
  }

  // ── DiffState.allDivergenceRegions ─────────────────────────────────────────

  group('DiffState.allDivergenceRegions', () {
    test('clamps divergenceIndex when accessing currentDivergenceTime', () {
      // Build a DiffState where divergenceIndex is out of bounds.
      const s = DiffState(divergenceIndex: 99);
      // No diffResult means allDivergenceTimes is empty — should return null.
      expect(s.currentDivergenceTime, isNull);
    });

    test('TimeRange equality', () {
      const r1 = TimeRange(start: 10, end: 20);
      const r2 = TimeRange(start: 10, end: 20);
      expect(r1, r2);
    });
  });

  if (realTraces) {
    // ── Bug 5 regression: xorTraces keyed by signalRefA not pathA ────────────

    group('DiffNotifier.loadSecondFile — xorTraces key is signalRefA', () {
      test('xorTraces is keyed by signalRefA, not pathA', () async {
        // _mockPrimary produces a Variable whose signalRef='ref_clk' (distinct
        // from its fullPath 'top.clk').  After the fix, xorTraces must be keyed
        // by 'ref_clk' so the canvas can look it up via signalRef.
        final c = _containerWith(_mockPrimary());
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        final traces = c.read(diffProvider).xorTraces;
        expect(
          traces.containsKey(_clkRef),
          isTrue,
          reason: 'xorTraces must be keyed by signalRefA ("$_clkRef")',
        );
        expect(
          traces.containsKey(_clkPath),
          isFalse,
          reason: 'xorTraces must NOT be keyed by pathA ("$_clkPath")',
        );
      });

      test(
        'xorTraces is empty when both files are identical (no divergences)',
        () async {
          final primary = WellenProvider();
          await primary.openFile(_fixturePath);
          final c = _containerWith(primary);
          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          expect(c.read(diffProvider).xorTraces, isEmpty);
        },
      );
    });

    // ── diffSignalStatusProvider ─────────────────────────────────────────────

    group('diffSignalStatusProvider', () {
      test('returns empty map when diff is idle', () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        expect(c.read(diffSignalStatusProvider), isEmpty);
      });

      test('returns empty map after clearDiff', () async {
        final c = _containerWith(_mockPrimary());
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);
        c.read(diffProvider.notifier).clearDiff();
        expect(c.read(diffSignalStatusProvider), isEmpty);
      });

      test('maps signalRefA to different for a diverging signal', () async {
        // _mockPrimary always returns '1' for ref_clk; the WellenProvider
        // secondary returns the real VCD value — a mismatch creates a
        // divergence.
        final c = _containerWith(_mockPrimary());
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        final statusMap = c.read(diffSignalStatusProvider);
        expect(statusMap[_clkRef], DiffSignalStatus.different);
      });

      test(
        'maps signalRefA to identical for a signal with no divergence',
        () async {
          // Comparing the same file against itself produces no divergences.
          final primary = WellenProvider();
          await primary.openFile(_fixturePath);
          final c = _containerWith(primary);
          await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

          final statusMap = c.read(diffSignalStatusProvider);
          // All signals are identical; every entry should be
          // DiffSignalStatus.identical.
          expect(statusMap.values, everyElement(DiffSignalStatus.identical));
          expect(statusMap, isNotEmpty);
        },
      );

      test('does not contain pathA as a key — keyed by signalRefA', () async {
        final c = _containerWith(_mockPrimary());
        await c.read(diffProvider.notifier).loadSecondFile(_fixturePath);

        final statusMap = c.read(diffSignalStatusProvider);
        // pathA = 'top.clk' must not appear; signalRefA = 'ref_clk' must
        // appear.
        expect(statusMap.containsKey(_clkPath), isFalse);
        expect(statusMap.containsKey(_clkRef), isTrue);
      });
    });
  }

  // The comparison file is a second native waveform source that nothing else
  // owns, so the notifier must close it on dispose and when it is replaced —
  // otherwise the whole second file leaks. These drive the leak paths through
  // the injectable [diffSecondSourceFactoryProvider]; the primary source is
  // null so loadSecondFile stores the second source and returns before diffing.
  group('DiffNotifier — second-source leak guards', () {
    ProviderContainer containerFor(
      WaveformDataSource Function() factory,
    ) {
      final c = ProviderContainer(
        overrides: [
          diffSecondSourceFactoryProvider.overrideWithValue(factory),
          waveformSourceProvider.overrideWith(_NullSourceNotifier.new),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    _MockDataSource stubbedSource() {
      final s = _MockDataSource();
      when(() => s.openFile(any())).thenAnswer((_) async {});
      return s;
    }

    test(
      'closes the comparison source when the notifier is disposed',
      () async {
        final source = stubbedSource();
        final c = containerFor(() => source);

        await c.read(diffProvider.notifier).loadSecondFile('/second.vcd');
        verifyNever(source.close);

        c.dispose();
        verify(source.close).called(1);
      },
    );

    test(
      'closes the previous comparison source when a new one is loaded',
      () async {
        final first = stubbedSource();
        final second = stubbedSource();
        final queue = <WaveformDataSource>[first, second];
        final c = containerFor(() => queue.removeAt(0));

        await c.read(diffProvider.notifier).loadSecondFile('/first.vcd');
        await c.read(diffProvider.notifier).loadSecondFile('/second.vcd');

        // The first source is released when the second replaces it.
        verify(first.close).called(1);
        verifyNever(second.close);
      },
    );
  });
}

/// Waveform-source notifier that reports no primary file, so `loadSecondFile`
/// short-circuits after storing the comparison source.
class _NullSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncData(null);
}
