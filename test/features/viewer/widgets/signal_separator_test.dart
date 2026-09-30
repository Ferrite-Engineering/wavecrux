// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/widgets/signal_separator.dart';
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
  group('SignalSeparator — blank separator', () {
    for (final locale in _locales) {
      testWidgets('locale sweep — renders in $locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const SignalSeparator(isComment: false), locale: locale),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders a 10px-tall row', (tester) async {
      await tester.pumpWidget(
        _wrap(const SignalSeparator(isComment: false)),
      );
      final sizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(Container),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sizedBox.height, 10);
    });
  });

  group('SignalSeparator — comment row', () {
    for (final locale in _locales) {
      testWidgets('locale sweep — renders in $locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            SignalSeparator(
              isComment: true,
              commentText: 'Clock signals',
              onCommentChanged: (_) {},
            ),
            locale: locale,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('displays comment text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalSeparator(
            isComment: true,
            commentText: 'AXI bus',
            onCommentChanged: (_) {},
          ),
        ),
      );
      expect(find.text('AXI bus'), findsOneWidget);
    });

    testWidgets('shows dash when comment text is empty', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalSeparator(
            isComment: true,
            commentText: '',
            onCommentChanged: (_) {},
          ),
        ),
      );
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('tapping edit icon enters editing mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SignalSeparator(
            isComment: true,
            commentText: 'old text',
            onCommentChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit_note));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('submitting text calls onCommentChanged', (tester) async {
      String? committed;
      await tester.pumpWidget(
        _wrap(
          SignalSeparator(
            isComment: true,
            commentText: 'old',
            onCommentChanged: (t) => committed = t,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit_note));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'new text');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, 'new text');
    });
  });
}
