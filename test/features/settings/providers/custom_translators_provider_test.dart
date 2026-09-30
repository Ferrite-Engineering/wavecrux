// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/features/settings/providers/custom_translators_provider.dart';

CustomTranslatorDef _def(String name, {int fields = 1}) => CustomTranslatorDef(
  name: name,
  config: BitfieldTranslatorConfig(
    fields: [
      for (var i = 0; i < fields; i++)
        BitFieldSpec(name: 'f$i', hiBit: i, loBit: i),
    ],
  ),
);

void main() {
  test('starts empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(customTranslatorsProvider), isEmpty);
  });

  test('upsert adds then replaces by name, kept sorted', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(customTranslatorsProvider.notifier)
      ..upsert(_def('beta'))
      ..upsert(_def('alpha'));
    expect(c.read(customTranslatorsProvider).map((d) => d.name), [
      'alpha',
      'beta',
    ]);

    n.upsert(_def('alpha', fields: 3));
    expect(c.read(customTranslatorsProvider), hasLength(2));
    expect(n.byName('alpha')!.config.fields, hasLength(3));
  });

  test('rename replaces the old entry', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(customTranslatorsProvider.notifier)
      ..upsert(_def('old'))
      ..rename('old', _def('new'));
    expect(n.byName('old'), isNull);
    expect(n.byName('new'), isNotNull);
  });

  test('remove deletes by name', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(customTranslatorsProvider.notifier)
      ..upsert(_def('a'))
      ..upsert(_def('b'))
      ..remove('a');
    expect(c.read(customTranslatorsProvider).map((d) => d.name), ['b']);
  });
}
