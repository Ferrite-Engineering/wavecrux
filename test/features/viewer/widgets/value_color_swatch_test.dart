// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/widgets/value_color_swatch.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('fills the chip with the given ARGB colour at the given size', (
    tester,
  ) async {
    await _pump(tester, const ValueColorSwatch(colorArgb: 0xFFFF0000));
    final finder = find.byKey(const ValueKey('value_color_swatch'));
    expect(finder, findsOneWidget);
    // Default chip size is 12 dp square.
    expect(tester.getSize(finder), const Size(12, 12));

    final container = tester.widget<Container>(finder);
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFFF0000));
  });

  testWidgets('honours a custom size', (tester) async {
    await _pump(tester, const ValueColorSwatch(colorArgb: 0xFF00FF00, size: 9));
    expect(
      tester.getSize(find.byKey(const ValueKey('value_color_swatch'))),
      const Size(9, 9),
    );
  });
}
