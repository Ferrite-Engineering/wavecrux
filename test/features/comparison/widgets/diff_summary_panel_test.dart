// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/diff_result.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/comparison/widgets/diff_summary_panel.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Widget _wrap(Widget child, {DiffState state = const DiffState()}) =>
    ProviderScope(
      overrides: [
        diffProvider.overrideWith(() => _FakeDiffNotifier(state)),
      ],
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: DiffSummaryPanel()),
      ),
    );

class _FakeDiffNotifier extends DiffNotifier {
  _FakeDiffNotifier(this._state);
  final DiffState _state;
  @override
  DiffState build() => _state;
}

/// Resolves the active [L10N] from the pumped panel's context.
L10N _l10n(WidgetTester tester) =>
    L10N.of(tester.element(find.byType(DiffSummaryPanel)));

/// A matched signal that is identical (no divergence regions).
SignalMatch _identicalMatch(String path) =>
    SignalMatch(pathA: path, pathB: path);

/// A matched signal that differs at [firstDivergence] with [regions] regions.
SignalMatch _differentMatch(
  String path, {
  int firstDivergence = 100,
  int regions = 1,
}) => SignalMatch(
  pathA: path,
  pathB: path,
  isDifferent: true,
  divergenceRegions: [
    for (var i = 0; i < regions; i++)
      TimeRange(
        start: firstDivergence + i * 50,
        end: firstDivergence + i * 50 + 10,
      ),
  ],
);

DiffState _populatedState({
  List<SignalMatch> matched = const [],
  List<String> unmatchedA = const [],
  List<String> unmatchedB = const [],
}) => DiffState(
  secondFilePath: '/b.vcd',
  diffResult: DiffResult(
    matchedSignals: matched,
    unmatchedA: unmatchedA,
    unmatchedB: unmatchedB,
  ),
);

void main() {
  group('DiffSummaryPanel — locale sweep', () {
    // Sweep with a populated diff so chip / section / tile strings all render
    // (catches RenderFlex overflow and CJK rendering in the real content path).
    final sweepState = _populatedState(
      matched: [
        _identicalMatch('top.clk'),
        _differentMatch('top.data', regions: 3),
      ],
      unmatchedA: ['top.only_a'],
      unmatchedB: ['top.only_b'],
    );
    for (final locale in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              diffProvider.overrideWith(() => _FakeDiffNotifier(sweepState)),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              locale: Locale(
                locale.replaceAll('_CN', ''),
                locale.contains('_') ? locale.split('_')[1] : null,
              ),
              home: const Scaffold(body: DiffSummaryPanel()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DiffSummaryPanel — idle / loading / error states', () {
    testWidgets('shows no-file placeholder when diff is idle', (tester) async {
      await tester.pumpWidget(_wrap(const DiffSummaryPanel()));
      await tester.pumpAndSettle();
      expect(find.byType(DiffSummaryPanel), findsOneWidget);
      expect(find.text(_l10n(tester).diffSummaryNoFile), findsOneWidget);
    });

    testWidgets('shows loading indicator when isLoading', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: const DiffState(secondFilePath: '/b.vcd', isLoading: true),
        ),
      );
      // pump (not pumpAndSettle) — CircularProgressIndicator never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error text when diff has error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: const DiffState(error: 'file not found'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('file not found'), findsOneWidget);
    });
  });

  group('DiffSummaryPanel — populated summary chips', () {
    testWidgets('shows identical + different chips', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: _populatedState(
            matched: [
              _identicalMatch('top.a'),
              _identicalMatch('top.b'),
              _differentMatch('top.c'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      // identicalCount = matchedCount(3) - differentCount(1) = 2
      expect(find.text(_l10n(tester).diffSummaryIdentical(2)), findsOneWidget);
      expect(find.text(_l10n(tester).diffSummaryDifferent(1)), findsOneWidget);
    });

    testWidgets('shows only-in-A and only-in-B chips when nonzero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: _populatedState(
            matched: [_identicalMatch('top.a')],
            unmatchedA: ['top.x', 'top.y'],
            unmatchedB: ['top.z'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).diffSummaryOnlyInA(2)), findsOneWidget);
      expect(find.text(_l10n(tester).diffSummaryOnlyInB(1)), findsOneWidget);
    });

    testWidgets('omits only-in-A/B chips when counts are zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: _populatedState(matched: [_identicalMatch('top.a')]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).diffSummaryOnlyInA(0)), findsNothing);
      expect(find.text(_l10n(tester).diffSummaryOnlyInB(0)), findsNothing);
    });
  });

  group('DiffSummaryPanel — matched signal list', () {
    testWidgets('renders matched-signals section header and rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: _populatedState(
            matched: [
              _identicalMatch('top.clk'),
              _differentMatch('top.data', regions: 2),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(_l10n(tester).diffSummaryMatchedSignals),
        findsOneWidget,
      );
      expect(find.text('top.clk'), findsOneWidget);
      expect(find.text('top.data'), findsOneWidget);
      // Identical row uses a check icon; different row uses a close icon.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      // Divergence-region count badge for the differing row.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('different row with empty regions shows no count badge', (
      tester,
    ) async {
      // isDifferent true but no regions => firstDivergenceTime null, no badge.
      const match = SignalMatch(
        pathA: 'top.x',
        pathB: 'top.x',
        isDifferent: true,
      );
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: _populatedState(matched: const [match]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);
      // No region-count badge text.
      expect(find.text('0'), findsNothing);
    });

    testWidgets('tapping a differing row jumps the primary cursor', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          diffProvider.overrideWith(
            () => _FakeDiffNotifier(
              _populatedState(
                matched: [_differentMatch('top.data', firstDivergence: 250)],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      // cursorStateProvider is autoDispose; keep an active subscription so the
      // post-tap state survives until we read it back.
      final sub = container.listen(cursorStateProvider, (_, _) {});
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: DiffSummaryPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sub.read().primaryCursorTime, isNull);

      await tester.tap(find.text('top.data'));
      await tester.pumpAndSettle();

      // No waveform loaded => clamp is a no-op, so the cursor lands exactly on
      // the first divergence time.
      expect(sub.read().primaryCursorTime, 250);
    });

    testWidgets('tapping an identical row does not move the cursor', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          diffProvider.overrideWith(
            () => _FakeDiffNotifier(
              _populatedState(matched: [_identicalMatch('top.clk')]),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(cursorStateProvider, (_, _) {});
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: DiffSummaryPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('top.clk'));
      await tester.pumpAndSettle();
      // onTap is null for identical rows — cursor stays unset.
      expect(sub.read().primaryCursorTime, isNull);
    });
  });

  group('DiffSummaryPanel — unmatched signal list', () {
    testWidgets('renders unmatched section with A and B markers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: _populatedState(
            unmatchedA: ['top.only_a'],
            unmatchedB: ['top.only_b'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).diffSummaryUnmatched), findsOneWidget);
      expect(find.text('top.only_a'), findsOneWidget);
      expect(find.text('top.only_b'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      // Unmatched tiles use the remove icon.
      expect(find.byIcon(Icons.remove), findsNWidgets(2));
    });

    testWidgets('empty result renders no section headers', (tester) async {
      await tester.pumpWidget(
        _wrap(const DiffSummaryPanel(), state: _populatedState()),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).diffSummaryMatchedSignals), findsNothing);
      expect(find.text(_l10n(tester).diffSummaryUnmatched), findsNothing);
      // But the summary chips for an empty diff still render (0 identical, 0
      // different) without error.
      expect(tester.takeException(), isNull);
    });

    // A diff of two full-design dumps matches every variable in the design.
    //
    // The 2026-09 audit read "one tile per variable" here as an unbounded
    // render. Measured, it is not: `ListView(children: [...])` constructs
    // the child *widgets* eagerly but its `SliverChildListDelegate` only
    // ever mounts and lays out the ones in view, so a 20 000-signal diff
    // builds 25 tiles in 290 ms — the same 25 tiles in 298 ms as an
    // explicitly index-built `ListView.builder`, i.e. no difference outside
    // noise. The eager child list stays.
    //
    // PRIMARY MUTATION TARGET: replacing the `ListView` with a `Column`
    // (or any non-viewport parent) builds all 20 000 tiles and fails this.
    testWidgets('a 20 000-signal diff builds only the tiles in view', (
      tester,
    ) async {
      final matched = <SignalMatch>[
        for (var i = 0; i < 20000; i++)
          if (i.isEven)
            _identicalMatch('top.s$i')
          else
            _differentMatch('top.s$i'),
      ];
      final sw = Stopwatch()..start();
      await tester.pumpWidget(
        _wrap(
          const DiffSummaryPanel(),
          state: _populatedState(
            matched: matched,
            unmatchedA: const ['top.only_a'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      sw.stop();

      expect(tester.takeException(), isNull);
      final tiles = tester
          .elementList(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_SignalMatchTile',
            ),
          )
          .length;
      expect(
        tiles,
        lessThan(200),
        reason: 'built $tiles tiles in ${sw.elapsedMilliseconds} ms',
      );
      // The header and the first rows are still there, in order.
      expect(
        find.text(_l10n(tester).diffSummaryMatchedSignals),
        findsOneWidget,
      );
      expect(find.text('top.s0'), findsOneWidget);
      expect(find.text('top.s19999'), findsNothing);
    });
  });
}
