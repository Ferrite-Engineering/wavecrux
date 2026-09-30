// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/q_format_config_dialog.dart';

Widget _harness(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  );
}

// Opens QFormatConfigDialog via show() and returns [tester] with the dialog
// already on screen.
Future<void> _openDialog(
  WidgetTester tester, {
  Map<String, Object?>? config,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    _harness(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => QFormatConfigDialog.show(ctx, config: config),
          child: const Text('open'),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('QFormatConfigDialog — rendering', () {
    testWidgets('shows title, sliders, signed switch, and preview', (
      tester,
    ) async {
      await _openDialog(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2));
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets(
      'initializes with default QFormatConfig when no config provided',
      (tester) async {
        await _openDialog(tester);
        const defaults = QFormatConfig();

        // The preview text should contain the default notation.
        expect(find.textContaining(defaults.notation), findsOneWidget);
      },
    );

    testWidgets('initializes with provided config values', (tester) async {
      // Use m: 4, n: 12 (non-default) and signed: false (non-default) so the
      // notation preview differs visibly from the default "Q7.8".
      final config = const QFormatConfig(m: 4, n: 12, signed: false).toMap();
      await _openDialog(tester, config: config);

      expect(
        find.textContaining(
          const QFormatConfig(m: 4, n: 12, signed: false).notation,
        ),
        findsOneWidget,
      );
    });
  });

  group('QFormatConfigDialog — cancel', () {
    testWidgets('returns null when dismissed via Cancel', (tester) async {
      Map<String, Object?>? result = const {'sentinel': true};

      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await QFormatConfigDialog.show(ctx);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('a tap outside does NOT dismiss — editor dialogs hold '
        'in-progress input (suite dialog canon)', (tester) async {
      Map<String, Object?>? result = const {'sentinel': true};

      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await QFormatConfigDialog.show(ctx);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // A stray tap on the scrim must NOT discard the editor.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(result, const {'sentinel': true});

      // Cancel remains the deliberate dismissal path.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('QFormatConfigDialog — dirty-cancel guard', () {
    testWidgets('dirty cancel prompts to discard; keep editing stays open', (
      tester,
    ) async {
      await _openDialog(tester);

      // Dirty the form by flipping the signed switch.
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // "Keep editing" returns to the editor.
      await tester.tap(
        find.byKey(const ValueKey('editorDiscardConfirmKeepEditing')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(SwitchListTile), findsOneWidget);

      // "Discard" closes the editor.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editorDiscardConfirmDiscard')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('clean cancel closes without a prompt', (tester) async {
      await _openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('QFormatConfigDialog — OK', () {
    testWidgets('returns non-null map when OK is tapped', (tester) async {
      Map<String, Object?>? result;

      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await QFormatConfigDialog.show(ctx);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
    });

    testWidgets('returned map round-trips through QFormatConfig', (
      tester,
    ) async {
      Map<String, Object?>? result;

      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await QFormatConfigDialog.show(
                  ctx,
                  config: const QFormatConfig(m: 4, n: 12).toMap(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Accept defaults — we just confirm round-trip works.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      final restored = QFormatConfig.fromMap(result!);
      expect(restored.m, 4);
      expect(restored.n, 12);
      expect(restored.signed, isTrue);
    });
  });

  group('QFormatConfigDialog — locale sweep', () {
    const locales = [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];

    for (final locale in locales) {
      testWidgets('renders without exception in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await _openDialog(tester, locale: locale);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'QFormatConfigDialog raised in ${locale.toLanguageTag()}',
        );
      });
    }
  });
}
