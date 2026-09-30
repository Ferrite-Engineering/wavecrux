// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/plugins/extra_translator_presets_provider.dart';
import 'package:wavecrux/plugins/translator_preset.dart';

void main() {
  group('extraTranslatorPresetsProvider', () {
    test('open-core default is an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(extraTranslatorPresetsProvider), isEmpty);
    });

    test('honors an override that contributes presets', () {
      final preset = TranslatorPreset(
        id: 'test.preset',
        labelResolver: (_) => 'Test',
        icon: Icons.bolt,
        configBuilder: () => const {'translator': 'test.preset'},
        requiredTier: LicenseTier.pro,
      );
      final container = ProviderContainer(
        overrides: [
          extraTranslatorPresetsProvider.overrideWithValue([preset]),
        ],
      );
      addTearDown(container.dispose);

      final presets = container.read(extraTranslatorPresetsProvider);
      expect(presets, hasLength(1));
      expect(presets.single.id, 'test.preset');
      expect(presets.single.requiredTier, LicenseTier.pro);
      expect(presets.single.configBuilder()['translator'], 'test.preset');
    });
  });
}
