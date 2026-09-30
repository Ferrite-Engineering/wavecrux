// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/features/workspace/widgets/wavecrux_empty_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  Widget harness(Locale locale) => MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => crux.CruxSuiteFooter(
          label: L10N.of(context).emptyCanvasSuiteFooter,
          onTap: () => suiteSiteLaunchUrl(Uri.parse(HelpUrls.suiteHome)),
        ),
      ),
    ),
  );

  // Replaced per file, as every other seam-using suite here does: each test
  // file runs in its own isolate, so the production `launchUrl` is never
  // reached and there is nothing to restore.
  final opened = <Uri>[];
  setUp(() {
    opened.clear();
    suiteSiteLaunchUrl = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  testWidgets('every locale keeps the linked domain verbatim', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await tester.pumpWidget(harness(locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'locale $locale');

      final rendered = tester
          .widget<Text>(find.byType(Text))
          .textSpan!
          .toPlainText();
      // The widget splits the sentence around this literal to underline it.
      // A translation that paraphrased or localized the domain would render
      // the line with nothing to click, which is not a visible failure.
      expect(
        rendered,
        contains(crux.CruxSuiteFooter.defaultLinkText),
        reason: 'locale $locale dropped the linked domain',
      );
      expect(rendered, contains('EDACrux'), reason: 'locale $locale');
    }
  });

  testWidgets('following the line opens this product’s landing path', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const Locale('en')));
    await tester.tap(find.byKey(crux.CruxSuiteFooter.rowKey));
    await tester.pumpAndSettle();

    // Per-product path, not the shared `/products` page: the site's page-view
    // beacon records the path and drops the query string, so this segment is
    // the only thing that attributes the visit to WaveCrux.
    expect(opened, [Uri.parse('https://edacrux.app/from/wavecrux')]);
  });

  group('More from EDACrux', () {
    Widget peersHarness(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(body: WaveCruxSuitePeers()),
    );

    testWidgets('offers the other three, and never WaveCrux itself', (
      tester,
    ) async {
      await tester.pumpWidget(peersHarness(const Locale('en')));
      await tester.pumpAndSettle();

      for (final peer in crux.CruxSuiteProduct.waveCrux.peers) {
        expect(
          find.byKey(crux.CruxSuitePeers.rowKeyFor(peer)),
          findsOneWidget,
          reason: '${peer.displayName} row missing',
        );
      }
      expect(
        find.byKey(
          crux.CruxSuitePeers.rowKeyFor(crux.CruxSuiteProduct.waveCrux),
        ),
        findsNothing,
      );
    });

    testWidgets('a row lands on that product\u2019s card', (tester) async {
      await tester.pumpWidget(peersHarness(const Locale('en')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          crux.CruxSuitePeers.rowKeyFor(crux.CruxSuiteProduct.lintCrux),
        ),
      );
      await tester.pumpAndSettle();

      // Same attributable path as the footer, plus a fragment the site's
      // beacon drops before sending — so the reader lands on LintCrux's card
      // and the visit is still recorded against WaveCrux.
      expect(opened, [Uri.parse('https://edacrux.app/from/wavecrux#lintcrux')]);
    });

    testWidgets('every locale names all three products', (tester) async {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        await tester.pumpWidget(peersHarness(locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'locale $locale');
        for (final peer in crux.CruxSuiteProduct.waveCrux.peers) {
          // Product names are never translated, so each row must still
          // carry its name verbatim in every locale.
          expect(
            find.text(peer.displayName),
            findsOneWidget,
            reason: '$locale dropped ${peer.displayName}',
          );
        }
      }
    });
  });
}
