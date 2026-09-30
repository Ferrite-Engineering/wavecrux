// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/about/widgets/about_acknowledgments_screen.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── Widget builder ────────────────────────────────────────────────────────────

Widget _buildApp({String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  home: const AboutAcknowledgmentsScreen(),
);

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── locale sweeps ───────────────────────────────────────────────────────────

  group('locale sweeps', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(_buildApp(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── content checks ──────────────────────────────────────────────────────────

  group('content', () {
    testWidgets('shows screen title', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Acknowledgments'), findsWidgets);
    });

    testWidgets('shows wellen entry', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('wellen'), findsOneWidget);
    });

    testWidgets('shows Flutter entry', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Flutter'), findsOneWidget);
    });

    testWidgets('shows flutter_riverpod / riverpod entry', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('flutter_riverpod / riverpod'), findsOneWidget);
    });

    testWidgets('shows license badges', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      // BSD 3-Clause appears for multiple entries.
      expect(find.text('BSD 3-Clause'), findsWidgets);
    });

    testWidgets('shows MIT license badge', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('MIT'), findsWidgets);
    });

    testWidgets('shows back navigation button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  // ── responsive sizes ────────────────────────────────────────────────────────

  group('responsive surface sizes', () {
    for (final entry in [
      ('phone', const Size(400, 800)),
      ('tablet', const Size(800, 1024)),
      ('desktop', const Size(1400, 900)),
    ]) {
      testWidgets('renders without overflow on ${entry.$1}', (tester) async {
        tester.view.physicalSize = entry.$2;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── interaction ─────────────────────────────────────────────────────────────

  group('interaction', () {
    testWidgets('back button pops the route', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const AboutAcknowledgmentsScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('wellen'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('wellen'), findsNothing);
    });
  });
}
