// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/help_link.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('HelpLink', () {
    testWidgets('renders help_outline icon', (tester) async {
      await tester.pumpWidget(
        _wrap(const HelpLink(url: 'https://example.com')),
      );
      await tester.pump();

      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(HelpLink(url: 'https://example.com', onTap: () => tapped = true)),
      );
      await tester.pump();

      await tester.tap(find.byType(HelpLink));
      expect(tapped, isTrue);
    });

    testWidgets('uses custom tooltip when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HelpLink(
            url: 'https://example.com',
            tooltip: 'Custom tip',
          ),
        ),
      );
      await tester.pump();

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Custom tip');
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses localised "Learn more" tooltip by default (en)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const HelpLink(url: 'https://example.com')),
      );
      await tester.pump();

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Learn more');
      expect(tester.takeException(), isNull);
    });

    // ── locale sweep ──────────────────────────────────────────────────────────

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without error in locale $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(const HelpLink(url: 'https://example.com'), locale: locale),
        );
        await tester.pump();

        expect(find.byIcon(Icons.help_outline), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('onTap is not called when not tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(HelpLink(url: 'https://example.com', onTap: () => tapped = true)),
      );
      await tester.pump();

      expect(tapped, isFalse);
    });

    testWidgets('wraps icon in InkWell for tap feedback', (tester) async {
      await tester.pumpWidget(
        _wrap(const HelpLink(url: 'https://example.com')),
      );
      await tester.pump();

      expect(find.byType(InkWell), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });
  });
}
