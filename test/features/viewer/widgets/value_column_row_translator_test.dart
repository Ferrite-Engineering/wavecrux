// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/widgets/translator_child_row.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/value_format/bitfield_translator.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

SignalEntry _entry() => SignalEntry.signal(
  signalRef: 'r',
  displayName: 'bus',
  translatorConfig: {
    ...const BitfieldTranslatorConfig(
      fields: [
        BitFieldSpec(name: 'hi', hiBit: 7, loBit: 4),
        BitFieldSpec(name: 'lo', hiBit: 3, loBit: 0),
      ],
    ).toMap(),
    kTranslatorIdConfigKey: BitfieldTranslator.translatorId,
  },
);

/// An inline-only translator: produces fields but is NOT a
/// [ChildRowTranslator], so it reserves no child rows (mirrors RISC-V
/// disassembly). The value column must not render an expand chevron for it.
class _InlineTranslator implements Translator {
  const _InlineTranslator();
  static const String translatorId = 'fake.inline';
  @override
  String get id => translatorId;
  @override
  TranslationResult translate(TranslationRequest request) =>
      const TranslationResult(text: 'addi x1, x0, 5');
}

SignalEntry _inlineEntry() => SignalEntry.signal(
  signalRef: 'r2',
  displayName: 'instr',
  translatorConfig: const {
    kTranslatorIdConfigKey: _InlineTranslator.translatorId,
  },
);

/// A value that *does* carry fields — proves the chevron is gated on the
/// translator's static child-row capacity, not on `fields.isNotEmpty`.
const _inlineValue = SignalValue(
  formatted: 'addi x1, x0, 5',
  rawValue: '00000000010100000000000010010011',
  fields: [
    TranslatedField(name: 'mnemonic', text: 'addi', hiBit: 31, loBit: 0),
    TranslatedField(name: 'op0', text: 'x1', hiBit: 31, loBit: 0),
  ],
);

const _value = SignalValue(
  formatted: '{hi=a, lo=b}',
  rawValue: '10101011',
  fields: [
    TranslatedField(name: 'hi', text: 'a', hiBit: 7, loBit: 4),
    TranslatedField(name: 'lo', text: 'b', hiBit: 3, loBit: 0),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required int childRows,
  Locale locale = const Locale('en'),
  SignalEntry? entry,
  SignalValue? value,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceClassProvider.overrideWithValue(DeviceClass.phone),
        ...extraOverrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ValueColumnRow(
              entry: entry ?? _entry(),
              signalValue: value ?? _value,
              childRows: childRows,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('expand affordance meets the 44x44 touch target on touch', (
    tester,
  ) async {
    await _pump(tester, childRows: 0);
    final affordance = find.byKey(
      const ValueKey('translator_expand_affordance'),
    );
    expect(affordance, findsOneWidget);
    final size = tester.getSize(affordance);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('expanded row renders one child row per subfield', (
    tester,
  ) async {
    await _pump(tester, childRows: 2);
    expect(find.byType(TranslatorChildRow), findsNWidgets(2));
    expect(find.text('hi'), findsOneWidget);
    expect(find.text('lo'), findsOneWidget);
  });

  testWidgets('collapsed row shows no child rows', (tester) async {
    await _pump(tester, childRows: 0);
    expect(find.byType(TranslatorChildRow), findsNothing);
  });

  testWidgets(
    'inline-only translator (not a ChildRowTranslator) shows NO expand '
    'chevron even when the value carries fields',
    (tester) async {
      await _pump(
        tester,
        childRows: 0,
        entry: _inlineEntry(),
        value: _inlineValue,
        extraOverrides: [
          // Register the inline translator through the same registry seam the
          // real ones use, so it resolves to a non-ChildRowTranslator.
          extraTranslatorsProvider.overrideWithValue(
            const [_InlineTranslator()],
          ),
        ],
      );
      // The disassembly renders inline...
      expect(find.text('addi x1, x0, 5'), findsOneWidget);
      // ...but no dead chevron, because the translator reserves no child rows.
      expect(
        find.byKey(const ValueKey('translator_expand_affordance')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a ChildRowTranslator-backed signal still shows the chevron (bitfield)',
    (tester) async {
      await _pump(tester, childRows: 0);
      expect(
        find.byKey(const ValueKey('translator_expand_affordance')),
        findsOneWidget,
      );
    },
  );

  testWidgets('locale sweep renders without exceptions', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await _pump(tester, childRows: 2, locale: locale);
      expect(tester.takeException(), isNull);
    }
  });
}
