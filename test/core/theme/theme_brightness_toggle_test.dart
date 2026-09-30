// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/theme_brightness_toggle.dart';

void main() {
  ProviderContainer makeContainer(String initialId) {
    final container = ProviderContainer(
      overrides: [
        cruxColorThemeProvider.overrideWith(
          () => CruxColorThemeNotifier(initial: builtinPresets()[initialId]!),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void toggle(ProviderContainer c) => toggleThemeBrightness(
    c.read(cruxColorThemeProvider.notifier),
    c.read(cruxColorThemeProvider),
  );

  group('toggleThemeBrightness', () {
    test('a dark preset toggles to the default light preset', () {
      final c = makeContainer(cruxDarkPresetId);
      expect(c.read(cruxColorThemeProvider).brightness, Brightness.dark);

      toggle(c);

      final after = c.read(cruxColorThemeProvider);
      expect(after.brightness, Brightness.light);
      expect(after.id, cruxLightPresetId);
    });

    test('a light preset toggles to the default dark preset', () {
      final c = makeContainer(cruxLightPresetId);
      expect(c.read(cruxColorThemeProvider).brightness, Brightness.light);

      toggle(c);

      final after = c.read(cruxColorThemeProvider);
      expect(after.brightness, Brightness.dark);
      expect(after.id, cruxDarkPresetId);
    });

    test('a non-default dark preset lands on the default light preset', () {
      // Solarized Dark is brightness-dark but not the WaveCrux Dark default;
      // toggling brightness lands on the opposite-brightness *default*.
      final c = makeContainer('solarized-dark');
      expect(c.read(cruxColorThemeProvider).brightness, Brightness.dark);

      toggle(c);

      expect(c.read(cruxColorThemeProvider).id, cruxLightPresetId);
    });

    test(
      'round-trip dark → light → dark returns to the default dark preset',
      () {
        final c = makeContainer(cruxDarkPresetId);

        toggle(c);
        expect(c.read(cruxColorThemeProvider).id, cruxLightPresetId);
        toggle(c);
        expect(c.read(cruxColorThemeProvider).id, cruxDarkPresetId);
      },
    );
  });
}
