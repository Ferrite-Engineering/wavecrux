// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../../../helpers/product_telemetry_config.dart';

void main() {
  // ── PatternSearchState ──────────────────────────────────────────────────────

  group('PatternSearchState', () {
    test('default constructor has sensible defaults', () {
      const state = PatternSearchState();
      expect(state.result, isNull);
      expect(state.currentMatchIndex, 0);
      expect(state.isSearching, isFalse);
      expect(state.error, isNull);
    });

    test('hasResult is false when result is null', () {
      const state = PatternSearchState();
      expect(state.hasResult, isFalse);
    });

    test('hasResult is false while searching', () {
      const state = PatternSearchState(isSearching: true);
      expect(state.hasResult, isFalse);
    });

    test('hasResult is true when result present and not searching', () {
      const expr = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const result = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const state = PatternSearchState(result: result);
      expect(state.hasResult, isTrue);
    });

    test('hasMatches is false with no matches', () {
      const expr = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const result = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const state = PatternSearchState(result: result);
      expect(state.hasMatches, isFalse);
    });

    test('hasMatches is true with at least one match', () {
      const expr = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const match = PatternMatch(
        time: 10,
        endTime: 20,
        signalValues: {'top.a': '1'},
      );
      const result = PatternSearchResult(
        matches: [match],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const state = PatternSearchState(result: result);
      expect(state.hasMatches, isTrue);
      expect(state.matchCount, 1);
    });

    test('currentMatch returns null when no matches', () {
      const state = PatternSearchState();
      expect(state.currentMatch, isNull);
    });

    test('currentMatch returns the match at currentMatchIndex', () {
      const expr = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const m0 = PatternMatch(
        time: 10,
        endTime: 20,
        signalValues: {'top.a': '1'},
      );
      const m1 = PatternMatch(
        time: 30,
        endTime: 40,
        signalValues: {'top.a': '1'},
      );
      const result = PatternSearchResult(
        matches: [m0, m1],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const state = PatternSearchState(result: result, currentMatchIndex: 1);
      expect(state.currentMatch, m1);
    });

    test('matchRanges returns empty list when no result', () {
      const state = PatternSearchState();
      expect(state.matchRanges, isEmpty);
    });

    test('matchRanges returns TimeRange list from matches', () {
      const expr = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const m0 = PatternMatch(
        time: 10,
        endTime: 20,
        signalValues: {'top.a': '1'},
      );
      const m1 = PatternMatch(
        time: 50,
        endTime: 60,
        signalValues: {'top.a': '1'},
      );
      const result = PatternSearchResult(
        matches: [m0, m1],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const state = PatternSearchState(result: result);
      expect(state.matchRanges, [
        const TimeRange(start: 10, end: 20),
        const TimeRange(start: 50, end: 60),
      ]);
    });

    test('copyWith preserves unchanged fields', () {
      const expr = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const result = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const original = PatternSearchState(result: result, currentMatchIndex: 2);
      final copy = original.copyWith(isSearching: true);
      expect(copy.result, same(original.result));
      expect(copy.currentMatchIndex, 2);
      expect(copy.isSearching, isTrue);
      expect(copy.error, isNull);
    });

    test('copyWith clearResult sets result to null', () {
      const expr = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const result = PatternSearchResult(
        matches: [],
        expression: expr,
        searchRange: TimeRange(start: 0, end: 100),
      );
      const state = PatternSearchState(result: result);
      final cleared = state.copyWith(clearResult: true);
      expect(cleared.result, isNull);
    });

    test('copyWith can clear error by passing null explicitly', () {
      const state = PatternSearchState(error: 'oops');
      final cleared = state.copyWith(error: null);
      expect(cleared.error, isNull);
    });

    test('equality: two default states are equal', () {
      const a = PatternSearchState();
      const b = PatternSearchState();
      expect(a, b);
    });

    test('equality: different error strings are not equal', () {
      const a = PatternSearchState(error: 'err1');
      const b = PatternSearchState(error: 'err2');
      expect(a, isNot(b));
    });

    test('hashCode matches for equal states', () {
      const a = PatternSearchState();
      const b = PatternSearchState();
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains matchCount, isSearching, error', () {
      const state = PatternSearchState(isSearching: true, error: 'e');
      final s = state.toString();
      expect(s, contains('searching: true'));
      expect(s, contains('error: e'));
    });
  });

  // ── PatternSearchNotifier ───────────────────────────────────────────────────

  group('PatternSearchNotifier', () {
    ProviderContainer buildContainer() {
      return ProviderContainer(overrides: [productTelemetryConfig]);
    }

    ProviderContainer buildContainerWithSource(WaveformDataSource source) {
      // Build a passthrough variables map where each signalRef key is also the
      // signalRef value.  Existing tests pass signalPaths that already ARE
      // signalRefs, so resolution step 1 (exact-ref match) passes unchanged.
      final passthroughVars = source is _FakeSource
          ? {
              for (final ref in source.signalRefs)
                ref: Variable(
                  name: ref,
                  varType: VarType.wire,
                  direction: VarDirection.unknown,
                  signalRef: ref,
                  scopePath: '',
                ),
            }
          : const <String, Variable>{};

      final c = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          waveformSourceProvider.overrideWith(
            () => _StubSourceNotifier(source),
          ),
          signalVariablesMapProvider.overrideWithValue(passthroughVars),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('initial state is empty PatternSearchState', () {
      final container = buildContainer();
      addTearDown(container.dispose);
      final state = container.read(patternSearchProvider);
      expect(state, const PatternSearchState());
    });

    test('clearSearch resets to empty state', () {
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(patternSearchProvider.notifier).clearSearch();

      expect(container.read(patternSearchProvider), const PatternSearchState());
    });

    test('nextMatch is a no-op when there are no matches', () {
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(patternSearchProvider.notifier).nextMatch();

      expect(container.read(patternSearchProvider), const PatternSearchState());
    });

    test('prevMatch is a no-op when there are no matches', () {
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(patternSearchProvider.notifier).prevMatch();

      expect(container.read(patternSearchProvider), const PatternSearchState());
    });

    test(
      'search sets isSearching then flags noWaveform when none loaded',
      () async {
        final container = buildContainer();
        addTearDown(container.dispose);

        await container
            .read(patternSearchProvider.notifier)
            .search(
              const SignalCondition(
                signalPath: 'top.a',
                operator: ConditionOperator.eq,
                value: '1',
              ),
              0,
              100,
            );

        final state = container.read(patternSearchProvider);
        expect(state.isSearching, isFalse);
        // The "no waveform" guidance is signalled via the typed flag (the
        // toolbar renders a localized label for it) rather than a hard-coded
        // English string in `error`.
        expect(state.noWaveform, isTrue);
        expect(state.error, isNull);
      },
    );

    // ── state machine ───────────────────────────────────────────────────────────

    test('state machine: idle → searching → results_available', () async {
      // top.a is '0' at t=0, becomes '1' at t=10, back to '0' at t=20.
      final source = _FakeSource({
        'top.a': [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 10, value: '1'),
          const SignalChange(time: 20, value: '0'),
        ],
      });
      final c = buildContainerWithSource(source);

      // Record intermediate states by listening before the call.
      final states = <PatternSearchState>[];
      c.listen(patternSearchProvider, (_, next) => states.add(next));

      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: 'top.a',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      // First emitted state must be searching.
      expect(states.first.isSearching, isTrue);
      expect(states.first.result, isNull);

      // Final state must have result with one match [10, 20).
      final final_ = c.read(patternSearchProvider);
      expect(final_.isSearching, isFalse);
      expect(final_.hasResult, isTrue);
      expect(final_.hasMatches, isTrue);
      expect(final_.matchCount, 1);
      expect(final_.currentMatch!.time, 10);
      expect(final_.currentMatch!.endTime, 20);
    });

    test('state machine: idle → searching → no_results', () async {
      // top.a is always '0' — condition top.a == 1 never true.
      final source = _FakeSource({
        'top.a': [const SignalChange(time: 0, value: '0')],
      });
      final c = buildContainerWithSource(source);

      final states = <PatternSearchState>[];
      c.listen(patternSearchProvider, (_, next) => states.add(next));

      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: 'top.a',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      expect(states.first.isSearching, isTrue);

      final final_ = c.read(patternSearchProvider);
      expect(final_.isSearching, isFalse);
      expect(final_.hasResult, isTrue);
      expect(final_.hasMatches, isFalse);
      expect(final_.matchCount, 0);
    });

    // ── search cancellation ─────────────────────────────────────────────────────

    test('second search call overrides in-flight search state', () async {
      // Source with two signals: top.a matches cond A, top.b matches cond B.
      final source = _FakeSource({
        'top.a': [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 10, value: '1'),
          const SignalChange(time: 20, value: '0'),
        ],
        'top.b': [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 30, value: '1'),
          const SignalChange(time: 40, value: '0'),
        ],
      });
      final c = buildContainerWithSource(source);

      const exprA = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const exprB = SignalCondition(
        signalPath: 'top.b',
        operator: ConditionOperator.eq,
        value: '1',
      );

      // Fire first search but do not await — fire second immediately after.
      final futureA = c
          .read(patternSearchProvider.notifier)
          .search(exprA, 0, 100);
      final futureB = c
          .read(patternSearchProvider.notifier)
          .search(exprB, 0, 100);

      await Future.wait([futureA, futureB]);

      // The final state must reflect the last call (exprB → match at [30,40)).
      final s = c.read(patternSearchProvider);
      expect(s.isSearching, isFalse);
      expect(s.hasMatches, isTrue);
      // The result expression must be the one for top.b.
      expect(s.result!.expression, exprB);
    });

    // ── expression forwarded to service ────────────────────────────────────────

    test(
      'PatternExpression is forwarded: AND expression finds intersection',
      () async {
        // top.a == 1 in [10,30), top.b == 1 in [20,40)
        // → AND match: [20,30)
        final source = _FakeSource({
          'top.a': [
            const SignalChange(time: 0, value: '0'),
            const SignalChange(time: 10, value: '1'),
            const SignalChange(time: 30, value: '0'),
          ],
          'top.b': [
            const SignalChange(time: 0, value: '0'),
            const SignalChange(time: 20, value: '1'),
            const SignalChange(time: 40, value: '0'),
          ],
        });
        final c = buildContainerWithSource(source);

        const expr = AndExpression(
          left: SignalCondition(
            signalPath: 'top.a',
            operator: ConditionOperator.eq,
            value: '1',
          ),
          right: SignalCondition(
            signalPath: 'top.b',
            operator: ConditionOperator.eq,
            value: '1',
          ),
        );

        await c.read(patternSearchProvider.notifier).search(expr, 0, 100);

        final s = c.read(patternSearchProvider);
        expect(s.hasMatches, isTrue);
        expect(s.matchCount, 1);
        expect(s.currentMatch!.time, 20);
        expect(s.currentMatch!.endTime, 30);
      },
    );

    test('PatternExpression is forwarded: OR expression finds union', () async {
      // top.a == 1 in [10,20), top.b == 1 in [30,40)
      // → OR matches: [10,20) and [30,40) (two separate matches)
      final source = _FakeSource({
        'top.a': [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 10, value: '1'),
          const SignalChange(time: 20, value: '0'),
        ],
        'top.b': [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 30, value: '1'),
          const SignalChange(time: 40, value: '0'),
        ],
      });
      final c = buildContainerWithSource(source);

      const expr = OrExpression(
        left: SignalCondition(
          signalPath: 'top.a',
          operator: ConditionOperator.eq,
          value: '1',
        ),
        right: SignalCondition(
          signalPath: 'top.b',
          operator: ConditionOperator.eq,
          value: '1',
        ),
      );

      await c.read(patternSearchProvider.notifier).search(expr, 0, 100);

      final s = c.read(patternSearchProvider);
      expect(s.hasMatches, isTrue);
      expect(s.matchCount, 2);
    });

    // ── nextMatch / prevMatch with results ──────────────────────────────────────

    test('nextMatch advances currentMatchIndex and wraps', () async {
      final source = _FakeSource({
        'top.a': [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 10, value: '1'),
          const SignalChange(time: 20, value: '0'),
          const SignalChange(time: 30, value: '1'),
          const SignalChange(time: 40, value: '0'),
        ],
      });
      final c = buildContainerWithSource(source);

      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: 'top.a',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      expect(c.read(patternSearchProvider).matchCount, 2);
      expect(c.read(patternSearchProvider).currentMatchIndex, 0);

      c.read(patternSearchProvider.notifier).nextMatch();
      expect(c.read(patternSearchProvider).currentMatchIndex, 1);

      // Wrap around.
      c.read(patternSearchProvider.notifier).nextMatch();
      expect(c.read(patternSearchProvider).currentMatchIndex, 0);
    });

    test('prevMatch decrements currentMatchIndex and wraps', () async {
      final source = _FakeSource({
        'top.a': [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 10, value: '1'),
          const SignalChange(time: 20, value: '0'),
          const SignalChange(time: 30, value: '1'),
          const SignalChange(time: 40, value: '0'),
        ],
      });
      final c = buildContainerWithSource(source);

      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: 'top.a',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      // prevMatch from index 0 wraps to last match.
      c.read(patternSearchProvider.notifier).prevMatch();
      expect(c.read(patternSearchProvider).currentMatchIndex, 1);
    });

    // ── clearSearch from completed result ───────────────────────────────────────

    test(
      'clearSearch resets state from a completed search with results',
      () async {
        final source = _FakeSource({
          'top.a': [
            const SignalChange(time: 0, value: '0'),
            const SignalChange(time: 10, value: '1'),
            const SignalChange(time: 20, value: '0'),
          ],
        });
        final c = buildContainerWithSource(source);

        await c
            .read(patternSearchProvider.notifier)
            .search(
              const SignalCondition(
                signalPath: 'top.a',
                operator: ConditionOperator.eq,
                value: '1',
              ),
              0,
              100,
            );

        expect(c.read(patternSearchProvider).hasMatches, isTrue);

        c.read(patternSearchProvider.notifier).clearSearch();

        expect(c.read(patternSearchProvider), const PatternSearchState());
      },
    );
  });

  // ── signal-name resolution (expression mode) ────────────────────────────────

  group('signal name resolution', () {
    // Signal data: idcode "!" is chip_select in scope top; "\"" is data in top.
    final source = _FakeSource({
      '!': [
        const SignalChange(time: 0, value: '0'),
        const SignalChange(time: 10, value: '1'),
        const SignalChange(time: 20, value: '0'),
      ],
      '"': [
        const SignalChange(time: 0, value: '0'),
        const SignalChange(time: 15, value: '1'),
        const SignalChange(time: 25, value: '0'),
      ],
    });

    // Variables map mirrors the two signals above.
    final variablesMap = <String, Variable>{
      '!': const Variable(
        name: 'chip_select',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: '!',
        scopePath: 'top',
        bitWidth: 1,
      ),
      '"': const Variable(
        name: 'data',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: '"',
        scopePath: 'top',
        bitWidth: 8,
      ),
    };

    ProviderContainer buildContainerWithSourceAndVars(
      WaveformDataSource src,
      Map<String, Variable> vars,
    ) {
      final c = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          waveformSourceProvider.overrideWith(() => _StubSourceNotifier(src)),
          signalVariablesMapProvider.overrideWithValue(vars),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('leaf name resolves to correct signalRef and returns match', () async {
      final c = buildContainerWithSourceAndVars(source, variablesMap);

      // Use the signal leaf name instead of the raw VCD idcode.
      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: 'chip_select',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      final s = c.read(patternSearchProvider);
      expect(s.hasMatches, isTrue);
      expect(s.matchCount, 1);
      expect(s.currentMatch!.time, 10);
      expect(s.currentMatch!.endTime, 20);
    });

    test('full hierarchical path resolves to correct signalRef', () async {
      final c = buildContainerWithSourceAndVars(source, variablesMap);

      // Use the full path "top.chip_select".
      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: 'top.chip_select',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      final s = c.read(patternSearchProvider);
      expect(s.hasMatches, isTrue);
      expect(s.currentMatch!.time, 10);
    });

    test('raw signalRef passthrough works (builder mode)', () async {
      final c = buildContainerWithSourceAndVars(source, variablesMap);

      // Builder mode passes the signalRef "!" directly.
      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: '!',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      final s = c.read(patternSearchProvider);
      expect(s.hasMatches, isTrue);
      expect(s.currentMatch!.time, 10);
    });

    test('AND expression with two leaf names resolves both signals', () async {
      final c = buildContainerWithSourceAndVars(source, variablesMap);

      // chip_select == 1 in [10,20), data == 1 in [15,25) → AND: [15,20)
      await c
          .read(patternSearchProvider.notifier)
          .search(
            const AndExpression(
              left: SignalCondition(
                signalPath: 'chip_select',
                operator: ConditionOperator.eq,
                value: '1',
              ),
              right: SignalCondition(
                signalPath: 'data',
                operator: ConditionOperator.eq,
                value: '1',
              ),
            ),
            0,
            100,
          );

      final s = c.read(patternSearchProvider);
      expect(s.hasMatches, isTrue);
      expect(s.matchCount, 1);
      expect(s.currentMatch!.time, 15);
      expect(s.currentMatch!.endTime, 20);
    });

    test('unknown signal name sets error state with helpful message', () async {
      final c = buildContainerWithSourceAndVars(source, variablesMap);

      await c
          .read(patternSearchProvider.notifier)
          .search(
            const SignalCondition(
              signalPath: 'nonexistent_signal',
              operator: ConditionOperator.eq,
              value: '1',
            ),
            0,
            100,
          );

      final s = c.read(patternSearchProvider);
      expect(s.hasMatches, isFalse);
      expect(s.error, isNotNull);
      expect(s.error, contains('nonexistent_signal'));
    });

    test(
      'ambiguous leaf name sets error state with disambiguation hint',
      () async {
        // Two signals with the same leaf name in different scopes.
        final ambiguousVars = <String, Variable>{
          'A': const Variable(
            name: 'clk',
            varType: VarType.wire,
            direction: VarDirection.unknown,
            signalRef: 'A',
            scopePath: 'top.cpu',
            bitWidth: 1,
          ),
          'B': const Variable(
            name: 'clk',
            varType: VarType.wire,
            direction: VarDirection.unknown,
            signalRef: 'B',
            scopePath: 'top.mem',
            bitWidth: 1,
          ),
        };
        final ambiguousSource = _FakeSource({
          'A': [const SignalChange(time: 0, value: '0')],
          'B': [const SignalChange(time: 0, value: '0')],
        });

        final c = buildContainerWithSourceAndVars(
          ambiguousSource,
          ambiguousVars,
        );

        await c
            .read(patternSearchProvider.notifier)
            .search(
              const SignalCondition(
                signalPath: 'clk',
                operator: ConditionOperator.eq,
                value: '1',
              ),
              0,
              100,
            );

        final s = c.read(patternSearchProvider);
        expect(s.error, isNotNull);
        expect(s.error, contains('clk'));
        // Error should hint at using the full path.
        expect(s.error, contains('path'));
      },
    );
  });
}

// ── test doubles ──────────────────────────────────────────────────────────────

/// Stub [WaveformSourceNotifier] that returns a pre-built [WaveformDataSource].
class _StubSourceNotifier extends WaveformSourceNotifier {
  _StubSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// Minimal [WaveformDataSource] backed by a map of signal → change list.
///
/// All signals are considered pre-loaded; value queries are answered by walking
/// the change list.
class _FakeSource implements WaveformDataSource {
  _FakeSource(this._changes);

  final Map<String, List<SignalChange>> _changes;

  /// Exposes the signal refs known to this source for passthrough map builds.
  Iterable<String> get signalRefs => _changes.keys;

  @override
  bool isSignalLoaded(String signalRef) => true;

  @override
  Future<void> loadSignal(String signalRef) async {}

  @override
  Future<void> unloadSignal(String signalRef) async {}

  @override
  String? valueAt(String signalRef, int time) {
    final changes = _changes[signalRef];
    if (changes == null) return null;
    String? last;
    for (final c in changes) {
      if (c.time <= time) {
        last = c.value;
      } else {
        break;
      }
    }
    return last;
  }

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) {
    final changes = _changes[signalRef];
    if (changes == null) return [];
    return changes.where((c) => c.time >= start && c.time < end).toList();
  }

  @override
  int get startTime => 0;

  @override
  int get endTime => 100;

  // Unused members — minimal stubs.
  @override
  Future<void> openFile(String path) async {}
  @override
  void close() {}
  @override
  List<Scope> get rootScopes => [];
  @override
  List<Variable> findVariables(SignalFilter filter) => [];
  @override
  SignalChange? nextTransition(String signalRef, int afterTime) => null;
  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) => null;
  @override
  Timescale? get timescale => null;
  @override
  String? get date => null;
  @override
  String? get version => null;
}
