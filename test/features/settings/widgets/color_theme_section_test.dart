// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/theme/wavecrux_color_theme_bootstrap.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_appearance_strings.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/widgets/color_theme_section.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/policy/org_theme_application.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

_MockSettingsService _stubSettings(AppSettings settings) {
  final mock = _MockSettingsService();
  when(mock.load).thenAnswer((_) async => settings);
  when(() => mock.save(any())).thenAnswer((_) async {});
  return mock;
}

/// Pumps [ColorThemeSection] with stubbed file-system seams so the
/// widget tree never hits `path_provider` or the OS file picker.
Future<Directory> _pumpSection(
  WidgetTester tester, {
  required AppSettings settings,
  Locale locale = const Locale('en'),
  Future<String?> Function()? pickPackDocument,
  Future<String?> Function(String)? savePackDocument,
}) async {
  final service = _stubSettings(settings);
  // Use a clean per-test directory so install/list/uninstall state
  // does not leak between tests.
  final tmp = Directory.systemTemp.createTempSync('crux_theme_test_');
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(service),
        wavecruxCruxColorThemeOverride,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColorThemeSection(
              settings: settings,
              packDirectoryResolver: () async => tmp,
              pickPackDocument: pickPackDocument,
              savePackDocument: savePackDocument,
            ),
          ),
        ),
      ),
    ),
  );
  // Resolve AppSettings, the ColorThemeSection FutureBuilder (pack dir),
  // and the ThemePackBrowser FutureBuilder (list packs). Three pumps
  // covers the await chain without relying on pumpAndSettle — the
  // ThemePackBrowser's CircularProgressIndicator animates indefinitely
  // while pending and would trip pumpAndSettle's stability check.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tmp;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
    registerWaveCruxThemeTokens();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Composer renders + locale sweep ────────────────────────────────────

  group('ThemeAppearanceSection composition', () {
    testWidgets('renders preset picker, token overrides, and pack browser', (
      tester,
    ) async {
      await _pumpSection(tester, settings: const AppSettings());
      expect(tester.takeException(), isNull);

      // ThemeAppearanceSection composes a PresetPicker plus one
      // TokenCategorySection per registered category plus a
      // ThemePackBrowser. Existence by widget type is enough — the
      // package-side widget tests cover the internals.
      expect(find.byType(PresetPicker), findsOneWidget);
      expect(find.byType(TokenCategorySection), findsWidgets);
      expect(find.byType(ThemePackBrowser), findsOneWidget);
    });

    testWidgets('renders one preset card per built-in preset', (tester) async {
      await _pumpSection(tester, settings: const AppSettings());
      expect(tester.takeException(), isNull);

      // PresetCard renders one card per preset passed to PresetPicker, which
      // is fed `builtinPresets().values`. Assert against the canonical count
      // rather than a magic number so adding a preset (e.g. the OLED XR
      // preset) doesn't silently break this test.
      expect(find.byType(PresetCard), findsNWidgets(builtinPresets().length));
    });
  });

  group('locale sweep', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('zh'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale', (tester) async {
        await _pumpSection(
          tester,
          settings: const AppSettings(),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Preset activation persistence ──────────────────────────────────────

  group('preset activation', () {
    testWidgets('tapping a preset card persists activeThemeName to settings', (
      tester,
    ) async {
      const initial = AppSettings(); // defaults to crux-dark
      final service = _stubSettings(initial);
      final saved = <AppSettings>[];
      when(() => service.save(any())).thenAnswer((invocation) async {
        saved.add(invocation.positionalArguments.first as AppSettings);
      });
      final tmp = Directory.systemTemp.createTempSync('crux_theme_test_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      // Force a wide canvas so PresetPicker lays out all preset cards
      // without scroll, and the Oscilloscope card sits inside the
      // visible area.
      tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsServiceProvider.overrideWithValue(service),
            wavecruxCruxColorThemeOverride,
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ColorThemeSection(
                  settings: initial,
                  packDirectoryResolver: () async => tmp,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Tap the Oscilloscope preset card via its enclosing InkWell.
      final oscilloscopeCard = find.ancestor(
        of: find.text('Oscilloscope'),
        matching: find.byType(PresetCard),
      );
      expect(oscilloscopeCard, findsOneWidget);
      await tester.tap(oscilloscopeCard, warnIfMissed: false);
      // Let the activate() notifier chain complete the
      // setActiveThemeName / setThemeOverrides futures.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The bootstrap notifier writes through to AppSettings via
      // setActiveThemeName, which calls save() — assert one of the
      // saved snapshots reflects the new preset id.
      expect(
        saved.any((s) => s.activeThemeName == 'oscilloscope'),
        isTrue,
        reason: 'Expected activeThemeName to be persisted after preset tap',
      );
    });

    testWidgets('a theme the organization locked is shown but not changeable', (
      tester,
    ) async {
      const initial = AppSettings();
      final service = _stubSettings(initial);
      final saved = <AppSettings>[];
      when(() => service.save(any())).thenAnswer((invocation) async {
        saved.add(invocation.positionalArguments.first as AppSettings);
      });
      final tmp = Directory.systemTemp.createTempSync('crux_theme_test_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsServiceProvider.overrideWithValue(service),
            wavecruxCruxColorThemeOverride,
            orgThemeLockedProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ColorThemeSection(
                  settings: initial,
                  packDirectoryResolver: () async => tmp,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final l10n = L10N.of(tester.element(find.byType(ColorThemeSection)));
      expect(find.text(l10n.appearanceThemeLockedByPolicy), findsOneWidget);
      // Still visible: an engineer can see what the organization chose.
      final card = find.ancestor(
        of: find.text('Oscilloscope'),
        matching: find.byType(PresetCard),
      );
      expect(card, findsOneWidget);

      await tester.tap(card, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(saved.where((s) => s.activeThemeName == 'oscilloscope'), isEmpty);
    });
  });

  // ── File-picker callbacks ──────────────────────────────────────────────

  group('file picker callbacks', () {
    testWidgets('import button invokes pickPackDocument callback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var imported = false;
      await _pumpSection(
        tester,
        settings: const AppSettings(),
        pickPackDocument: () async {
          imported = true;
          return null; // user cancels — keeps state clean
        },
      );
      expect(tester.takeException(), isNull);

      final importButton = find.descendant(
        of: find.byType(ThemePackBrowser),
        matching: find.byType(FilledButton),
      );
      expect(importButton, findsOneWidget);
      await tester.tap(importButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(imported, isTrue);
    });

    testWidgets('export button invokes savePackDocument callback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var exported = false;
      await _pumpSection(
        tester,
        settings: const AppSettings(),
        savePackDocument: (document) async {
          exported = true;
          return null; // user cancels — no file is written
        },
      );
      expect(tester.takeException(), isNull);

      final exportButton = find.descendant(
        of: find.byType(ThemePackBrowser),
        matching: find.byType(OutlinedButton),
      );
      expect(exportButton, findsOneWidget);
      await tester.tap(exportButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(exported, isTrue);
    });

    testWidgets('export hands the encoded active theme to savePackDocument', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The store abstraction moved the write out of `ThemePackBrowser`: the
      // widget encodes the active theme and hands the *document text* to the
      // host, which owns the destination. So the assertion is on the text the
      // callback receives — no filesystem, no runAsync polling.
      String? received;
      await _pumpSection(
        tester,
        settings: const AppSettings(),
        savePackDocument: (document) async {
          received = document;
          return '/tmp/exported.crux-theme.json';
        },
      );
      expect(tester.takeException(), isNull);

      final exportButton = find.descendant(
        of: find.byType(ThemePackBrowser),
        matching: find.byType(OutlinedButton),
      );
      await tester.tap(exportButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(received, isNotNull);
      expect(received, contains('"schemaVersion": 1'));
      // The default preset id is the de-branded suite-wide `crux-dark`;
      // `wavecrux-dark` survives only as a read-path alias.
      expect(received, contains('"$cruxDarkPresetId"'));
    });
  });

  // ── Strings adapter ────────────────────────────────────────────────────

  group('WaveCruxThemeAppearanceStrings', () {
    testWidgets('adapts every interface slot to the active L10N', (
      tester,
    ) async {
      L10N? captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              captured = L10N.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = captured!;
      final strings = WaveCruxThemeAppearanceStrings(l10n);

      // Hit every getter to confirm none of them throw — protects
      // against ARB drift between the package interface and the adapter.
      expect(strings.sectionTitle, equals(l10n.settingsAppearanceSection));
      expect(strings.sectionSubtitle, equals(l10n.appearanceSectionSubtitle));
      expect(
        strings.presetSectionHeading,
        equals(l10n.appearancePresetSectionHeading),
      );
      expect(
        strings.tokenOverridesSectionHeading,
        equals(l10n.appearanceTokenOverridesSectionHeading),
      );
      expect(
        strings.themePackBrowserSectionHeading,
        equals(l10n.appearanceThemePackBrowserSectionHeading),
      );
      expect(strings.activatePresetTooltip, isNotEmpty);
      expect(strings.brightnessLabel(isDark: true), isNotEmpty);
      expect(strings.brightnessLabel(isDark: false), isNotEmpty);
      expect(strings.collapseCategoryLabel('Canvas'), contains('Canvas'));
      expect(strings.expandCategoryLabel('Chrome'), contains('Chrome'));
      expect(strings.invalidHexMessage('ZZZ'), contains('ZZZ'));
      expect(
        strings.confirmUninstallDialogBody('my-pack'),
        contains('my-pack'),
      );
      expect(strings.importFailedMessage('boom'), contains('boom'));
      expect(strings.importSucceededMessage('mypack'), contains('mypack'));
      expect(strings.exportSucceededMessage('/tmp/x'), contains('/tmp/x'));
      expect(strings.exportFailedMessage('boom'), contains('boom'));
    });
  });
}
