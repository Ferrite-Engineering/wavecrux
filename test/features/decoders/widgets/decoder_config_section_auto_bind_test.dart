// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_auto_bind_preview_dialog.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_section.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/inspector_test_host.dart';

// ── fixtures ──────────────────────────────────────────────────────────────────

const _spiDef = DecoderDefinition(
  id: 'spi',
  displayName: 'SPI',
  description: 'Serial Peripheral Interface',
  requiredSignals: [
    SignalBinding(name: 'sclk', description: 'Clock', bitWidth: 1),
    SignalBinding(name: 'mosi', description: 'Master Out', bitWidth: 1),
  ],
  optionalSignals: [
    SignalBinding(name: 'miso', description: 'Master In', bitWidth: 1),
    SignalBinding(name: 'cs', description: 'Chip Select', bitWidth: 1),
  ],
);

const _axiLite = DecoderDefinition(
  id: 'axi4_lite',
  displayName: 'AXI4-Lite',
  description: 'AXI4-Lite',
  requiredSignals: [
    SignalBinding(name: 'aclk', description: 'Clock', bitWidth: 1),
    SignalBinding(name: 'aresetn', description: 'Reset', bitWidth: 1),
    SignalBinding(name: 'awvalid', description: 'AW Valid', bitWidth: 1),
    SignalBinding(name: 'awready', description: 'AW Ready', bitWidth: 1),
  ],
);

Map<String, Variable> _signals(List<String> paths) =>
    inspectorTestSignals([for (final p in paths) inspectorTestVar(p)]);

// ── helpers ───────────────────────────────────────────────────────────────────

/// The Inspector on a new decoder of [definition], as the picker opens it.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required DecoderDefinition definition,
  required Map<String, Variable> signals,
  Locale? locale,
  Size surface = const Size(1000, 1000),
}) async {
  registerInspectorTestDecoder(definition);
  final container = await pumpInspectorHost(
    tester,
    signals: signals,
    locale: locale,
    surface: surface,
  );
  await startNewDecoder(tester, container, definition);
  return container;
}

L10N _l10n(WidgetTester tester) =>
    L10N.of(tester.element(find.byType(DecoderConfigSection)));

Finder get _add => find.descendant(
  of: find.byType(CruxInspectorApplyBar),
  matching: find.byType(FilledButton),
);

void main() {
  group('Auto-bind button — enabled state', () {
    testWidgets('button is disabled when no signals are loaded', (
      tester,
    ) async {
      await _pump(tester, definition: _spiDef, signals: const {});
      final l10n = _l10n(tester);
      final finder = find.widgetWithText(
        TextButton,
        l10n.decoderConfigAutoBindButton,
      );
      expect(finder, findsOneWidget);
      expect(tester.widget<TextButton>(finder).onPressed, isNull);
    });

    testWidgets('button is enabled when signals are loaded', (tester) async {
      await _pump(
        tester,
        definition: _spiDef,
        signals: _signals(['tb.sclk', 'tb.mosi']),
      );
      final l10n = _l10n(tester);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l10n.decoderConfigAutoBindButton),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('Auto-bind preview dialog open / close', () {
    testWidgets('pressing Auto-bind opens the preview dialog', (tester) async {
      await _pump(
        tester,
        definition: _spiDef,
        signals: _signals(['tb.sclk', 'tb.mosi']),
      );
      final l10n = _l10n(tester);

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      expect(find.byType(DecoderAutoBindPreviewDialog), findsOneWidget);
      expect(
        find.text(l10n.decoderAutoBindPreviewTitle(_spiDef.displayName)),
        findsOneWidget,
      );
    });

    testWidgets('Cancel closes the preview without applying', (tester) async {
      await _pump(
        tester,
        definition: _spiDef,
        signals: _signals(['tb.sclk', 'tb.mosi']),
      );
      final l10n = _l10n(tester);

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(DecoderAutoBindPreviewDialog),
          matching: find.text(l10n.decoderAutoBindCancelButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DecoderAutoBindPreviewDialog), findsNothing);
      // The Inspector still shows the new decoder.
      expect(find.byType(DecoderConfigSection), findsOneWidget);
    });
  });

  group('Auto-bind preview summary', () {
    testWidgets('summary shows expected counts for SPI', (tester) async {
      // 2 required (sclk, mosi) + 2 optional (miso, cs). All four resolve
      // exactly when leaf names match the binding names.
      await _pump(
        tester,
        definition: _spiDef,
        signals: _signals(['tb.sclk', 'tb.mosi', 'tb.miso', 'tb.cs']),
      );
      final l10n = _l10n(tester);

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.decoderAutoBindSummary(4, 0, 0, 4)),
        findsOneWidget,
      );
    });
  });

  group('Apply all populates the bindings', () {
    testWidgets('clicking Apply all then Add Decoder activates with bindings', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        definition: _spiDef,
        signals: _signals(['tb.sclk', 'tb.mosi', 'tb.miso', 'tb.cs']),
      );
      final l10n = _l10n(tester);

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.decoderAutoBindApplyAllButton));
      await tester.pumpAndSettle();
      expect(find.byType(DecoderAutoBindPreviewDialog), findsNothing);

      await tester.tap(_add);
      await tester.pumpAndSettle();

      final actives = container.read(activeDecodersProvider);
      expect(actives, hasLength(1));
      expect(actives.first.config.signalBindings['sclk'], 'tb.sclk');
      expect(actives.first.config.signalBindings['mosi'], 'tb.mosi');
      expect(actives.first.config.signalBindings['miso'], 'tb.miso');
      expect(actives.first.config.signalBindings['cs'], 'tb.cs');
    });
  });

  group('Apply confirmed only excludes fuzzy candidates', () {
    testWidgets('fuzzy candidates are not applied', (tester) async {
      // sclk + mosi resolve exactly; miso has only a typo'd 'misoo'
      // available, which the algorithm matches with fuzzyMatch confidence.
      // cs is absent, so noMatch.
      final container = await _pump(
        tester,
        definition: _spiDef,
        signals: _signals(['tb.sclk', 'tb.mosi', 'tb.misoo']),
      );
      final l10n = _l10n(tester);

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.decoderAutoBindApplyConfirmedOnlyButton));
      await tester.pumpAndSettle();

      await tester.tap(_add);
      await tester.pumpAndSettle();

      final actives = container.read(activeDecodersProvider);
      expect(actives, hasLength(1));
      expect(actives.first.config.signalBindings['sclk'], 'tb.sclk');
      expect(actives.first.config.signalBindings['mosi'], 'tb.mosi');
      expect(actives.first.config.signalBindings.containsKey('miso'), isFalse);
    });
  });

  group('Manually pre-bound signals are not overwritten', () {
    testWidgets('pre-existing binding survives Auto-bind preview Apply all', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        definition: _spiDef,
        signals: _signals(['tb.sclk', 'tb.foo_clk', 'tb.mosi']),
      );
      final l10n = _l10n(tester);

      // Manually bind sclk to tb.foo_clk: the first picker is the sclk row.
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('tb.foo_clk').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.decoderAutoBindApplyAllButton));
      await tester.pumpAndSettle();

      await tester.tap(_add);
      await tester.pumpAndSettle();

      final actives = container.read(activeDecodersProvider);
      expect(actives, hasLength(1));
      expect(actives.first.config.signalBindings['sclk'], 'tb.foo_clk');
      expect(actives.first.config.signalBindings['mosi'], 'tb.mosi');
    });
  });

  group('Ambiguous-prefix banner', () {
    testWidgets(
      'banner appears with two AXI buses; selecting prefix re-runs algorithm',
      (tester) async {
        await _pump(
          tester,
          definition: _axiLite,
          signals: _signals([
            'tb.dut.m_axi_aclk',
            'tb.dut.m_axi_aresetn',
            'tb.dut.m_axi_awvalid',
            'tb.dut.m_axi_awready',
            'tb.dut.s_axi_aclk',
            'tb.dut.s_axi_aresetn',
            'tb.dut.s_axi_awvalid',
            'tb.dut.s_axi_awready',
          ]),
        );
        final l10n = _l10n(tester);

        await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
        await tester.pumpAndSettle();

        expect(find.text(l10n.decoderAutoBindAmbiguousBanner), findsOneWidget);
        expect(
          find.text(l10n.decoderAutoBindPrefixDropdownLabel),
          findsOneWidget,
        );
        expect(find.text('m_axi_'), findsOneWidget);

        final prefixDropdown = find.descendant(
          of: find.byType(DecoderAutoBindPreviewDialog),
          matching: find.byType(DropdownButton<String>),
        );
        expect(prefixDropdown, findsOneWidget);
        await tester.tap(prefixDropdown);
        await tester.pumpAndSettle();
        expect(find.text('s_axi_'), findsWidgets);
        await tester.tap(find.text('s_axi_').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text(l10n.decoderAutoBindApplyAllButton));
        await tester.pumpAndSettle();

        // The Inspector's pickers show the s_axi_ paths, one per binding.
        final dropdowns = find.byType(DropdownButton<String>);
        expect(dropdowns, findsNWidgets(_axiLite.requiredSignals.length));
        expect(find.text('tb.dut.s_axi_aclk'), findsOneWidget);
        expect(find.text('tb.dut.s_axi_awvalid'), findsOneWidget);
      },
    );
  });

  group('Locale sweep', () {
    for (final localeCode in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('$localeCode renders without overflow at tablet width', (
        tester,
      ) async {
        await _pump(
          tester,
          definition: _spiDef,
          signals: _signals(['tb.sclk', 'tb.mosi']),
          locale: Locale(localeCode),
          surface: const Size(900, 700),
        );
        await tester.tap(
          find.text(_l10n(tester).decoderConfigAutoBindButton),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DecoderAutoBindPreviewDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
