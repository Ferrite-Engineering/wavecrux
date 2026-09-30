// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/widgets/signal_group_header.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Widget child, {Locale? locale}) => MaterialApp(
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  locale: locale,
  home: Scaffold(body: child),
);

void main() {
  group('SignalGroupHeader', () {
    for (final locale in _locales) {
      testWidgets('locale sweep — renders in $locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            SignalGroupHeader(
              groupName: 'AXI',
              signalCount: 3,
              collapsed: false,
              onToggleCollapsed: () {},
            ),
            locale: locale,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('displays group name', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalGroupHeader(
            groupName: 'Control',
            signalCount: 2,
            collapsed: false,
            onToggleCollapsed: () {},
          ),
        ),
      );
      expect(find.text('Control'), findsOneWidget);
    });

    testWidgets('shows expand_more icon when expanded', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalGroupHeader(
            groupName: 'G',
            signalCount: 1,
            collapsed: false,
            onToggleCollapsed: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('shows chevron_right icon when collapsed', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalGroupHeader(
            groupName: 'G',
            signalCount: 1,
            collapsed: true,
            onToggleCollapsed: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('shows signal count badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalGroupHeader(
            groupName: 'G',
            signalCount: 5,
            collapsed: false,
            onToggleCollapsed: () {},
          ),
        ),
      );
      expect(find.text('5 signals'), findsOneWidget);
    });

    testWidgets('singular count shows "1 signal"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalGroupHeader(
            groupName: 'G',
            signalCount: 1,
            collapsed: false,
            onToggleCollapsed: () {},
          ),
        ),
      );
      expect(find.text('1 signal'), findsOneWidget);
    });

    testWidgets('tapping fires onToggleCollapsed callback', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          SignalGroupHeader(
            groupName: 'G',
            signalCount: 2,
            collapsed: false,
            onToggleCollapsed: () => tapped++,
          ),
        ),
      );
      await tester.tap(find.byType(SignalGroupHeader));
      expect(tapped, 1);
    });
  });
}
