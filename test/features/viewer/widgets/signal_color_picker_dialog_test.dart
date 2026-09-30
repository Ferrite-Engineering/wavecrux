// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/features/viewer/widgets/signal_color_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

/// A preset-grid color (dark red) that is not in the quick-pick palette and
/// not the initial color used by these tests.
const _presetDarkRed = Color(0xFF880000);

Widget _app(Widget child, {Locale? locale}) => MaterialApp(
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  locale: locale,
  home: Scaffold(body: child),
);

/// Finds the shared picker's circular swatch rendering [color].
///
/// The shared `crux_theme` swatch is a private widget, so pin it structurally:
/// a circular [Container] whose decoration color matches. The before/after
/// preview swatches are rounded rectangles, so the circle check excludes them.
Finder _swatch(Color color) => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
      (w.decoration! as BoxDecoration).color?.toARGB32() == color.toARGB32(),
);

/// Opens the picker via [SignalColorPickerDialog.show] and returns a getter
/// for the (eventual) result. Enlarges the test viewport first: the shared
/// dialog stacks two palette sections above its preview / hex / RGB / HSV
/// controls and does not fit the default 800x600 surface.
Future<Color? Function()> _open(
  WidgetTester tester,
  Color initial, {
  Locale? locale,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Color? result;
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            result = await SignalColorPickerDialog.show(ctx, initial);
          },
          child: const Text('Open'),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  group('SignalColorPickerDialog — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await _open(tester, WavecruxColors.signalGreen, locale: locale);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SignalColorPickerDialog — static structure', () {
    testWidgets('shows title, Palette and Presets section labels', (
      tester,
    ) async {
      await _open(tester, WavecruxColors.signalGreen);
      expect(find.text('Signal Color'), findsOneWidget);
      expect(find.text('Palette'), findsOneWidget);
      expect(find.text('Presets'), findsOneWidget);
    });

    testWidgets('shows Cancel and Apply buttons', (tester) async {
      await _open(tester, WavecruxColors.signalGreen);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('palette quick-picks render every WaveCrux signal color', (
      tester,
    ) async {
      await _open(tester, WavecruxColors.signalGreen);
      for (final c in WavecruxColors.signalPalette) {
        expect(_swatch(c), findsOneWidget);
      }
      // The initial color is a palette color, so exactly one swatch carries
      // the selected treatment's check mark.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('preset grid renders the hue-grouped preset colors', (
      tester,
    ) async {
      await _open(tester, WavecruxColors.signalGreen);
      // Spot-check one color per end of the grid plus the row count: first
      // red, dark red, and last neutral.
      expect(_swatch(const Color(0xFFFF2222)), findsOneWidget);
      expect(_swatch(_presetDarkRed), findsOneWidget);
      expect(_swatch(const Color(0xFF222222)), findsOneWidget);
    });

    testWidgets('hex field is pre-populated from the initial color', (
      tester,
    ) async {
      // Pure green — the shared picker always emits RRGGBBAA with alpha.
      await _open(tester, const Color(0xFF00FF00));
      expect(find.widgetWithText(TextField, '00FF00FF'), findsOneWidget);
    });

    testWidgets('shows the shared manual controls (HSV, RGB, preview)', (
      tester,
    ) async {
      await _open(tester, WavecruxColors.signalGreen);
      expect(find.text('Hue'), findsOneWidget);
      expect(find.text('Saturation'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(3));
      // RGB readout of pure signal green 4CAF50.
      expect(find.text('R 76  G 175  B 80  A 255'), findsOneWidget);
    });
  });

  group('SignalColorPickerDialog — interactions', () {
    testWidgets('Cancel dismisses and returns null', (tester) async {
      final result = await _open(tester, WavecruxColors.signalGreen);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Dialog is gone
      expect(find.text('Signal Color'), findsNothing);
      expect(result(), isNull);
    });

    testWidgets('Apply returns the initial color when unchanged', (
      tester,
    ) async {
      final result = await _open(tester, WavecruxColors.signalGreen);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result(), isNotNull);
      expect(result()!.toARGB32(), WavecruxColors.signalGreen.toARGB32());
    });

    testWidgets('tapping a preset swatch then Apply returns that color', (
      tester,
    ) async {
      final result = await _open(tester, WavecruxColors.signalGreen);

      await tester.tap(_swatch(_presetDarkRed));
      await tester.pump();
      // The tapped swatch now carries the selected check.
      expect(
        find.descendant(
          of: _swatch(_presetDarkRed),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result(), isNotNull);
      expect(result()!.toARGB32(), _presetDarkRed.toARGB32());
    });

    testWidgets('valid hex entry updates the color returned by Apply', (
      tester,
    ) async {
      final result = await _open(tester, WavecruxColors.signalGreen);

      await tester.enterText(find.byType(TextField), 'FF0000');
      await tester.pump();

      expect(find.textContaining('Invalid color'), findsNothing);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result(), isNotNull);
      expect(result()!.toARGB32(), const Color(0xFFFF0000).toARGB32());
    });

    testWidgets('partial hex input shows the error and disables Apply', (
      tester,
    ) async {
      // The shared picker surfaces incomplete hex as an inline error and
      // disables the confirm action (the old local dialog silently ignored
      // partial input instead).
      await _open(tester, WavecruxColors.signalGreen);

      await tester.enterText(find.byType(TextField), 'FF0');
      await tester.pump();

      expect(find.text('Invalid color: FF0'), findsOneWidget);
      final apply = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(apply.onPressed, isNull);
    });
  });
}
