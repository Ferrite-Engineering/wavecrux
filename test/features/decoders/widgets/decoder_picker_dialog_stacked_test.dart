// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Verifies the picker UI affordances for stacked decoders documented in
// verification/VERIFICATION_GUIDE.md §5.10:
//   - parent-gating: stacked decoder hidden when its parent is not active
//   - dedicated "Stacked Decoders" section when a parent IS active
//   - "Stacks on <Parent>" badge on each stacked tile
//   - stacked decoder removed from its nominal category section

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

import '../../../helpers/product_telemetry_config.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Future<void> _pumpPicker(
  WidgetTester tester, {
  ProviderContainer? tabContainer,
  Locale? locale,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [productTelemetryConfig],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: DecoderPickerDialog(
            signalMap: const {},
            tabContainer: tabContainer,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps every visible `ExpansionTile` to expand it, so descendant rows
/// can be found by text.
Future<void> _expandAll(WidgetTester tester) async {
  final tiles = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile));
  final keys = [
    for (final t in tiles)
      if (t.key != null) t.key!,
  ];
  for (final k in keys) {
    await tester.tap(find.byKey(k));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    DecoderRegistry.instance
      ..clear()
      ..register(SpiDecoder.decoderDefinition, SpiDecoder.new)
      ..register(SpiFlashDecoder.decoderDefinition, SpiFlashDecoder.new);
  });
  tearDown(DecoderRegistry.instance.clear);

  group('DecoderPickerDialog stacked-decoders — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders the Stacked Decoders section in $locale without '
          'exceptions', (tester) async {
        final container = ProviderContainer(
          overrides: [productTelemetryConfig],
        );
        addTearDown(container.dispose);
        container
            .read(activeDecodersProvider.notifier)
            .addDecoder(
              'spi',
              const DecoderConfig(
                signalBindings: {
                  'sclk': 'tb.sclk',
                  'mosi': 'tb.mosi',
                },
              ),
            );

        await _pumpPicker(tester, tabContainer: container, locale: locale);
        await _expandAll(tester);

        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('no Stacked Decoders section when no parent decoder is active', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: [productTelemetryConfig]);
    addTearDown(container.dispose);
    // Sanity: container has no active decoders.
    expect(container.read(activeDecodersProvider), isEmpty);

    await _pumpPicker(tester, tabContainer: container);
    final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));

    // The stacked section header (via pickerCategoryHeader) should NOT
    // render anywhere in the dialog.
    expect(
      find.text(
        l10n.pickerCategoryHeader(l10n.decoderCategoryStacked, 1),
      ),
      findsNothing,
    );

    // The Serial Bus section exists (SPI is registered) but SPI Flash
    // must not appear under it — open all sections to confirm.
    await _expandAll(tester);
    expect(find.text('SPI'), findsOneWidget);
    expect(find.text('SPI Flash'), findsNothing);
  });

  testWidgets(
    'Stacked Decoders section appears with SPI Flash + "Stacks on SPI" '
    'badge when SPI is active; SPI Flash is removed from Serial Bus',
    (tester) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      // Inject an active SPI decoder instance into the tab container.
      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'spi',
            const DecoderConfig(
              signalBindings: {
                'sclk': 'tb.sclk',
                'mosi': 'tb.mosi',
              },
            ),
          );
      expect(container.read(activeDecodersProvider), hasLength(1));

      await _pumpPicker(tester, tabContainer: container);
      final l10n = L10N.of(tester.element(find.byType(DecoderPickerDialog)));

      // The Stacked Decoders section header should now render.
      final stackedHeader = l10n.pickerCategoryHeader(
        l10n.decoderCategoryStacked,
        1,
      );
      expect(find.text(stackedHeader), findsOneWidget);

      // Expand all sections, including the new Stacked one.
      await _expandAll(tester);

      // SPI Flash is now inside the Stacked Decoders section.
      expect(find.text('SPI Flash'), findsOneWidget);

      // The "Stacks on SPI" badge renders next to the SPI Flash entry.
      // The SPI decoder's display name is 'SPI' (no localization override).
      expect(find.text(l10n.decoderStacksOnBadge('SPI')), findsOneWidget);

      // SPI itself (the parent) is still listed under Serial Bus.
      expect(find.text('SPI'), findsOneWidget);
    },
  );

  testWidgets(
    'no PRO/ENT FeatureTierBadge renders on Open Core picker rows '
    '(parent SPI + stacked SPI Flash are both Open Core)',
    (tester) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      // Activate SPI so the Stacked Decoders section (with SPI Flash) renders
      // and both an Open Core parent and an Open Core stacked row are visible.
      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'spi',
            const DecoderConfig(
              signalBindings: {
                'sclk': 'tb.sclk',
                'mosi': 'tb.mosi',
              },
            ),
          );

      await _pumpPicker(tester, tabContainer: container);
      await _expandAll(tester);

      // Both rows are Open Core (requiredTier == LicenseTier.openCore), so the
      // picker must not paint a PRO/ENT WaveCruxFeatureTierBadge anywhere. This guards
      // the "Tier badge absent (Open Core)" verification row (§5.10) — a
      // regression where an Open Core decoder accidentally declares a Pro tier
      // would surface a stray chip here.
      expect(find.text('SPI'), findsOneWidget);
      expect(find.text('SPI Flash'), findsOneWidget);
      expect(find.byType(WaveCruxFeatureTierBadge), findsNothing);
    },
  );
}
