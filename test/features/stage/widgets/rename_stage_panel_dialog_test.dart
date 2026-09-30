// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/widgets/rename_stage_panel_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Future<String?> _openDialog(
  WidgetTester tester, {
  required String initialName,
  required String titleText,
  Locale locale = const Locale('en'),
}) async {
  String? result;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await RenameStagePanelDialog.show(
                  context,
                  initialName: initialName,
                  titleText: titleText,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('RenameStagePanelDialog — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await _openDialog(
          tester,
          initialName: 'Old',
          titleText: 'Title',
          locale: Locale(locale),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    }
  });

  group('RenameStagePanelDialog — confirm', () {
    testWidgets('returns trimmed entered text on OK', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await RenameStagePanelDialog.show(
                      context,
                      initialName: 'Old',
                      titleText: 'Rename',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Replace text and confirm.
      await tester.enterText(find.byType(TextField), '  Bus Monitor  ');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, 'Bus Monitor');
    });

    testWidgets('Cancel returns null', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await RenameStagePanelDialog.show(
                      context,
                      initialName: 'Old',
                      titleText: 'Rename',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('confirming with whitespace-only text returns null', (
      tester,
    ) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await RenameStagePanelDialog.show(
                      context,
                      initialName: 'Old',
                      titleText: 'Rename',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
