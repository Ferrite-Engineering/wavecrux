// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The decoder row of a decoder this seat's tier does not include. The run
// withholds it (active_decoders_tier_gate_test.dart); this is what the user
// sees instead of a silently empty lane.

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_list_entry.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

import '../../../helpers/product_telemetry_config.dart';

const _pro = DecoderDefinition(
  id: 'pro_stub',
  displayName: 'Pro Stub',
  description: '',
  requiredSignals: [],
  requiredTier: LicenseTier.pro,
);

const _enterprise = DecoderDefinition(
  id: 'ent_stub',
  displayName: 'Ent Stub',
  description: '',
  requiredSignals: [],
  requiredTier: LicenseTier.enterprise,
);

ActiveDecoder _decoder(String decoderId) => ActiveDecoder(
  id: 'decoder_0',
  decoderId: decoderId,
  config: const DecoderConfig(signalBindings: {}),
  instanceNumber: 1,
);

final Finder _proNotice = find.text('“Pro Stub #1” requires WaveCrux Pro.');
final Finder _proLabel = find.text('Pro Stub #1');

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
  String decoderId = 'pro_stub',
  double width = 360,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      productTelemetryConfig,
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
        theme: ThemeData(platform: TargetPlatform.macOS),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: DecoderListEntry(decoder: _decoder(decoderId), index: 0),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    DecoderRegistry.instance
      ..clear()
      ..register(_pro, (_) => throw UnimplementedError())
      ..register(_enterprise, (_) => throw UnimplementedError());
  });
  tearDown(DecoderRegistry.instance.clear);

  testWidgets('during the beta the row names the decoder', (tester) async {
    await _pump(tester, beta: true, tier: LicenseTier.openCore);
    expect(_proLabel, findsOneWidget);
    expect(_proNotice, findsNothing);
  });

  testWidgets('after the beta at Open Core the row says why it is empty', (
    tester,
  ) async {
    await _pump(tester, beta: false, tier: LicenseTier.openCore);
    expect(_proNotice, findsOneWidget);
    expect(_proLabel, findsNothing);
    expect(
      find.bySemanticsLabel('“Pro Stub #1” requires WaveCrux Pro.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow row keeps the sentence and does not overflow', (
    tester,
  ) async {
    await _pump(tester, beta: false, tier: LicenseTier.openCore, width: 110);
    expect(tester.takeException(), isNull);
    expect(_proNotice, findsOneWidget);
  });

  testWidgets('tapping the withheld row opens the upgrade dialog', (
    tester,
  ) async {
    await _pump(tester, beta: false, tier: LicenseTier.openCore);
    await tester.tap(_proNotice);
    await tester.pumpAndSettle();
    expect(find.text('Upgrade Required'), findsOneWidget);
  });

  testWidgets('after the beta at Pro the row names the decoder', (
    tester,
  ) async {
    await _pump(tester, beta: false, tier: LicenseTier.pro);
    expect(_proLabel, findsOneWidget);
    expect(_proNotice, findsNothing);
  });

  testWidgets('an Enterprise decoder at Pro names the tier it needs', (
    tester,
  ) async {
    await _pump(
      tester,
      beta: false,
      tier: LicenseTier.pro,
      decoderId: 'ent_stub',
    );
    expect(
      find.text('“Ent Stub #1” requires WaveCrux Enterprise.'),
      findsOneWidget,
    );
  });

  testWidgets('a licence change mid-session follows, both ways', (
    tester,
  ) async {
    final container = await _pump(tester, beta: false);
    expect(_proNotice, findsOneWidget);

    container.read(_tier.notifier).tier = LicenseTier.pro;
    await tester.pumpAndSettle();
    expect(_proLabel, findsOneWidget);
    expect(_proNotice, findsNothing);

    container.read(_tier.notifier).tier = LicenseTier.openCore;
    await tester.pumpAndSettle();
    expect(_proNotice, findsOneWidget);
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
