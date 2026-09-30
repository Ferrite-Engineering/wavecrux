// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/named_enum_editor_dialog.dart';

Widget _harness(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  );
}

/// Opens the dialog via [NamedEnumEditorDialog.show] and leaves [tester] with
/// the dialog on screen. Returns the [Future] from show() via [resultHolder].
Future<void> _openDialog(
  WidgetTester tester, {
  Map<String, Object?>? config,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    _harness(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => NamedEnumEditorDialog.show(ctx, config: config),
          child: const Text('open'),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('NamedEnumEditorDialog — rendering', () {
    testWidgets('shows an AlertDialog when opened empty', (tester) async {
      await _openDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('shows existing entries as rows when config is provided', (
      tester,
    ) async {
      final config = NamedEnumConfig(
        entries: [
          NamedEnumEntry(value: BigInt.zero, label: 'IDLE'),
          NamedEnumEntry(value: BigInt.one, label: 'ACTIVE'),
        ],
      ).toMap();
      await _openDialog(tester, config: config);

      // Each entry renders its label in a TextFormField.
      expect(find.widgetWithText(TextFormField, 'IDLE'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'ACTIVE'), findsOneWidget);
    });

    testWidgets('add button appends a new row', (tester) async {
      await _openDialog(tester);

      // Initially empty → 0 TextFormFields visible in the list.
      final beforeAdd = tester.widgetList(find.byType(TextFormField)).length;

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final afterAdd = tester.widgetList(find.byType(TextFormField)).length;
      expect(afterAdd, greaterThan(beforeAdd));
    });

    testWidgets('delete button removes a row', (tester) async {
      final config = NamedEnumConfig(
        entries: [
          NamedEnumEntry(value: BigInt.zero, label: 'A'),
          NamedEnumEntry(value: BigInt.one, label: 'B'),
        ],
      ).toMap();
      await _openDialog(tester, config: config);

      final beforeDelete = tester.widgetList(find.byType(TextFormField)).length;
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      final afterDelete = tester.widgetList(find.byType(TextFormField)).length;
      expect(afterDelete, lessThan(beforeDelete));
    });
  });

  group('NamedEnumEditorDialog — OK button state', () {
    testWidgets('OK is enabled when all value fields are valid integers', (
      tester,
    ) async {
      final config = NamedEnumConfig(
        entries: [
          NamedEnumEntry(value: BigInt.zero, label: 'IDLE'),
        ],
      ).toMap();
      await _openDialog(tester, config: config);

      final okButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(okButton.onPressed, isNotNull);
    });

    testWidgets('OK is disabled when a value field contains a non-integer', (
      tester,
    ) async {
      final config = NamedEnumConfig(
        entries: [
          NamedEnumEntry(value: BigInt.zero, label: 'IDLE'),
        ],
      ).toMap();
      await _openDialog(tester, config: config);

      // Edit the value field to an invalid string.
      final valueField = find.byType(TextFormField).first;
      await tester.enterText(valueField, 'notanumber');
      await tester.pumpAndSettle();

      final okButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(okButton.onPressed, isNull);
    });

    testWidgets('OK re-enables after correcting an invalid value', (
      tester,
    ) async {
      final config = NamedEnumConfig(
        entries: [
          NamedEnumEntry(value: BigInt.zero, label: 'X'),
        ],
      ).toMap();
      await _openDialog(tester, config: config);

      final valueField = find.byType(TextFormField).first;
      await tester.enterText(valueField, 'bad');
      await tester.pumpAndSettle();

      await tester.enterText(valueField, '42');
      await tester.pumpAndSettle();

      final okButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(okButton.onPressed, isNotNull);
    });
  });

  group('NamedEnumEditorDialog — cancel', () {
    testWidgets('returns null when Cancel is tapped', (tester) async {
      Map<String, Object?>? result = const {'sentinel': true};

      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await NamedEnumEditorDialog.show(ctx);
              },
              child: const Text('open'),
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
  });

  group('NamedEnumEditorDialog — dirty-cancel guard', () {
    testWidgets('dirty cancel prompts to discard; keep editing stays open', (
      tester,
    ) async {
      final config = NamedEnumConfig(
        entries: [
          NamedEnumEntry(value: BigInt.zero, label: 'IDLE'),
        ],
      ).toMap();
      await _openDialog(tester, config: config);

      // Dirty the form by editing a label.
      await tester.enterText(find.byType(TextFormField).last, 'BUSY');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // "Keep editing" returns to the editor with input intact.
      await tester.tap(
        find.byKey(const ValueKey('editorDiscardConfirmKeepEditing')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'BUSY'), findsOneWidget);

      // "Discard" closes the editor.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editorDiscardConfirmDiscard')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('clean cancel closes without a prompt', (tester) async {
      await _openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('NamedEnumEditorDialog — OK result', () {
    testWidgets('returns non-null map with correct entries on OK', (
      tester,
    ) async {
      Map<String, Object?>? result;

      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await NamedEnumEditorDialog.show(
                  ctx,
                  config: NamedEnumConfig(
                    entries: [
                      NamedEnumEntry(value: BigInt.zero, label: 'IDLE'),
                      NamedEnumEntry(value: BigInt.one, label: 'ACTIVE'),
                    ],
                  ).toMap(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      final restored = NamedEnumConfig.fromMap(result!);
      expect(restored.entries, hasLength(2));
      expect(restored.entries[0].value, BigInt.zero);
      expect(restored.entries[0].label, 'IDLE');
      expect(restored.entries[1].value, BigInt.one);
      expect(restored.entries[1].label, 'ACTIVE');
    });

    testWidgets(
      'returns empty-entry config when all rows deleted and OK tapped',
      (tester) async {
        Map<String, Object?>? result;

        await tester.pumpWidget(
          _harness(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await NamedEnumEditorDialog.show(
                    ctx,
                    config: NamedEnumConfig(
                      entries: [
                        NamedEnumEntry(value: BigInt.zero, label: 'X'),
                      ],
                    ).toMap(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Delete the single row.
        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        final restored = NamedEnumConfig.fromMap(result!);
        expect(restored.entries, isEmpty);
      },
    );
  });

  group('NamedEnumEditorDialog — locale sweep', () {
    const locales = [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];

    for (final locale in locales) {
      testWidgets('renders without exception in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await _openDialog(tester, locale: locale);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'NamedEnumEditorDialog raised in ${locale.toLanguageTag()}',
        );
      });
    }
  });
}
