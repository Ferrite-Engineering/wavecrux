// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/features/settings/providers/custom_translators_provider.dart';
import 'package:wavecrux/features/settings/widgets/custom_translators_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  List<CustomTranslatorDef> seed = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (seed.isNotEmpty)
          customTranslatorsProvider.overrideWith(
            () => _SeededTranslators(seed),
          ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: CustomTranslatorsPanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SeededTranslators extends CustomTranslators {
  _SeededTranslators(this._seed);
  final List<CustomTranslatorDef> _seed;
  @override
  List<CustomTranslatorDef> build() => _seed;
}

void main() {
  testWidgets('shows empty state and add button when no translators', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('No custom translators yet.'), findsOneWidget);
    expect(find.text('Add Translator'), findsOneWidget);
  });

  testWidgets('lists authored translators with field counts', (tester) async {
    await _pump(
      tester,
      seed: const [
        CustomTranslatorDef(
          name: 'AXI ARSIZE',
          config: BitfieldTranslatorConfig(
            fields: [
              BitFieldSpec(name: 'size', hiBit: 2, loBit: 0),
            ],
          ),
        ),
      ],
    );
    expect(find.text('AXI ARSIZE'), findsOneWidget);
    expect(find.text('1 field'), findsOneWidget);
  });

  testWidgets('opens the editor dialog when Add is tapped', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Add Translator'));
    await tester.pumpAndSettle();
    expect(find.text('New Translator'), findsOneWidget);
  });

  testWidgets('insets its content to align with the surrounding card rows', (
    tester,
  ) async {
    await _pump(tester);
    // The panel wraps its column in a 16/12 inset so the description and
    // button line up with the ListTile rows of the enclosing settings card,
    // matching the other settings sections. Without it the text/button hug
    // the card edge (the reported visual bug).
    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(CustomTranslatorsPanel),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(16, 12, 16, 12));
  });

  testWidgets('locale sweep renders without exceptions', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await _pump(
        tester,
        locale: locale,
        seed: const [
          CustomTranslatorDef(
            name: 'demo',
            config: BitfieldTranslatorConfig(
              fields: [
                BitFieldSpec(name: 'a', hiBit: 1, loBit: 0),
                BitFieldSpec(name: 'b', hiBit: 3, loBit: 2),
              ],
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
    }
  });
}
