// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_auto_bind_preview_dialog.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/product_telemetry_config.dart';

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

Variable _v(String fullPath, {int bitWidth = 1}) {
  final lastDot = fullPath.lastIndexOf('.');
  final name = lastDot < 0 ? fullPath : fullPath.substring(lastDot + 1);
  final scope = lastDot < 0 ? '' : fullPath.substring(0, lastDot);
  return Variable(
    name: name,
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: fullPath,
    scopePath: scope,
    bitWidth: bitWidth,
  );
}

Map<String, Variable> _signals(List<Variable> vars) => {
  for (final v in vars) v.signalRef: v,
};

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _wrap({
  required DecoderDefinition definition,
  required Map<String, Variable> signalMap,
  Locale? locale,
  Size? surfaceSize,
}) {
  final app = ProviderScope(
    overrides: [
      productTelemetryConfig,
      signalVariablesMapProvider.overrideWith((ref) => signalMap),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: DecoderConfigDialog(definition: definition)),
    ),
  );
  if (surfaceSize == null) return app;
  return MediaQuery(
    data: MediaQueryData(size: surfaceSize),
    child: app,
  );
}

void main() {
  group('Auto-bind button — enabled state', () {
    testWidgets('button is disabled when signalMap is empty', (tester) async {
      await tester.pumpWidget(_wrap(definition: _spiDef, signalMap: {}));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      final finder = find.widgetWithText(
        TextButton,
        l10n.decoderConfigAutoBindButton,
      );
      expect(finder, findsOneWidget);
      final button = tester.widget<TextButton>(finder);
      expect(button.onPressed, isNull);
    });

    testWidgets('button is enabled when signals are loaded', (tester) async {
      final signals = _signals([_v('tb.sclk'), _v('tb.mosi')]);
      await tester.pumpWidget(_wrap(definition: _spiDef, signalMap: signals));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l10n.decoderConfigAutoBindButton),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('Auto-bind preview dialog open / close', () {
    testWidgets('pressing Auto-bind opens the preview dialog', (tester) async {
      final signals = _signals([_v('tb.sclk'), _v('tb.mosi')]);
      await tester.pumpWidget(_wrap(definition: _spiDef, signalMap: signals));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      expect(find.byType(DecoderAutoBindPreviewDialog), findsOneWidget);
      expect(
        find.text(l10n.decoderAutoBindPreviewTitle(_spiDef.displayName)),
        findsOneWidget,
      );
    });

    testWidgets('Cancel closes the preview without applying', (tester) async {
      final signals = _signals([_v('tb.sclk'), _v('tb.mosi')]);
      await tester.pumpWidget(_wrap(definition: _spiDef, signalMap: signals));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      // Both dialogs have a Cancel button localized to the same word; scope
      // the find to descendants of the preview dialog.
      await tester.tap(
        find.descendant(
          of: find.byType(DecoderAutoBindPreviewDialog),
          matching: find.text(l10n.decoderAutoBindCancelButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DecoderAutoBindPreviewDialog), findsNothing);
      // Underlying dialog still open.
      expect(find.byType(DecoderConfigDialog), findsOneWidget);
    });
  });

  group('Auto-bind preview summary', () {
    testWidgets('summary shows expected counts for SPI', (tester) async {
      // 2 required (sclk, mosi) + 2 optional (miso, cs). All four resolve
      // exactly when leaf names match the binding names.
      final signals = _signals([
        _v('tb.sclk'),
        _v('tb.mosi'),
        _v('tb.miso'),
        _v('tb.cs'),
      ]);
      await tester.pumpWidget(_wrap(definition: _spiDef, signalMap: signals));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      // 4 exact, 0 fuzzy, 0 unmatched of 4 total.
      final expected = l10n.decoderAutoBindSummary(4, 0, 0, 4);
      expect(find.text(expected), findsOneWidget);
    });
  });

  group('Apply all populates _bindings', () {
    testWidgets('clicking Apply all then Add Decoder activates with bindings', (
      tester,
    ) async {
      final signals = _signals([
        _v('tb.sclk'),
        _v('tb.mosi'),
        _v('tb.miso'),
        _v('tb.cs'),
      ]);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productTelemetryConfig,
            signalVariablesMapProvider.overrideWith((ref) => signals),
          ],
          child: Builder(
            builder: (ctx) {
              container = ProviderScope.containerOf(ctx);
              return const MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(body: DecoderConfigDialog(definition: _spiDef)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));

      // Open preview.
      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      // Apply all.
      await tester.tap(find.text(l10n.decoderAutoBindApplyAllButton));
      await tester.pumpAndSettle();
      expect(find.byType(DecoderAutoBindPreviewDialog), findsNothing);

      // Add Decoder.
      await tester.tap(find.text(l10n.decoderConfigAddButton));
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
      // cs is absent → noMatch.
      final signals = _signals([
        _v('tb.sclk'),
        _v('tb.mosi'),
        _v('tb.misoo'),
      ]);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productTelemetryConfig,
            signalVariablesMapProvider.overrideWith((ref) => signals),
          ],
          child: Builder(
            builder: (ctx) {
              container = ProviderScope.containerOf(ctx);
              return const MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(body: DecoderConfigDialog(definition: _spiDef)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));

      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();

      // Apply confirmed only.
      await tester.tap(find.text(l10n.decoderAutoBindApplyConfirmedOnlyButton));
      await tester.pumpAndSettle();

      // Add Decoder. SPI requires sclk + mosi only — miso is optional.
      await tester.tap(find.text(l10n.decoderConfigAddButton));
      await tester.pumpAndSettle();

      final actives = container.read(activeDecodersProvider);
      expect(actives, hasLength(1));
      expect(actives.first.config.signalBindings['sclk'], 'tb.sclk');
      expect(actives.first.config.signalBindings['mosi'], 'tb.mosi');
      // miso resolved fuzzily (1-edit from misoo) — Apply confirmed only
      // must skip it.
      expect(
        actives.first.config.signalBindings.containsKey('miso'),
        isFalse,
      );
    });
  });

  group('Manually pre-bound signals are not overwritten', () {
    testWidgets('pre-existing binding survives Auto-bind preview Apply all', (
      tester,
    ) async {
      // A wider set of signals — both 'tb.sclk' (the obvious match) and
      // 'tb.foo_clk' (unconventional). User has manually bound sclk to
      // foo_clk before pressing Auto-bind.
      final signals = _signals([
        _v('tb.sclk'),
        _v('tb.foo_clk'),
        _v('tb.mosi'),
      ]);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productTelemetryConfig,
            signalVariablesMapProvider.overrideWith((ref) => signals),
          ],
          child: Builder(
            builder: (ctx) {
              container = ProviderScope.containerOf(ctx);
              return const MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(
                  body: DecoderConfigDialog(definition: _spiDef),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));

      // Manually bind sclk → tb.foo_clk via the dropdown.
      // First DropdownButton<String> is the sclk row.
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      // The dropdown menu shows fullPath (which equals signalRef here).
      await tester.tap(find.text('tb.foo_clk').last);
      await tester.pumpAndSettle();

      // Now run Auto-bind.
      await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.decoderAutoBindApplyAllButton));
      await tester.pumpAndSettle();

      // Add Decoder.
      await tester.tap(find.text(l10n.decoderConfigAddButton));
      await tester.pumpAndSettle();

      final actives = container.read(activeDecodersProvider);
      expect(actives, hasLength(1));
      // Manual binding preserved — NOT overwritten by tb.sclk.
      expect(actives.first.config.signalBindings['sclk'], 'tb.foo_clk');
      expect(actives.first.config.signalBindings['mosi'], 'tb.mosi');
    });
  });

  group('Ambiguous-prefix banner', () {
    testWidgets(
      'banner appears with two AXI buses; selecting prefix re-runs algorithm',
      (tester) async {
        // Two AXI4 buses, m_axi_ and s_axi_, in the same scope. Each
        // resolves the same number of bindings → ambiguous.
        final signals = _signals([
          _v('tb.dut.m_axi_aclk'),
          _v('tb.dut.m_axi_aresetn'),
          _v('tb.dut.m_axi_awvalid'),
          _v('tb.dut.m_axi_awready'),
          _v('tb.dut.s_axi_aclk'),
          _v('tb.dut.s_axi_aresetn'),
          _v('tb.dut.s_axi_awvalid'),
          _v('tb.dut.s_axi_awready'),
        ]);
        await tester.pumpWidget(
          _wrap(definition: _axiLite, signalMap: signals),
        );
        await tester.pumpAndSettle();
        final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));

        await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
        await tester.pumpAndSettle();

        // Banner is visible.
        expect(find.text(l10n.decoderAutoBindAmbiguousBanner), findsOneWidget);
        expect(
          find.text(l10n.decoderAutoBindPrefixDropdownLabel),
          findsOneWidget,
        );

        // Both prefixes appear in the dropdown's selected-value position.
        expect(find.text('m_axi_'), findsOneWidget);

        // Open the prefix dropdown (the only one inside the preview dialog).
        final prefixDropdown = find.descendant(
          of: find.byType(DecoderAutoBindPreviewDialog),
          matching: find.byType(DropdownButton<String>),
        );
        expect(prefixDropdown, findsOneWidget);
        await tester.tap(prefixDropdown);
        await tester.pumpAndSettle();
        expect(find.text('s_axi_'), findsWidgets);

        // Select s_axi_.
        await tester.tap(find.text('s_axi_').last);
        await tester.pumpAndSettle();

        // Apply all and confirm s_axi_ signals are picked.
        await tester.tap(find.text(l10n.decoderAutoBindApplyAllButton));
        await tester.pumpAndSettle();

        // After Apply: the parent dialog's per-binding dropdowns show the
        // s_axi_ paths (one DropdownButton<String> per required binding).
        final dropdowns = find.byType(DropdownButton<String>);
        expect(dropdowns, findsNWidgets(_axiLite.requiredSignals.length));
        expect(find.text('tb.dut.s_axi_aclk'), findsOneWidget);
        expect(find.text('tb.dut.s_axi_awvalid'), findsOneWidget);
      },
    );
  });

  group('Locale sweep', () {
    final signals = _signals([_v('tb.sclk'), _v('tb.mosi')]);

    for (final localeCode in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('$localeCode renders without overflow at tablet width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            definition: _spiDef,
            signalMap: signals,
            locale: Locale(localeCode),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
        await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
        await tester.pumpAndSettle();
        expect(find.byType(DecoderAutoBindPreviewDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$localeCode renders without overflow at phone width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(420, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            definition: _spiDef,
            signalMap: signals,
            locale: Locale(localeCode),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
        await tester.tap(find.text(l10n.decoderConfigAutoBindButton));
        await tester.pumpAndSettle();
        expect(find.byType(DecoderAutoBindPreviewDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
