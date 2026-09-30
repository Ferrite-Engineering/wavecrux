// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/translator_expansion_provider.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/value_format/bitfield_translator.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

/// A non-bitfield translator that reserves a config-driven number of child
/// rows — stands in for a Pro-pack translator (pro.amba / pro.mlFloat /
/// pro.pixel) contributed through `extraTranslatorsProvider`.
class _FakeChildRowTranslator implements Translator, ChildRowTranslator {
  const _FakeChildRowTranslator();
  static const String translatorId = 'fake.childRows';
  @override
  String get id => translatorId;
  @override
  TranslationResult translate(TranslationRequest request) =>
      const TranslationResult(text: 'x');
  @override
  int childRowCount(Map<String, Object?>? config) =>
      (config?['n'] as num?)?.toInt() ?? 0;
}

const _desktop = LaneMetrics(minLaneHeight: 16);

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: 8,
);

Map<String, Object?> _bitfieldCfg() => {
  ...const BitfieldTranslatorConfig(
    fields: [
      BitFieldSpec(name: 'hi', hiBit: 7, loBit: 4),
      BitFieldSpec(name: 'lo', hiBit: 3, loBit: 0),
    ],
  ).toMap(),
  kTranslatorIdConfigKey: BitfieldTranslator.translatorId,
};

void main() {
  test('toggle flips expansion state by entry id', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(expandedTranslatorRowsProvider.notifier);

    expect(notifier.isExpanded('id-1'), isFalse);
    notifier.toggle('id-1');
    expect(notifier.isExpanded('id-1'), isTrue);
    notifier.toggle('id-1');
    expect(notifier.isExpanded('id-1'), isFalse);
  });

  test('signalChildRowCounts only counts expanded bitfield-bound signals', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier).addSignal(_v('bus'));
    final id = c.read(signalGroupsProvider).entries.single.id;
    c
        .read(signalGroupsProvider.notifier)
        .setSignalTranslatorConfigByRef('ref_bus', _bitfieldCfg());

    // Collapsed → no reserved child rows.
    expect(c.read(signalChildRowCountsProvider), isEmpty);

    // Expanded → two child rows (one per field).
    c.read(expandedTranslatorRowsProvider.notifier).toggle(id);
    expect(c.read(signalChildRowCountsProvider), {id: 2});
  });

  test('expansion inflates the shared lane geometry by the child rows', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier).addSignal(_v('bus'));
    final id = c.read(signalGroupsProvider).entries.single.id;
    c
        .read(signalGroupsProvider.notifier)
        .setSignalTranslatorConfigByRef('ref_bus', _bitfieldCfg());

    // Collapsed: one 30 dp lane.
    expect(c.read(laneGeometryProvider(_desktop)).rows.single.height, 30);

    // Expanded: 30 + 2 * childRowHeight, and the row carries childRows = 2.
    c.read(expandedTranslatorRowsProvider.notifier).toggle(id);
    final row = c.read(laneGeometryProvider(_desktop)).rows.single;
    expect(row.childRows, 2);
    expect(row.height, 30 + 2 * kChildRowHeight);
  });

  test('a signal without a bitfield binding reserves no child rows', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier).addSignal(_v('plain'));
    final id = c.read(signalGroupsProvider).entries.single.id;
    c.read(expandedTranslatorRowsProvider.notifier).toggle(id);
    expect(c.read(signalChildRowCountsProvider), isEmpty);
  });

  test('counts child rows for any registered ChildRowTranslator (not just '
      'builtin.bitfield) — the Pro-pack path', () {
    // Register a non-bitfield ChildRowTranslator through the same seam the
    // Pro pack uses, and bind a signal to it with n=4.
    final c = ProviderContainer(
      overrides: [
        extraTranslatorsProvider.overrideWithValue(
          const [_FakeChildRowTranslator()],
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier).addSignal(_v('bus'));
    final id = c.read(signalGroupsProvider).entries.single.id;
    c.read(signalGroupsProvider.notifier).setSignalTranslatorConfigByRef(
      'ref_bus',
      {kTranslatorIdConfigKey: _FakeChildRowTranslator.translatorId, 'n': 4},
    );

    c.read(expandedTranslatorRowsProvider.notifier).toggle(id);
    expect(c.read(signalChildRowCountsProvider), {id: 4});
  });
}
