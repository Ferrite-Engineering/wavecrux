// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/experimental_chip.dart';

Widget _wrap(Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  home: const Scaffold(body: Center(child: ExperimentalChip())),
);

void main() {
  const locales = [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ko'),
  ];

  for (final locale in locales) {
    testWidgets('renders without exception in $locale', (tester) async {
      await tester.pumpWidget(_wrap(locale));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ExperimentalChip), findsOneWidget);
      // The localized label resolves to non-empty text.
      final l10n = await L10N.delegate.load(locale);
      expect(find.text(l10n.experimentalChipLabel), findsOneWidget);
      expect(l10n.experimentalChipLabel, isNotEmpty);
    });
  }
}
