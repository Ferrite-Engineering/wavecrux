// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guards the legacy preset-id migration in [WaveCruxCruxColorThemeNotifier].
//
// The suite-wide preset ids were de-branded: `wavecrux-dark` / `wavecrux-light`
// became `crux-dark` / `crux-light`. Beta users have the OLD spelling persisted
// in `AppSettings.activeThemeName`. `builtinPresetById` applies crux_theme's
// permanent read-path alias map; a plain `builtinPresets()[name]` lookup does
// not, and would silently drop every existing user back to the seed preset on
// first launch after the upgrade.
//
// That failure is invisible in `flutter analyze` and produces no exception at
// runtime — it just quietly resets people's theme. Hence this test.

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/theme/wavecrux_color_theme_bootstrap.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

/// Builds a container whose settings hydrate to [themeName].
Future<ProviderContainer> _containerFor(String themeName) async {
  final mock = _MockSettingsService();
  when(mock.load).thenAnswer(
    (_) async => const AppSettings().copyWith(activeThemeName: themeName),
  );
  when(() => mock.save(any())).thenAnswer((_) async {});

  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(mock),
      wavecruxCruxColorThemeOverride,
    ],
  );
  addTearDown(container.dispose);
  // Realize the settings future so the notifier's build() sees a value
  // rather than the seed preset.
  await container.read(appSettingsProvider.future);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
    registerWaveCruxThemeTokens();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('legacy preset id migration', () {
    test(
      'a persisted `wavecrux-dark` resolves to the crux-dark preset',
      () async {
        final container = await _containerFor('wavecrux-dark');
        final theme = container.read(cruxColorThemeProvider);
        expect(theme.id, cruxDarkPresetId);
        expect(theme.brightness, Brightness.dark);
      },
    );

    test(
      'a persisted `wavecrux-light` keeps the user on a LIGHT theme',
      () async {
        // The regression this guards: without the alias, the lookup misses,
        // the notifier falls back to its dark seed, and a light-theme user is
        // dropped into dark mode on upgrade.
        final container = await _containerFor('wavecrux-light');
        final theme = container.read(cruxColorThemeProvider);
        expect(theme.id, cruxLightPresetId);
        expect(theme.brightness, Brightness.light);
      },
    );

    test('current ids still resolve directly', () async {
      final container = await _containerFor(cruxLightPresetId);
      expect(container.read(cruxColorThemeProvider).id, cruxLightPresetId);
    });

    test('a non-built-in id falls back to the seed preset', () async {
      // e.g. a theme pack that was uninstalled since it was last activated.
      final container = await _containerFor('some-uninstalled-pack');
      expect(container.read(cruxColorThemeProvider).id, cruxDarkPresetId);
    });

    test('the migrated theme carries WaveCrux canvas tokens', () async {
      // The canvas values arrive via the product-registered
      // `PresetTokenOverlay`, so a migrated preset must still paint.
      final container = await _containerFor('wavecrux-dark');
      final theme = container.read(cruxColorThemeProvider);
      expect(
        theme.color(canvasTokens.id, 'signal.x.fill')?.toARGB32(),
        0xFFFF2222,
      );
    });
  });

  group('theme packs', () {
    CruxColorTheme packTheme() => CruxColorTheme(
      id: 'house-style',
      displayName: 'House Style',
      brightness: Brightness.light,
      tokens: const {
        'canvas': {'background': Color(0xFFFAF0E6)},
      },
    );

    test('an activated pack stays active after its choice is saved', () async {
      // The regression: activation persists the pack's id, the settings write
      // rebuilds the notifier, and a rebuild that only knew built-in presets
      // fell back to Crux Dark straight away.
      final container = await _containerFor(cruxDarkPresetId);
      container.read(cruxColorThemeProvider.notifier).activate(packTheme());
      await pumpEventQueue();

      expect(
        container.read(appSettingsProvider).value?.activeThemeName,
        'house-style',
      );
      final active = container.read(cruxColorThemeProvider);
      expect(active.id, 'house-style');
      expect(
        active.color('canvas', 'background')?.toARGB32(),
        0xFFFAF0E6,
      );
    });

    test('choosing a preset afterwards leaves the pack', () async {
      final container = await _containerFor(cruxDarkPresetId);
      container.read(cruxColorThemeProvider.notifier)
        ..activate(packTheme())
        ..activate(builtinPresetById(cruxLightPresetId)!);
      await pumpEventQueue();

      expect(container.read(cruxColorThemeProvider).id, cruxLightPresetId);
    });

    test(
      'bootstrap restores the saved pack from the installed store',
      () async {
        final container = await _containerFor('house-style');
        final store = InMemoryThemePackStore(
          initialPacks: [
            ThemePack(
              id: 'house-style',
              displayName: 'House Style',
              brightness: Brightness.light,
              tokens: packTheme().tokens,
            ),
          ],
        );

        await restoreActiveThemePack(
          container,
          storeResolver: () async => store,
        );
        await pumpEventQueue();

        expect(container.read(cruxColorThemeProvider).id, 'house-style');
      },
    );

    test('an uninstalled saved pack leaves the default theme', () async {
      final container = await _containerFor('house-style');

      await restoreActiveThemePack(
        container,
        storeResolver: () async => InMemoryThemePackStore(),
      );

      expect(container.read(cruxColorThemeProvider).id, cruxDarkPresetId);
    });
  });

  group('applyEphemeral (editor-host theme bridge)', () {
    test('replaces the rendered theme immediately', () async {
      final container = await _containerFor(cruxLightPresetId);
      final notifier =
          container.read(cruxColorThemeProvider.notifier)
              as WaveCruxCruxColorThemeNotifier;
      final hostTheme = CruxColorTheme(
        id: 'editor-host.vscode',
        displayName: 'VSCode',
        brightness: Brightness.dark,
        tokens: const {
          'canvas': {'background': Color(0xFF101010)},
        },
      );

      notifier.applyEphemeral(hostTheme);

      final active = container.read(cruxColorThemeProvider);
      expect(active.id, 'editor-host.vscode');
      expect(active.brightness, Brightness.dark);
      expect(
        active.color('canvas', 'background')?.toARGB32(),
        0xFF101010,
      );
    });

    test('does not persist — the on-disk preset choice survives it', () async {
      // The regression this guards: a VSCode window toggling theme must never
      // overwrite what `activeThemeName` / `themeOverrides` say for the next
      // launch outside that window. `activate` (the preset-switch path) does
      // persist; `applyEphemeral` deliberately calls straight through to the
      // base notifier and skips `_persistDerivedFromTheme` entirely.
      final container = await _containerFor(cruxLightPresetId);
      (container.read(cruxColorThemeProvider.notifier)
              as WaveCruxCruxColorThemeNotifier)
          .applyEphemeral(
            CruxColorTheme(
              id: 'editor-host.vscode',
              displayName: 'VSCode',
              brightness: Brightness.dark,
              tokens: const <String, Map<String, Color>>{},
            ),
          );

      // The rendered theme changed…
      expect(container.read(cruxColorThemeProvider).id, 'editor-host.vscode');
      // …but the persisted settings snapshot did not.
      expect(
        container.read(appSettingsProvider).value?.activeThemeName,
        cruxLightPresetId,
      );
    });

    test(
      'a later activate() (preset switch) still persists normally',
      () async {
        // Proves `applyEphemeral` did not disable persistence globally — it
        // bypasses it for exactly the one call it makes.
        final container = await _containerFor(cruxLightPresetId);
        (container.read(cruxColorThemeProvider.notifier)
              as WaveCruxCruxColorThemeNotifier)
          ..applyEphemeral(
            CruxColorTheme(
              id: 'editor-host.vscode',
              displayName: 'VSCode',
              brightness: Brightness.dark,
              tokens: const <String, Map<String, Color>>{},
            ),
          )
          ..activate(builtinPresetById(cruxDarkPresetId)!);

        expect(
          container.read(appSettingsProvider).value?.activeThemeName,
          cruxDarkPresetId,
        );
      },
    );
  });
}
