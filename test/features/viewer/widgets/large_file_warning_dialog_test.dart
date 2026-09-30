// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/widgets/large_file_warning_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── helpers ───────────────────────────────────────────────────────────────

Widget _app({Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  home: const Scaffold(
    body: LargeFileWarningDialog(fileSizeMb: '150.3', thresholdMb: '100'),
  ),
);

Future<bool?> _showAndTap(
  WidgetTester tester,
  String buttonText,
) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            result = await LargeFileWarningDialog.show(
              ctx,
              fileSizeBytes: 150 * 1024 * 1024,
              thresholdBytes: 100 * 1024 * 1024,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(buttonText));
  await tester.pumpAndSettle();
  return result;
}

// ── tests ─────────────────────────────────────────────────────────────────

void main() {
  group('LargeFileWarningDialog', () {
    // ── Locale sweep ────────────────────────────────────────────────────────

    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('locale sweep — no exception in $locale', (tester) async {
        await tester.pumpWidget(_app(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // ── Static structure ────────────────────────────────────────────────────

    testWidgets('shows a title', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      // Title widget is rendered (exact text is locale-dependent; check type)
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('shows the file size in the body', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      // Both the file size (150.3) and threshold (100) should appear somewhere.
      expect(find.textContaining('150.3'), findsWidgets);
      expect(find.textContaining('100'), findsWidgets);
    });

    testWidgets('shows a FilledButton for load-anyway action', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows a cancel TextButton', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.byType(TextButton), findsAtLeastNWidgets(1));
    });

    // ── show() return values ────────────────────────────────────────────────

    testWidgets('show() returns true when Load Anyway is tapped', (
      tester,
    ) async {
      final result = await _showAndTap(tester, 'Load Anyway');
      expect(result, isTrue);
    });

    testWidgets('show() returns false when Cancel is tapped', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await LargeFileWarningDialog.show(
                  ctx,
                  fileSizeBytes: 150 * 1024 * 1024,
                  thresholdBytes: 100 * 1024 * 1024,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Find the cancel button by its localized label inside the dialog.
      final cancelFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      );
      await tester.tap(cancelFinder.first);
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    // ── show() byte → MB conversion ─────────────────────────────────────────

    testWidgets('show() converts bytes to MB for display', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => LargeFileWarningDialog.show(
                ctx,
                fileSizeBytes: 157_286_400, // 150.0 MB
                thresholdBytes: 104_857_600, // 100 MB
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('150.0'), findsWidgets);
      expect(find.textContaining('100'), findsWidgets);
    });
  });
}
