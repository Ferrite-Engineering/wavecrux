// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/viewer/widgets/status_bar.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  double textScaleFactor = 1.0,
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: overrides,
  child: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: child),
    ),
  ),
);

Widget _toolbar({
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: overrides,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: ViewerToolbar(
          onShortcutAction: (_) {},
          isTransactionTableVisible: false,
          isStagePanelVisible: false,
        ),
      ),
    ),
  ),
);

void main() {
  // ── Toolbar semantic label tests ────────────────────────────────────────────

  group('ViewerToolbar accessibility', () {
    testWidgets('toolbar renders without exception and contains Semantics', (
      tester,
    ) async {
      await tester.pumpWidget(_toolbar());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The Semantics container wrapping the toolbar must be present in the tree.
      expect(find.byType(Semantics), findsWidgets);
    });

    testWidgets('toolbar buttons have tooltips set directly on IconButton', (
      tester,
    ) async {
      await tester.pumpWidget(_toolbar());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The tooltip is passed to IconButton.tooltip (not an outer Tooltip
      // widget), which Flutter uses as both the tooltip message and the
      // button's semantic label for screen readers. It now also carries the
      // user's live keybinding, so match the label prefix rather than the
      // whole string.
      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((w) => w.message ?? '')
          .toList();
      expect(messages.any((m) => m.startsWith('Open File')), isTrue);
    });

    testWidgets('toolbar renders at 2x text scale without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(_toolbar());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ── StatusBar semantic region tests ────────────────────────────────────────

  group('StatusBar accessibility', () {
    testWidgets('status bar contains a Semantics container node', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StatusBar()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The Semantics region wrapping the status bar is present in the tree.
      expect(find.byType(Semantics), findsWidgets);
    });

    testWidgets('status bar renders at 2x text scale without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const StatusBar(), textScaleFactor: 2),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // SizedBox must still match the desktop StatusBar height (24 dp) on
      // macOS host regardless of text scale, because
      // MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3) clamps the
      // multiplier; the underlying SizedBox height is fixed by MobileMetrics.
      final box = tester.getSize(find.byType(StatusBar));
      expect(box.height, 24);
    });
  });

  // ── High-contrast theme validity ────────────────────────────────────────────

  group('WavecruxTheme high-contrast', () {
    test('highContrastDark is a valid ThemeData with bright outlines', () {
      final theme = WavecruxTheme.highContrastDark;
      expect(theme.brightness, Brightness.dark);
      expect((theme.colorScheme.outline.a * 255.0).round().clamp(0, 255), 255);
    });

    test('highContrastLight is a valid ThemeData with dark outlines', () {
      final theme = WavecruxTheme.highContrastLight;
      expect(theme.brightness, Brightness.light);
      expect((theme.colorScheme.outline.a * 255.0).round().clamp(0, 255), 255);
    });

    testWidgets('MaterialApp accepts highContrast themes without error', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavecruxTheme.light,
          darkTheme: WavecruxTheme.dark,
          highContrastTheme: WavecruxTheme.highContrastLight,
          highContrastDarkTheme: WavecruxTheme.highContrastDark,
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ── Locale sweep ─────────────────────────────────────────────────────────────

  group('Accessibility locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('StatusBar renders without exception in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(const StatusBar(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('ViewerToolbar renders without exception in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(_toolbar(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Desktop layout — all primary buttons have labels ─────────────────────────

  group('ViewerToolbar desktop layout semantics', () {
    testWidgets(
      'Zoom In and Zoom Out buttons have tooltips set on IconButton',
      (tester) async {
        await tester.pumpWidget(
          _toolbar(
            overrides: [
              deviceClassProvider.overrideWith((_) => DeviceClass.desktop),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Desktop shows both zoom buttons inline with tooltip-derived
        // semantic labels via IconButton.tooltip. The chord is no longer
        // baked into the label — five ARB keys spelled it in across five
        // locales, and WaveCrux shortcuts are rebindable, so those strings
        // were wrong by construction. The live binding is appended at render
        // time instead, so assert on the label prefix.
        final messages = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((w) => w.message ?? '')
            .toList();
        expect(messages.any((m) => m.startsWith('Zoom In')), isTrue);
        expect(messages.any((m) => m.startsWith('Zoom Out')), isTrue);
        expect(
          messages.any((m) => m.contains('(W)')),
          isFalse,
          reason: 'the chord must not be part of the translated label',
        );
      },
    );
  });
}
