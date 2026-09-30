// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: focus mechanics only; no localized text is rendered.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/utils/focus_opening_menu.dart';

Future<void> _pump(WidgetTester tester, {required bool openMenu}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            autofocus: true,
            onPressed: () {
              if (openMenu) {
                unawaited(
                  showMenu<String>(
                    context: context,
                    position: const RelativeRect.fromLTRB(10, 10, 10, 10),
                    items: const [
                      PopupMenuItem(value: 'a', child: Text('First')),
                      PopupMenuItem(value: 'b', child: Text('Second')),
                    ],
                  ),
                );
              }
              focusFirstItemOfOpeningMenu();
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String? _focusedText(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final texts = find
      .descendant(
        of: find.byElementPredicate((e) => identical(e, context)),
        matching: find.byType(Text),
      )
      .evaluate();
  return texts.isEmpty ? null : (texts.first.widget as Text).data;
}

void main() {
  testWidgets('focus lands on the first item of a menu that opens', (
    tester,
  ) async {
    await _pump(tester, openMenu: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(_focusedText(tester), 'First');
  });

  testWidgets('closing the menu returns focus to the control that opened it', (
    tester,
  ) async {
    await _pump(tester, openMenu: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('First'), findsNothing);
    expect(_focusedText(tester), 'Open');
  });

  testWidgets('with no menu opening, focus stays where it was', (
    tester,
  ) async {
    await _pump(tester, openMenu: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_focusedText(tester), 'Open');
  });
}
