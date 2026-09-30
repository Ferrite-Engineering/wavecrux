// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/workspace/widgets/empty_canvas_docs_hint.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  Widget harness(Locale locale, {VoidCallback? onTap}) => MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: Center(child: EmptyCanvasDocsHint(onTap: onTap)),
    ),
  );

  testWidgets('renders without exception across the four locales', (
    tester,
  ) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await tester.pumpWidget(harness(locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'locale $locale');
      expect(find.byType(EmptyCanvasDocsHint), findsOneWidget);
    }
  });

  testWidgets('tapping the docs.wavecrux.app link invokes onTap', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      harness(const Locale('en'), onTap: () => tapped = true),
    );
    await tester.pumpAndSettle();

    // Only the domain span carries the recognizer — tapping it (not the
    // surrounding prose) fires the link.
    await tester.tapOnText(find.textRange.ofSubstring('docs.wavecrux.app'));
    expect(tapped, isTrue);
  });

  testWidgets('the localized prose is present alongside the link', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const Locale('en')));
    await tester.pumpAndSettle();
    // The whole hint, including the linked domain, renders as one rich text.
    expect(
      find.textContaining('Need help getting started?'),
      findsOneWidget,
    );
  });
}
