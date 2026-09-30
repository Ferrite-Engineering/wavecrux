// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/features/settings/widgets/custom_translator_editor_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Future<CustomTranslatorDef?> _open(
  WidgetTester tester, {
  CustomTranslatorDef? initial,
  Locale locale = const Locale('en'),
}) async {
  CustomTranslatorDef? result;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await CustomTranslatorEditorDialog.show(
                context,
                initial: initial,
              );
            },
            child: const Text('open'),
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
  testWidgets('requires a name before saving', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('A name is required.'), findsOneWidget);
    // Dialog stays open.
    expect(find.text('New Translator'), findsOneWidget);
  });

  testWidgets('edits an existing translator with its fields pre-filled', (
    tester,
  ) async {
    await _open(
      tester,
      initial: const CustomTranslatorDef(
        name: 'AXI',
        config: BitfieldTranslatorConfig(
          fields: [
            BitFieldSpec(name: 'size', hiBit: 2, loBit: 0),
          ],
        ),
      ),
    );
    expect(find.text('Edit Translator'), findsOneWidget);
    expect(find.text('AXI'), findsOneWidget);
    // Add-field control is present.
    expect(find.text('Add Field'), findsOneWidget);
  });

  testWidgets('dirty cancel prompts to discard; keep editing stays open', (
    tester,
  ) async {
    await _open(tester);
    // Dirty the form.
    await tester.enterText(
      find.byType(TextField).first,
      'AXI',
    );
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
    expect(find.text('New Translator'), findsOneWidget);
    expect(find.text('AXI'), findsOneWidget);

    // "Discard" closes the editor.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editorDiscardConfirmDiscard')),
    );
    await tester.pumpAndSettle();
    expect(find.text('New Translator'), findsNothing);
  });

  testWidgets('clean cancel closes without a prompt', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('New Translator'), findsNothing);
  });

  testWidgets('locale sweep opens the editor without exceptions', (
    tester,
  ) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await _open(tester, locale: locale);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Dismiss via Cancel before the next locale so routes don't stack —
      // editor dialogs are barrier-non-dismissible (suite dialog canon).
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
    }
  });
}
