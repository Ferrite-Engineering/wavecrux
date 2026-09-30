// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/widgets/pattern_search_toolbar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Widget _buildToolbar({
  PatternSearchState? initialState,
}) {
  return ProviderScope(
    overrides: [
      if (initialState != null)
        patternSearchProvider.overrideWith(() => _StubNotifier(initialState)),
    ],
    child: const MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: Scaffold(
        body: PatternSearchToolbar(),
      ),
    ),
  );
}

class _StubNotifier extends PatternSearchNotifier {
  _StubNotifier(this._state);
  final PatternSearchState _state;

  @override
  PatternSearchState build() => _state;
}

PatternSearchResult _makeResult({List<PatternMatch> matches = const []}) {
  return PatternSearchResult(
    matches: matches,
    expression: const SignalCondition(
      signalPath: 'top.a',
      operator: ConditionOperator.eq,
      value: '1',
    ),
    searchRange: const TimeRange(start: 0, end: 100),
  );
}

PatternMatch _makeMatch(int start, int end) => PatternMatch(
  time: start,
  endTime: end,
  signalValues: const {'top.a': '1'},
);

void main() {
  group('PatternSearchToolbar', () {
    testWidgets('hidden when state is idle (no result, not searching)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();
      expect(find.byType(PatternSearchToolbar), findsOneWidget);
      // SizedBox.shrink — no Container rendered
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('locale sweep — no exceptions in en', (tester) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: PatternSearchState(
            result: _makeResult(matches: [_makeMatch(10, 20)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — no exceptions in zh_CN', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patternSearchProvider.overrideWith(
              () => _StubNotifier(
                PatternSearchState(
                  result: _makeResult(matches: [_makeMatch(10, 20)]),
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: [Locale('zh', 'CN')],
            locale: Locale('zh', 'CN'),
            home: Scaffold(body: PatternSearchToolbar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — no exceptions in ja', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patternSearchProvider.overrideWith(
              () => _StubNotifier(
                PatternSearchState(
                  result: _makeResult(matches: [_makeMatch(10, 20)]),
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: [Locale('ja')],
            locale: Locale('ja'),
            home: Scaffold(body: PatternSearchToolbar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — no exceptions in ko', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patternSearchProvider.overrideWith(
              () => _StubNotifier(
                PatternSearchState(
                  result: _makeResult(matches: [_makeMatch(10, 20)]),
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: [Locale('ko')],
            locale: Locale('ko'),
            home: Scaffold(body: PatternSearchToolbar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows searching spinner when isSearching', (tester) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: const PatternSearchState(isSearching: true),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows no-matches label when result has zero matches', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: PatternSearchState(result: _makeResult()),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = tester.element(find.byType(PatternSearchToolbar)).l10n;
      expect(find.text(l10n.patternSearchToolbarNoMatches), findsOneWidget);
    });

    testWidgets('shows match counter label with matches', (tester) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: PatternSearchState(
            result: _makeResult(
              matches: [_makeMatch(10, 20), _makeMatch(30, 40)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = tester.element(find.byType(PatternSearchToolbar)).l10n;
      expect(
        find.text(l10n.patternSearchToolbarMatchOf(1, 2)),
        findsOneWidget,
      );
    });

    testWidgets('nav buttons present when there are matches', (tester) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: PatternSearchState(
            result: _makeResult(matches: [_makeMatch(10, 20)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('nav buttons absent when there are no matches', (tester) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: PatternSearchState(result: _makeResult()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });

    testWidgets('close button always present when toolbar is shown', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: PatternSearchState(result: _makeResult()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('error state shows error message', (tester) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: const PatternSearchState(error: 'Something went wrong'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('toolbar height is 28', (tester) async {
      await tester.pumpWidget(
        _buildToolbar(
          initialState: PatternSearchState(result: _makeResult()),
        ),
      );
      await tester.pumpAndSettle();
      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxHeight ?? container.child, isNotNull);
    });
  });
}

extension on Element {
  L10N get l10n => L10N.of(this);
}
