// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The value cell of a signal bound to a translator this seat's tier does not
// include. The registry withholds the translator
// (translator_registry_tier_gate_test.dart) and the built-in formatter stands
// in; this is the lock that says so beside the plain value.

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/extra_translator_presets_provider.dart';
import 'package:wavecrux/plugins/translator_preset.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../../helpers/product_telemetry_config.dart';

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

TranslatorPreset _preset(String format, String label) => TranslatorPreset(
  id: 'pro.fake.$format',
  labelResolver: (_) => label,
  icon: Icons.palette_outlined,
  configBuilder: () => <String, Object?>{
    kTranslatorIdConfigKey: _ProTranslator.translatorId,
    'format': format,
  },
  requiredTier: LicenseTier.pro,
);

final List<TranslatorPreset> _presets = [
  _preset('a', 'Fake Alpha'),
  _preset('b', 'Fake Beta'),
];

SignalEntry _entry(String format) => SignalEntry.signal(
  signalRef: 'top.bus',
  displayName: 'bus',
  translatorConfig: {
    kTranslatorIdConfigKey: _ProTranslator.translatorId,
    'format': format,
  },
);

const _alphaSentence = '“Fake Alpha” requires WaveCrux Pro.';

/// A `licenseTierProvider` source a test can change after the scope is
/// built, the way a stored licence resolves after startup.
final _tier = NotifierProvider<_TierNotifier, LicenseTier>(_TierNotifier.new);

class _TierNotifier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get tier => state;
  set tier(LicenseTier value) => state = value;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool beta,
  LicenseTier? tier,
  String format = 'a',
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      productTelemetryConfig,
      deviceClassProvider.overrideWithValue(DeviceClass.desktop),
      extraTranslatorsProvider.overrideWithValue(const [_ProTranslator()]),
      extraTranslatorPresetsProvider.overrideWithValue(_presets),
      betaPeriodProvider.overrideWithValue(beta),
      if (tier != null)
        licenseTierProvider.overrideWithValue(tier)
      else
        licenseTierProvider.overrideWith((ref) => ref.watch(_tier)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: ValueColumnRow(
              entry: _entry(format),
              signalValue: const SignalValue(formatted: 'a', rawValue: '1010'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('during the beta there is no lock', (tester) async {
    await _pump(tester, beta: true, tier: LicenseTier.openCore);
    expect(find.bySemanticsLabel(_alphaSentence), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('after the beta at Open Core the value carries a lock that says '
      'why', (tester) async {
    await _pump(tester, beta: false, tier: LicenseTier.openCore);
    // The plain value is still shown; the lock stands beside it.
    expect(find.text('a'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.bySemanticsLabel(_alphaSentence), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lock names the preset the binding came from', (
    tester,
  ) async {
    await _pump(tester, beta: false, tier: LicenseTier.openCore, format: 'b');
    expect(
      find.bySemanticsLabel('“Fake Beta” requires WaveCrux Pro.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the lock opens the upgrade dialog', (tester) async {
    await _pump(tester, beta: false, tier: LicenseTier.openCore);
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade Required'), findsOneWidget);
  });

  testWidgets('after the beta at Pro there is no lock', (tester) async {
    await _pump(tester, beta: false, tier: LicenseTier.pro);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('a licence change mid-session follows, both ways', (
    tester,
  ) async {
    final container = await _pump(tester, beta: false);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    container.read(_tier.notifier).tier = LicenseTier.pro;
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsNothing);

    container.read(_tier.notifier).tier = LicenseTier.openCore;
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  group('presetForBinding', () {
    test('picks the preset whose configuration the binding carries', () {
      final config = _entry('b').translatorConfig!;
      expect(presetForBinding(_presets, config)?.id, 'pro.fake.b');
    });

    test('falls back to a preset binding the same translator', () {
      const config = {kTranslatorIdConfigKey: _ProTranslator.translatorId};
      expect(presetForBinding(_presets, config)?.id, 'pro.fake.a');
    });

    test('is null for a translator no preset binds', () {
      const config = {kTranslatorIdConfigKey: 'other.id'};
      expect(presetForBinding(_presets, config), isNull);
    });
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('the withheld state renders in $locale', (tester) async {
        await _pump(
          tester,
          beta: false,
          tier: LicenseTier.openCore,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      });
    }
  });
}
