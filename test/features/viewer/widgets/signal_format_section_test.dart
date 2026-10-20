// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/inspector_openers.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/widgets/signal_format_section.dart';
import 'package:wavecrux/features/viewer/widgets/wavecrux_inspector_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/inspector_test_host.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// Adds a row for [path] in [format] and returns its id.
String _addRow(
  ProviderContainer container,
  String path,
  DisplayFormat format, {
  Map<String, Object?>? config,
}) {
  final groups = container.read(signalGroupsProvider.notifier)
    ..addSignal(inspectorTestVar(path, bitWidth: 16));
  final entry = container.read(signalGroupsProvider).entries.last;
  groups.setSignalFormatById(entry.id, format);
  if (config != null) groups.setSignalTranslatorConfigById(entry.id, config);
  return entry.id;
}

SignalEntry _row(ProviderContainer container, String id) =>
    findSignalEntry(container.read(signalGroupsProvider).entries, id)!;

Future<void> _inspect(
  WidgetTester tester,
  ProviderContainer container,
  String id,
) async {
  openWaveCruxInspector(
    tester.element(find.byType(Scaffold)),
    container,
    InspectedSignal(id),
  );
  await tester.pumpAndSettle();
}

Finder get _apply => find.descendant(
  of: find.byType(CruxInspectorApplyBar),
  matching: find.byType(FilledButton),
);

L10N _l10n(WidgetTester tester) =>
    L10N.of(tester.element(find.byType(SignalFormatSection)));

void main() {
  group('a fixed-point row', () {
    for (final locale in _locales) {
      testWidgets('renders in ${locale.toLanguageTag()}', (tester) async {
        final container = await pumpInspectorHost(tester, locale: locale);
        final id = _addRow(container, 'tb.q', DisplayFormat.fixedPointQ);
        await _inspect(tester, container, id);
        expect(tester.takeException(), isNull);
        expect(find.byType(SignalFormatSection), findsOneWidget);
      });
    }

    testWidgets('shows the row and its knobs, applies them together on '
        'Apply', (tester) async {
      final container = await pumpInspectorHost(tester);
      final id = _addRow(container, 'tb.q', DisplayFormat.fixedPointQ);
      await _inspect(tester, container, id);
      final l10n = _l10n(tester);
      expect(find.text('tb.q'), findsWidgets);
      expect(find.text(l10n.qFormatConfigTitle), findsOneWidget);
      expect(find.text(l10n.namedEnumEditorTitle), findsNothing);
      expect(tester.widget<FilledButton>(_apply).onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      // Nothing written until Apply.
      expect(_row(container, id).translatorConfig, isNull);
      await tester.tap(_apply);
      await tester.pumpAndSettle();
      expect(_row(container, id).translatorConfig, {
        'm': 7,
        'n': 8,
        'signed': false,
      });
      expect(container.read(signalFormatDraftsProvider), isEmpty);
    });

    testWidgets('an unapplied change holds the row when another is chosen', (
      tester,
    ) async {
      final container = await pumpInspectorHost(tester);
      final first = _addRow(container, 'tb.q', DisplayFormat.fixedPointQ);
      final second = _addRow(container, 'tb.r', DisplayFormat.hexadecimal);
      await _inspect(tester, container, first);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      container
          .read(inspectedObjectProvider.notifier)
          .select(InspectedSignal(second));
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);
      expect(find.text(l10n.inspectorHeldMessage('q')), findsOneWidget);

      await tester.tap(find.text(l10n.inspectorRevert));
      await tester.pumpAndSettle();
      // Reverted: the Inspector follows the selection to the second row,
      // which has no knobs.
      expect(find.text(l10n.qFormatConfigTitle), findsNothing);
      expect(find.text('tb.r'), findsWidgets);
    });
  });

  group('a named-enum row', () {
    testWidgets('edits the label table and refuses an invalid value', (
      tester,
    ) async {
      final container = await pumpInspectorHost(tester);
      final id = _addRow(
        container,
        'tb.state',
        DisplayFormat.namedEnum,
        config: NamedEnumConfig(
          entries: [NamedEnumEntry(value: BigInt.zero, label: 'IDLE')],
        ).toMap(),
      );
      await _inspect(tester, container, id);
      final l10n = _l10n(tester);
      expect(find.text(l10n.namedEnumEditorTitle), findsOneWidget);
      expect(find.widgetWithText(TextField, 'IDLE'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      final valueFields = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == l10n.namedEnumEditorValueHeader,
      );
      await tester.enterText(valueFields.last, 'x');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_apply).onPressed, isNull);

      await tester.enterText(valueFields.last, '1');
      final labelFields = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == l10n.namedEnumEditorLabelHeader,
      );
      await tester.enterText(labelFields.last, 'BUSY');
      await tester.pumpAndSettle();
      await tester.tap(_apply);
      await tester.pumpAndSettle();
      final saved = NamedEnumConfig.fromMap(
        _row(container, id).translatorConfig!,
      );
      expect(saved.entries.map((e) => e.label), ['IDLE', 'BUSY']);
    });
  });

  testWidgets('a row that is removed empties the Inspector', (tester) async {
    final container = await pumpInspectorHost(tester);
    final id = _addRow(container, 'tb.q', DisplayFormat.fixedPointQ);
    await _inspect(tester, container, id);
    container.read(signalGroupsProvider.notifier).clear();
    await tester.pumpAndSettle();
    final l10n = L10N.of(tester.element(find.byType(WaveCruxInspectorPanel)));
    expect(find.text(l10n.inspectorEmpty), findsOneWidget);
  });

  testWidgets('on iOS and Android the same sections open in a bottom sheet', (
    tester,
  ) async {
    final container = await pumpInspectorHost(
      tester,
      showInspector: false,
      inSheet: true,
    );
    final id = _addRow(container, 'tb.q', DisplayFormat.fixedPointQ);
    await _inspect(tester, container, id);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(SignalFormatSection),
      ),
      findsOneWidget,
    );
    // Applied from the sheet, written to the tab.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_apply);
    await tester.pumpAndSettle();
    await tester.tap(_apply);
    await tester.pumpAndSettle();
    expect(_row(container, id).translatorConfig?['signed'], isFalse);
  });
}
