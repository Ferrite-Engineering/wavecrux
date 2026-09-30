// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/features/viewer/widgets/translator_child_row.dart';
import 'package:wavecrux/features/viewer/widgets/value_color_swatch.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('renders the field name and value at the given height', (
    tester,
  ) async {
    await _pump(
      tester,
      const TranslatorChildRow(
        field: TranslatedField(
          name: 'AxBURST',
          text: 'INCR',
          hiBit: 1,
          loBit: 0,
        ),
        height: 18,
      ),
    );
    expect(find.text('AxBURST'), findsOneWidget);
    expect(find.text('INCR'), findsOneWidget);
    expect(tester.getSize(find.byType(TranslatorChildRow)).height, 18);
  });

  testWidgets('a null field renders an empty placeholder of the same height', (
    tester,
  ) async {
    await _pump(tester, const TranslatorChildRow(field: null, height: 18));
    expect(tester.getSize(find.byType(TranslatorChildRow)).height, 18);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders a per-channel swatch when the field carries a colour', (
    tester,
  ) async {
    await _pump(
      tester,
      const TranslatorChildRow(
        field: TranslatedField(
          name: 'R',
          text: '255',
          hiBit: 15,
          loBit: 11,
          colorArgb: 0xFFFF0000,
        ),
        height: 18,
      ),
    );
    expect(find.byType(ValueColorSwatch), findsOneWidget);
    final decoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('value_color_swatch')),
                )
                .decoration!
            as BoxDecoration;
    expect(decoration.color, const Color(0xFFFF0000));
  });

  testWidgets('renders no swatch when the field has no colour hint', (
    tester,
  ) async {
    await _pump(
      tester,
      const TranslatorChildRow(
        field: TranslatedField(
          name: 'AxBURST',
          text: 'INCR',
          hiBit: 1,
          loBit: 0,
        ),
        height: 18,
      ),
    );
    expect(find.byType(ValueColorSwatch), findsNothing);
  });
}
