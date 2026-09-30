// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/comparison/widgets/diff_toolbar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

class _FakeDiffNotifier extends DiffNotifier {
  _FakeDiffNotifier(this._state);
  final DiffState _state;
  @override
  DiffState build() => _state;
}

Widget _wrap(DiffState state, {VoidCallback? onCompareWith}) => ProviderScope(
  overrides: [
    diffProvider.overrideWith(() => _FakeDiffNotifier(state)),
  ],
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: DiffToolbar(onCompareWith: onCompareWith ?? () {}),
    ),
  ),
);

void main() {
  group('DiffToolbar — locale sweep', () {
    for (final localeParts in [
      ['en', null],
      ['zh', 'CN'],
      ['ja', null],
      ['ko', null],
    ]) {
      final tag = localeParts[1] != null
          ? '${localeParts[0]}_${localeParts[1]}'
          : localeParts[0]!;
      testWidgets('renders without exception in $tag', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              diffProvider.overrideWith(
                () => _FakeDiffNotifier(const DiffState()),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              locale: Locale(localeParts[0]!, localeParts[1]),
              home: Scaffold(
                body: DiffToolbar(onCompareWith: () {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DiffToolbar — inactive state', () {
    testWidgets('shows Compare with button when no file loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const DiffState()));
      await tester.pumpAndSettle();
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('tapping Compare with invokes onCompareWith', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(const DiffState(), onCompareWith: () => called = true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton));
      expect(called, isTrue);
    });

    testWidgets('close and nav buttons absent when inactive', (tester) async {
      await tester.pumpWidget(_wrap(const DiffState()));
      await tester.pumpAndSettle();
      // Close button uses Icons.close; nav uses Icons.chevron_left/right.
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });

  group('DiffToolbar — active state', () {
    const activeState = DiffState(secondFilePath: '/path/to/b.vcd');

    testWidgets('shows filename when active', (tester) async {
      await tester.pumpWidget(_wrap(activeState));
      await tester.pumpAndSettle();
      expect(find.textContaining('b.vcd'), findsOneWidget);
    });

    testWidgets('shows close button when active', (tester) async {
      await tester.pumpWidget(_wrap(activeState));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('tapping close invokes onClose callback', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            diffProvider.overrideWith(() => _FakeDiffNotifier(activeState)),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: DiffToolbar(
                onCompareWith: () {},
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });

    testWidgets('shows nav buttons when active and not loading', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(activeState));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows loading indicator when isLoading', (tester) async {
      const loadingState = DiffState(secondFilePath: '/b.vcd', isLoading: true);
      await tester.pumpWidget(_wrap(loadingState));
      // Use pump (not pumpAndSettle) — CircularProgressIndicator never settles.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('no divergences label when no diff result', (tester) async {
      await tester.pumpWidget(_wrap(activeState));
      await tester.pumpAndSettle();
      // With no diffResult, totalDivergences == 0 → "No divergences" label.
      expect(find.textContaining('0'), findsNothing);
    });
  });

  group('DiffToolbar — fixed height', () {
    testWidgets('toolbar is exactly DiffToolbar.height tall', (tester) async {
      await tester.pumpWidget(_wrap(const DiffState()));
      await tester.pumpAndSettle();
      final toolbar = find.byType(DiffToolbar);
      final size = tester.getSize(toolbar);
      expect(size.height, DiffToolbar.height);
    });
  });
}
