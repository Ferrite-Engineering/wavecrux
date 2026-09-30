// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// Captures recorded events for the telemetry assertions below.
class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [productTelemetryConfig, ...overrides],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

Future<void> _pumpDialog(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              DecoderPickerDialog.show(context, signalMap: const {}),
          child: const Text('open'),
        ),
      ),
      overrides: overrides,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Taps every `ExpansionTile` in the picker once to open it. Categories
/// now default to collapsed so tests that assert on individual decoder
/// rows must call this after [_pumpDialog].
///
/// After each tap the just-expanded section's children push later
/// sections below the dialog fold; [scrollUntilVisible] brings the
/// next section back into the visible region of the dialog's
/// [SingleChildScrollView] before tapping it.
Future<void> _expandAllSections(WidgetTester tester) async {
  final keys = <Key>[
    for (final tile in tester.widgetList<ExpansionTile>(
      find.byType(ExpansionTile),
    ))
      if (tile.key != null) tile.key!,
  ];
  final scrollable = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(Scrollable),
  );
  for (final key in keys) {
    final finder = find.byKey(key);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(finder, 80, scrollable: scrollable);
    }
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(DecoderRegistry.instance.clear);
  tearDown(DecoderRegistry.instance.clear);

  group('DecoderPickerDialog — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [productTelemetryConfig],
            child: MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const Scaffold(body: DecoderPickerDialog(signalMap: {})),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DecoderPickerDialog — empty state', () {
    testWidgets('shows empty state text when no decoders registered', (
      tester,
    ) async {
      await _pumpDialog(tester);
      final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));
      expect(find.text(l10n.decoderPickerEmptyState), findsOneWidget);
    });

    testWidgets('shows dialog title', (tester) async {
      await _pumpDialog(tester);
      final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));
      expect(find.text(l10n.decoderPickerTitle), findsOneWidget);
    });
  });

  group('DecoderPickerDialog — with decoders', () {
    testWidgets('lists registered decoder by display name', (tester) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      await _expandAllSections(tester);
      expect(
        find.text(SpiDecoder.decoderDefinition.displayName),
        findsOneWidget,
      );
    });

    testWidgets('shows description for registered decoder', (tester) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      await _expandAllSections(tester);
      expect(
        find.text(SpiDecoder.decoderDefinition.description),
        findsOneWidget,
      );
    });

    testWidgets('lists multiple registered decoders', (tester) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      const stubDef = DecoderDefinition(
        id: 'stub',
        displayName: 'Stub Decoder',
        description: 'A stub',
        requiredSignals: [SignalBinding(name: 'sig', description: 'test')],
      );
      DecoderRegistry.instance.register(
        stubDef,
        (_) => throw UnimplementedError(),
      );
      await _pumpDialog(tester);
      await _expandAllSections(tester);
      expect(
        find.text(SpiDecoder.decoderDefinition.displayName),
        findsOneWidget,
      );
      expect(find.text('Stub Decoder'), findsOneWidget);
    });

    testWidgets('tapping a decoder closes picker dialog', (tester) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      await _expandAllSections(tester);
      await tester.tap(find.text(SpiDecoder.decoderDefinition.displayName));
      await tester.pumpAndSettle();
      expect(find.byType(DecoderPickerDialog), findsNothing);
    });

    testWidgets('Cancel button closes the dialog', (tester) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));
      // The dialog uses MaterialLocalizations.cancelButtonLabel.
      expect(find.byType(DecoderPickerDialog), findsOneWidget);
      await tester.tap(find.text(l10n.decoderConfigCancelButton).last);
      await tester.pumpAndSettle();
      // Use a more general approach — dialog should not be visible.
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('DecoderPickerDialog — tier badge', () {
    const proDef = DecoderDefinition(
      id: 'fake_pro',
      displayName: 'Fake Pro Decoder',
      description: 'Pro-tier fixture',
      requiredSignals: [SignalBinding(name: 'sig', description: 't')],
      requiredTier: LicenseTier.pro,
    );

    testWidgets('renders FeatureTierBadge for a Pro-tier decoder', (
      tester,
    ) async {
      DecoderRegistry.instance.register(
        proDef,
        (_) => throw UnimplementedError(),
      );
      // Register SPI alongside Pro so a single expansion exposes both
      // rows; calling _expandAllSections twice would toggle the
      // already-open section back to collapsed.
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      await _expandAllSections(tester);
      // Only the Pro row paints a badge; SPI is open-core.
      expect(find.byType(WaveCruxFeatureTierBadge), findsOneWidget);
    });

    testWidgets('renders no FeatureTierBadge for open-core decoders', (
      tester,
    ) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      await _expandAllSections(tester);
      expect(find.byType(WaveCruxFeatureTierBadge), findsNothing);
    });
  });

  group('DecoderPickerDialog — category grouping', () {
    testWidgets('renders one ExpansionTile per populated category', (
      tester,
    ) async {
      // SPI + I2C are both serial → one ExpansionTile only.
      DecoderRegistry.instance
        ..register(SpiDecoder.decoderDefinition, SpiDecoder.new)
        ..register(I2cDecoder.decoderDefinition, I2cDecoder.new);
      await _pumpDialog(tester);
      expect(find.byType(ExpansionTile), findsOneWidget);
    });

    testWidgets('renders multiple ExpansionTiles when categories differ', (
      tester,
    ) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      const ambaStub = DecoderDefinition(
        id: 'apb_stub',
        displayName: 'APB Stub',
        description: 'AMBA stub',
        requiredSignals: [SignalBinding(name: 'clk', description: 't')],
        category: DecoderCategory.amba,
      );
      DecoderRegistry.instance.register(
        ambaStub,
        (_) => throw UnimplementedError(),
      );
      await _pumpDialog(tester);
      // Two ExpansionTiles, one per populated category.
      expect(find.byType(ExpansionTile), findsNWidgets(2));
    });

    testWidgets('renders the localized category label in section header', (
      tester,
    ) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));
      // Header is "Serial Bus (1)" via pickerCategoryHeader format.
      final expected = l10n.pickerCategoryHeader(l10n.decoderCategorySerial, 1);
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('omits empty categories', (tester) async {
      // Register a serial decoder only — no AMBA, no Ethernet, etc.
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));
      // Other category labels do NOT appear.
      expect(find.text(l10n.decoderCategoryAmba), findsNothing);
      expect(find.text(l10n.decoderCategoryEthernet), findsNothing);
      expect(find.text(l10n.decoderCategoryHighSpeed), findsNothing);
    });

    testWidgets('all categories initially collapsed — children hidden', (
      tester,
    ) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);
      // SPI's display name is hidden until the user opens the section.
      expect(
        find.text(SpiDecoder.decoderDefinition.displayName),
        findsNothing,
      );
    });

    testWidgets('tapping a collapsed section header expands it, tapping again '
        'collapses (collapse/expand toggle works)', (tester) async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      await _pumpDialog(tester);

      // Initially collapsed → SPI row hidden.
      expect(
        find.text(SpiDecoder.decoderDefinition.displayName),
        findsNothing,
      );

      // Tap the only ExpansionTile (Serial Bus). The picker dialog renders
      // one ExpansionTile per populated category; with only SPI registered,
      // there's exactly one. Tapping the tile body toggles its expansion.
      // Targeting the visible category-header text via
      // `pickerCategoryHeader` is the stable finder.
      final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));
      final headerText = l10n.pickerCategoryHeader(
        l10n.decoderCategorySerial,
        1,
      );
      await tester.tap(find.text(headerText));
      await tester.pumpAndSettle();

      // After expand, SPI row becomes visible.
      expect(
        find.text(SpiDecoder.decoderDefinition.displayName),
        findsOneWidget,
        reason: 'tapping a collapsed section header should expand it',
      );

      // Tap again to collapse.
      await tester.tap(find.text(headerText));
      await tester.pumpAndSettle();

      expect(
        find.text(SpiDecoder.decoderDefinition.displayName),
        findsNothing,
        reason: 'tapping an expanded section header should collapse it',
      );
    });
  });

  group('DecoderPickerDialog — feature gate', () {
    const proDef = DecoderDefinition(
      id: 'fake_pro',
      displayName: 'Fake Pro Decoder',
      description: 'Pro-tier fixture',
      requiredSignals: [SignalBinding(name: 'sig', description: 't')],
      requiredTier: LicenseTier.pro,
    );

    testWidgets('beta-period: Open Core tier still opens the config dialog '
        '(FeatureGate short-circuits)', (tester) async {
      DecoderRegistry.instance.register(
        proDef,
        (_) => throw UnimplementedError(),
      );
      // Open-core default tier is openCore. Pinned to the beta, activation
      // succeeds even though openCore does not satisfy LicenseTier.pro.
      await _pumpDialog(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(true)],
      );
      await _expandAllSections(tester);

      // Tap the Pro decoder row.
      await tester.tap(find.text(proDef.displayName));
      await tester.pumpAndSettle();

      // Picker dialog closed (gate passed → Navigator.pop). If the gate had
      // blocked, the picker would still be visible and an upgrade dialog
      // would be stacked on top.
      expect(find.byType(DecoderPickerDialog), findsNothing);
      // The dialog count: only the config dialog is open (1 AlertDialog),
      // not picker + upgrade dialog (would be 2).
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  // `tier.gate_hit` — which locked features drive upgrade
  // intent, and from which tier. Only the DENIAL is instrumented here; the
  // allowed path is already counted by `decoder.opened` at `addDecoder`.
  group('DecoderPickerDialog — telemetry', () {
    const proDef = DecoderDefinition(
      id: 'fake_pro',
      displayName: 'Fake Pro Decoder',
      description: 'Pro-tier fixture',
      requiredSignals: [SignalBinding(name: 'sig', description: 't')],
      requiredTier: LicenseTier.pro,
    );

    testWidgets('a post-beta sub-Pro tap records tier.gate_hit', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetry();
      DecoderRegistry.instance.register(
        proDef,
        (_) => throw UnimplementedError(),
      );
      await _pumpDialog(
        tester,
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWithValue(LicenseTier.openCore),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      await _expandAllSections(tester);
      await tester.tap(find.text(proDef.displayName));
      await tester.pumpAndSettle();

      expect(telemetry.named('tier.gate_hit'), hasLength(1));
      // A closed call-site id, not the decoder id and never the localized
      // decoder name the upgrade dialog renders.
      expect(telemetry.named('tier.gate_hit').single.properties, {
        'feature': 'decoder_pack',
        'required': 'pro',
      });
      // `badge.click` rides along, from inside `WaveCruxUpgradeDialog.show`.
      // Not a duplicate: `tier.gate_hit` answers *which* locked feature drives
      // intent and has no impression counterpart, while `badge.click` shares
      // its `tier` dimension with `badge.impression` so the ratio the badge
      // funnel needs is computable. See the catalog entries for both.
      expect(telemetry.named('badge.click').single.properties, {'tier': 'pro'});
      expect(
        telemetry.events.map((e) => e.name).toSet(),
        {'tier.gate_hit', 'badge.click', 'badge.impression'},
      );
    });

    testWidgets('the beta short-circuit records nothing', (tester) async {
      final telemetry = _RecordingTelemetry();
      DecoderRegistry.instance.register(
        proDef,
        (_) => throw UnimplementedError(),
      );
      await _pumpDialog(
        tester,
        overrides: [
          betaPeriodProvider.overrideWithValue(true),
          licenseTierProvider.overrideWithValue(LicenseTier.openCore),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      await _expandAllSections(tester);
      await tester.tap(find.text(proDef.displayName));
      await tester.pumpAndSettle();

      expect(
        telemetry.events.where((e) => e.name == 'tier.gate_hit'),
        isEmpty,
      );
    });

    testWidgets('merely rendering the gated row records nothing', (
      tester,
    ) async {
      // `FeatureGate.satisfiesTier` is a pure predicate evaluated in build();
      // instrumenting there would fire on every rebuild. Expanding the
      // sections rebuilds every tile, so this asserts the absence.
      //
      // `badge.impression` is the deliberate exception and is excluded below:
      // a badge becoming visible IS the event, and it is deduplicated to once
      // per tier per session in `TierBadgeImpressionNotifier` rather than in
      // the render path — which is what keeps the rebuild storm this test
      // provokes from inflating it.
      final telemetry = _RecordingTelemetry();
      DecoderRegistry.instance.register(
        proDef,
        (_) => throw UnimplementedError(),
      );
      await _pumpDialog(
        tester,
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWithValue(LicenseTier.openCore),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      await _expandAllSections(tester);

      expect(
        telemetry.events.where((e) => e.name != 'badge.impression'),
        isEmpty,
      );
      // …and the impression fires exactly once despite every tile rebuilding.
      expect(telemetry.named('badge.impression'), hasLength(1));
    });
  });
}
