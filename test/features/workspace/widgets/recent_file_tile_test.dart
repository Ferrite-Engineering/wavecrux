// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/workspace/widgets/recent_file_tile.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Widget child, {Locale? locale}) {
  return MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  );
}

void main() {
  group('RecentFileTile — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await tester.pumpWidget(
          _wrap(
            RecentFileTile(
              filePath: '/home/user/signals.vcd',
              onTap: () {},
              onRemove: () {},
            ),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('RecentFileTile — content', () {
    testWidgets('shows basename from POSIX path', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecentFileTile(
            filePath: '/home/user/projects/dump.fst',
            onTap: () {},
            onRemove: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('dump.fst'), findsOneWidget);
    });

    testWidgets('shows full path in secondary line', (tester) async {
      const path = '/home/user/projects/dump.fst';
      await tester.pumpWidget(
        _wrap(
          RecentFileTile(
            filePath: path,
            onTap: () {},
            onRemove: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text(path), findsOneWidget);
    });
  });

  group('RecentFileTile — interactions', () {
    testWidgets('calls onTap when row is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          RecentFileTile(
            filePath: '/a/b.vcd',
            onTap: () => tapped = true,
            onRemove: () {},
          ),
        ),
      );
      await tester.pump();
      // first InkWell is the outermost row; the second is internal to InkWell
      await tester.tap(find.byType(InkWell).first);
      expect(tapped, isTrue);
    });

    testWidgets('calls onRemove when close button is tapped', (tester) async {
      var removed = false;
      await tester.pumpWidget(
        _wrap(
          RecentFileTile(
            filePath: '/a/b.vcd',
            onTap: () {},
            onRemove: () => removed = true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(IconButton));
      expect(removed, isTrue);
    });
  });
}
