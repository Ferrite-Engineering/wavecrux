// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';

/// Verifies that the `.crux-theme.json` preset fixtures under
/// `test/fixtures/themes/` parse via `crux_theme`'s `ThemePackCodec` and that
/// every WaveCrux-registered token resolves to a non-null `Color` once
/// `ThemeRegistry` fallback is applied. Regression guard against drift
/// between the WaveCrux token catalog and the JSON theme-pack format.
///
/// These packs are test fixtures, not shipped assets — the running app's
/// built-in presets come from `crux_theme`'s `builtinPresets()` (Dart), so the
/// JSON copies are read from the test tree via `File` rather than `rootBundle`
/// to keep them out of the app bundle.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (!ThemeRegistry.instance.hasCategory(canvasTokens.id)) {
      registerWaveCruxThemeTokens();
    }
  });

  const presetIds = [
    'wavecrux-dark',
    'wavecrux-light',
    'solarized-dark',
    'high-contrast-dark',
    'oscilloscope',
  ];

  for (final id in presetIds) {
    test(
      'asset $id parses and covers every registered WaveCrux token',
      () async {
        const codec = ThemePackCodec();
        final raw = await File('test/fixtures/themes/$id.json').readAsString();
        final pack = codec.decode(raw);

        expect(pack.id, id, reason: 'pack id must match filename');
        expect(
          pack.brightness,
          anyOf(Brightness.dark, Brightness.light),
          reason: 'brightness must round-trip',
        );

        final theme = pack.toTheme();
        for (final descriptor in canvasTokens.tokens) {
          final color = ThemeRegistry.instance.resolve(
            theme,
            canvasTokens.id,
            descriptor.id,
          );
          expect(
            color,
            isNotNull,
            reason: 'canvas.${descriptor.id} must resolve in $id',
          );
        }
        for (final descriptor in chromeTokens.tokens) {
          final color = ThemeRegistry.instance.resolve(
            theme,
            chromeTokens.id,
            descriptor.id,
          );
          expect(
            color,
            isNotNull,
            reason: 'chrome.${descriptor.id} must resolve in $id',
          );
        }
      },
    );
  }
}
