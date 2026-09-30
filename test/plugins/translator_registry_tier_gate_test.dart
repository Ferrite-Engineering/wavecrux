// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A session restore puts back every signal's translator binding, and the Pro
// overlay registers its translators at every tier: the bind dialog is the only
// door that asks. So the registry the value column resolves through asks the
// tier, and these tests restore a signal list bound to a Pro translator the
// way a session saved during the beta would bind one.

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/translator_registry.dart';

import '../helpers/fake_waveform_data_source.dart';

/// Stands in for a Pro pack translator: registered at every tier through
/// [extraTranslatorsProvider], sold at Pro.
class _ProTranslator implements TierGatedTranslator {
  const _ProTranslator();

  static const String translatorId = 'pro.fake';

  @override
  String get id => translatorId;

  @override
  LicenseTier get requiredTier => LicenseTier.pro;

  @override
  TranslationResult translate(TranslationRequest request) =>
      const TranslationResult(text: 'pro-translated');
}

class _OpenTranslator implements Translator {
  const _OpenTranslator();

  static const String translatorId = 'contrib.open';

  @override
  String get id => translatorId;

  @override
  TranslationResult translate(TranslationRequest request) =>
      const TranslationResult(text: 'open-translated');
}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);

  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// A `licenseTierProvider` source a test can change after the container is
/// built, the way a stored licence resolves after startup.
final _tier = NotifierProvider<_TierNotifier, LicenseTier>(_TierNotifier.new);

class _TierNotifier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get tier => state;
  set tier(LicenseTier value) => state = value;
}

final _boundEntry = SignalEntry.signal(
  signalRef: 'top.bus',
  displayName: 'bus',
  translatorConfig: const {
    kTranslatorIdConfigKey: _ProTranslator.translatorId,
  },
);

/// Restores a signal list whose one signal is bound to the Pro translator,
/// the way `SessionNotifier` restores `signalGroup`.
ProviderContainer _restored({required bool beta, LicenseTier? tier}) {
  final source = FakeWaveformDataSource(
    signals: {
      'top.bus': const [SignalChange(time: 0, value: 'b1010')],
    },
  );
  final c = ProviderContainer(
    overrides: <Override>[
      waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
      extraTranslatorsProvider.overrideWithValue(const [_ProTranslator()]),
      betaPeriodProvider.overrideWithValue(beta),
      if (tier != null)
        licenseTierProvider.overrideWithValue(tier)
      else
        licenseTierProvider.overrideWith((ref) => ref.watch(_tier)),
    ],
  )..listen(signalValuesAtCursorProvider, (_, _) {});
  addTearDown(c.dispose);
  c
      .read(signalGroupsProvider.notifier)
      .restoreFromSession(SignalGroup(entries: [_boundEntry]));
  return c;
}

String? _shown(ProviderContainer c) =>
    c.read(signalValuesAtCursorProvider)['top.bus']?.formatted;

LicenseTier? _withheld(ProviderContainer c) => c
    .read(translatorRegistryProvider)
    .withheldTier(_ProTranslator.translatorId);

void main() {
  group('TranslatorRegistry.withhold', () {
    test('a withheld id resolves to the built-in and says it is withheld', () {
      final registry = TranslatorRegistry()
        ..withhold(_ProTranslator.translatorId, LicenseTier.pro);
      expect(registry.isRegistered(_ProTranslator.translatorId), isFalse);
      expect(
        registry.resolve(_ProTranslator.translatorId).id,
        TranslatorRegistry.builtinId,
      );
      expect(
        registry.withheldTier(_ProTranslator.translatorId),
        LicenseTier.pro,
      );
      expect(registry.withheldTier('never.heard.of'), isNull);
    });

    test('registering the translator clears the record', () {
      final registry = TranslatorRegistry()
        ..withhold(_ProTranslator.translatorId, LicenseTier.pro)
        ..register(const _ProTranslator());
      expect(registry.withheldTier(_ProTranslator.translatorId), isNull);
      expect(
        registry.resolve(_ProTranslator.translatorId),
        isA<_ProTranslator>(),
      );
    });

    test('withholding never removes what already resolves under the id', () {
      final registry = TranslatorRegistry()
        ..withhold(TranslatorRegistry.builtinId, LicenseTier.pro);
      expect(registry.isRegistered(TranslatorRegistry.builtinId), isTrue);
    });
  });

  test('an untiered contributed translator registers at every tier', () {
    final c = ProviderContainer(
      overrides: [
        extraTranslatorsProvider.overrideWithValue(const [_OpenTranslator()]),
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWithValue(LicenseTier.openCore),
      ],
    );
    addTearDown(c.dispose);
    final registry = c.read(translatorRegistryProvider);
    expect(registry.get(_OpenTranslator.translatorId), isA<_OpenTranslator>());
    expect(registry.withheldTier(_OpenTranslator.translatorId), isNull);
  });

  group('Restored Pro translator binding — tier gate', () {
    test('Open Core during the beta: the Pro translator renders', () {
      final c = _restored(beta: true, tier: LicenseTier.openCore);
      expect(_shown(c), 'pro-translated');
      expect(_withheld(c), isNull);
    });

    test('Open Core after the beta: withheld, and the binding is kept', () {
      final c = _restored(beta: false, tier: LicenseTier.openCore);
      // The built-in formatter stands in, and the registry records why, which
      // is what the value column's lock reads.
      expect(_shown(c), 'a');
      expect(_withheld(c), LicenseTier.pro);
      expect(
        c.read(signalGroupsProvider).entries.single.translatorConfig,
        _boundEntry.translatorConfig,
      );
    });

    for (final tier in const [
      LicenseTier.edu,
      LicenseTier.pro,
      LicenseTier.enterprise,
    ]) {
      test('${tier.name} after the beta: the Pro translator renders', () {
        final c = _restored(beta: false, tier: tier);
        expect(_shown(c), 'pro-translated');
        expect(_withheld(c), isNull);
      });
    }

    test('a licence change mid-session follows, both ways', () {
      final c = _restored(beta: false);
      expect(_shown(c), 'a');

      c.read(_tier.notifier).tier = LicenseTier.pro;
      expect(_shown(c), 'pro-translated');
      expect(_withheld(c), isNull);

      c.read(_tier.notifier).tier = LicenseTier.openCore;
      expect(_shown(c), 'a');
      expect(_withheld(c), LicenseTier.pro);
    });
  });
}
