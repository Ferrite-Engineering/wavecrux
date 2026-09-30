// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/features/settings/providers/custom_translators_provider.dart';
import 'package:wavecrux/features/viewer/widgets/bind_custom_translator_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/extra_translator_presets_provider.dart';
import 'package:wavecrux/plugins/translator_preset.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

import '../../../helpers/product_telemetry_config.dart';

/// Captures recorded events for the telemetry assertions below.
class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

class _Seeded extends CustomTranslators {
  _Seeded(this._seed);
  final List<CustomTranslatorDef> _seed;
  @override
  List<CustomTranslatorDef> build() => _seed;
}

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Future<Map<String, Object?>? Function()> _open(
  WidgetTester tester,
  List<CustomTranslatorDef> seed, {
  List<TranslatorPreset> presets = const [],
  List<Override> extraOverrides = const [],
  Locale? locale,
}) async {
  Map<String, Object?>? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productTelemetryConfig,
        customTranslatorsProvider.overrideWith(() => _Seeded(seed)),
        extraTranslatorPresetsProvider.overrideWithValue(presets),
        ...extraOverrides,
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await BindCustomTranslatorDialog.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

TranslatorPreset _proPreset() => TranslatorPreset(
  id: 'pro.demo',
  labelResolver: (_) => 'Demo Pro Translator',
  descriptionResolver: (_) => 'demo subtitle',
  icon: Icons.bolt,
  configBuilder: () => const <String, Object?>{
    'translator': 'pro.demo',
    'demo': true,
  },
  requiredTier: LicenseTier.pro,
);

void main() {
  group('BindCustomTranslatorDialog — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await _open(
          tester,
          const [
            CustomTranslatorDef(
              name: 'AXI ARSIZE',
              config: BitfieldTranslatorConfig(
                fields: [
                  BitFieldSpec(name: 'size', hiBit: 2, loBit: 0),
                ],
              ),
            ),
          ],
          presets: [_proPreset()],
          locale: locale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('binding RISC-V returns the riscvDisasm marker', (tester) async {
    final get = await _open(tester, const []);
    await tester.tap(find.text('RISC-V disassembly'));
    await tester.pumpAndSettle();
    expect(get()?['translator'], 'builtin.riscvDisasm');
  });

  testWidgets('binding a custom translator returns its bitfield config', (
    tester,
  ) async {
    final get = await _open(tester, const [
      CustomTranslatorDef(
        name: 'AXI ARSIZE',
        config: BitfieldTranslatorConfig(
          fields: [
            BitFieldSpec(name: 'size', hiBit: 2, loBit: 0),
          ],
        ),
      ),
    ]);
    await tester.tap(find.text('AXI ARSIZE'));
    await tester.pumpAndSettle();
    final config = get();
    expect(config?['translator'], 'builtin.bitfield');
    expect(config?['fields'], isA<List<Object?>>());
  });

  testWidgets('empty state explains how to author translators', (tester) async {
    await _open(tester, const []);
    expect(
      find.textContaining('No custom translators'),
      findsOneWidget,
    );
  });

  testWidgets('contributed Pro preset renders with a tier badge', (
    tester,
  ) async {
    await _open(tester, const [], presets: [_proPreset()]);
    expect(find.text('Demo Pro Translator'), findsOneWidget);
    expect(find.text('demo subtitle'), findsOneWidget);
    // The PRO badge renders from the preset's requiredTier.
    expect(find.byType(WaveCruxFeatureTierBadge), findsOneWidget);
  });

  testWidgets('tapping a Pro preset during beta returns its config', (
    tester,
  ) async {
    // The beta short-circuit allows binding at any tier; pinned here rather
    // than read from the build, which has ended the beta.
    final get = await _open(
      tester,
      const [],
      presets: [_proPreset()],
      extraOverrides: [betaPeriodProvider.overrideWithValue(true)],
    );
    await tester.tap(find.text('Demo Pro Translator'));
    await tester.pumpAndSettle();
    final config = get();
    expect(config?['translator'], 'pro.demo');
    expect(config?['demo'], isTrue);
  });

  testWidgets('post-beta, tapping a Pro preset without the tier shows the '
      'upgrade dialog instead of binding', (tester) async {
    final get = await _open(
      tester,
      const [],
      presets: [_proPreset()],
      extraOverrides: [
        // Flip off the beta short-circuit and run as Open Core so the gate
        // denies — exercises the post-beta-correctness path.
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWithValue(LicenseTier.openCore),
      ],
    );
    await tester.tap(find.text('Demo Pro Translator'));
    await tester.pumpAndSettle();
    // The bind dialog did not pop with a config; an upgrade dialog appeared.
    expect(get(), isNull);
    expect(find.textContaining('Required'), findsOneWidget);
  });

  // ── telemetry ─────────────────────────────────────────────────────────────
  //
  // `translator.preset_bound` — which Pro translator family justifies
  // the pack — and `tier.gate_hit` — which locked features
  // drive upgrade intent.

  testWidgets('binding a Pro preset records its family, not its id', (
    tester,
  ) async {
    final telemetry = _RecordingTelemetry();
    await _open(
      tester,
      const [],
      presets: [_proPreset()],
      extraOverrides: [
        // Binding a Pro preset needs a seat that holds Pro.
        licenseTierProvider.overrideWithValue(LicenseTier.pro),
        telemetryServiceProvider.overrideWithValue(telemetry),
      ],
    );
    await tester.tap(find.text('Demo Pro Translator'));
    await tester.pumpAndSettle();

    final bound = telemetry.named('translator.preset_bound');
    expect(bound, hasLength(1));
    // The registry id's last segment, lowercased — never the preset id and
    // never the localized label.
    expect(bound.single.properties, {'family': 'demo'});
    expect(
      bound.single.properties['family'],
      matches(RegExp(r'^[a-z0-9_]{1,64}$')),
    );
  });

  testWidgets('the built-in RISC-V row is not a preset and records nothing', (
    tester,
  ) async {
    final telemetry = _RecordingTelemetry();
    await _open(
      tester,
      const [],
      extraOverrides: [
        telemetryServiceProvider.overrideWithValue(telemetry),
      ],
    );
    await tester.tap(find.text('RISC-V disassembly'));
    await tester.pumpAndSettle();

    expect(telemetry.events, isEmpty);
  });

  testWidgets('a denied Pro preset records tier.gate_hit, not a bind', (
    tester,
  ) async {
    final telemetry = _RecordingTelemetry();
    await _open(
      tester,
      const [],
      presets: [_proPreset()],
      extraOverrides: [
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWithValue(LicenseTier.openCore),
        telemetryServiceProvider.overrideWithValue(telemetry),
      ],
    );
    await tester.tap(find.text('Demo Pro Translator'));
    await tester.pumpAndSettle();

    expect(telemetry.named('tier.gate_hit'), hasLength(1));
    expect(telemetry.named('tier.gate_hit').single.properties, {
      'feature': 'translator_preset',
      'required': 'pro',
    });
    // `badge.click` rides along from `WaveCruxUpgradeDialog.show` — the badge
    // funnel's other half, sharing its `tier` dimension with
    // `badge.impression` so the two produce a ratio rather than two counts.
    expect(telemetry.named('badge.click').single.properties, {'tier': 'pro'});
    expect(telemetry.named('translator.preset_bound'), isEmpty);
  });

  testWidgets('the beta short-circuit records no tier.gate_hit', (
    tester,
  ) async {
    final telemetry = _RecordingTelemetry();
    await _open(
      tester,
      const [],
      presets: [_proPreset()],
      extraOverrides: [
        betaPeriodProvider.overrideWithValue(true),
        licenseTierProvider.overrideWithValue(LicenseTier.openCore),
        telemetryServiceProvider.overrideWithValue(telemetry),
      ],
    );
    await tester.tap(find.text('Demo Pro Translator'));
    await tester.pumpAndSettle();

    // During the beta the gate short-circuits to allow, so the upgrade
    // dialog, and therefore this event, is unreachable.
    expect(telemetry.named('tier.gate_hit'), isEmpty);
  });
}
