// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness;

/// Flips the active color-theme preset between the default light and dark
/// WaveCrux presets. Wired to `ShortcutAction.toggleTheme` (⌘/Ctrl+Shift+K).
///
/// Brightness in WaveCrux is driven entirely by the *active color-theme
/// preset*: `MaterialApp.themeMode` in `app.dart` is derived from the preset's
/// `brightness` via `themeModeFromBrightness`, and the Settings → Appearance
/// preset picker is the single brightness lever. The legacy `AppThemeMode`
/// (light / dark / system) setting is no longer consulted for theming, so this
/// toggle activates the opposite-brightness *default* preset rather than
/// writing that dead flag.
///
/// When the user is on a non-default preset (e.g. Solarized Dark), the toggle
/// lands on the default preset of the opposite brightness (WaveCrux Light); the
/// preset picker reflects the new selection. Activation flows through the
/// WaveCrux color-theme notifier (see `wavecrux_color_theme_bootstrap.dart`),
/// which persists `activeThemeName` so the choice survives a restart.
void toggleThemeBrightness(
  CruxColorThemeNotifier notifier,
  CruxColorTheme current,
) {
  final presets = builtinPresets();
  // Preset ids are the de-branded suite-wide `crux-*` constants exported by
  // `crux_theme`; hardcoding the old `wavecrux-*` spellings would make these
  // lookups return null and the `!` throw.
  final next = current.brightness == Brightness.dark
      ? presets[cruxLightPresetId]!
      : presets[cruxDarkPresetId]!;
  notifier.activate(next);
}
