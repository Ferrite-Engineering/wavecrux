// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/features/settings/providers/custom_translators_provider.dart';

CustomTranslatorDef _def(String name) =>
    CustomTranslatorDef(name: name, config: const BitfieldTranslatorConfig());

void main() {
  group('CustomTranslators view-composition recipe seams', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('toCompositionRecipe returns the library', () {
      c.read(customTranslatorsProvider.notifier)
        ..upsert(_def('axi'))
        ..upsert(_def('reg'));
      final recipe = c
          .read(customTranslatorsProvider.notifier)
          .toCompositionRecipe();
      expect(recipe.map((d) => d.name), ['axi', 'reg']);
    });

    test('round-trip: apply replaces the library (sorted)', () {
      c.read(customTranslatorsProvider.notifier)
        ..upsert(_def('followers_own'))
        ..applyCompositionRecipe([_def('zeta'), _def('alpha')]);
      // Follower's own def is gone; presenter's library replaced it, sorted.
      expect(c.read(customTranslatorsProvider).map((d) => d.name), [
        'alpha',
        'zeta',
      ]);
    });
  });
}
