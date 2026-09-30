// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/decoders/l10n/decoder_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// Pumps a minimal L10N-enabled widget tree and returns the English [L10N].
Future<L10N> _l10n(WidgetTester tester) async {
  late L10N captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (ctx) {
          captured = L10N.of(ctx);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── decoderName ─────────────────────────────────────────────────────────────

  group('DecoderStrings.decoderName', () {
    testWidgets('returns localized name for all built-in decoders', (
      tester,
    ) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.decoderName(l10n, 'spi', 'SPI'),
        l10n.spiDecoderName,
      );
      expect(
        DecoderStrings.decoderName(l10n, 'i2c', 'I²C'),
        l10n.i2cDecoderName,
      );
      expect(
        DecoderStrings.decoderName(l10n, 'uart', 'UART'),
        l10n.uartDecoderName,
      );
      expect(
        DecoderStrings.decoderName(l10n, 'axi4_lite', 'AXI4-Lite'),
        l10n.axi4LiteDecoderName,
      );
      expect(
        DecoderStrings.decoderName(l10n, 'apb', 'APB'),
        l10n.apbDecoderName,
      );
      expect(
        DecoderStrings.decoderName(l10n, 'ahb_lite', 'AHB-Lite'),
        l10n.ahbLiteDecoderName,
      );
      expect(
        DecoderStrings.decoderName(l10n, 'wishbone', 'Wishbone'),
        l10n.wishboneDecoderName,
      );
      expect(
        DecoderStrings.decoderName(l10n, 'riscv', 'RISC-V Instruction Trace'),
        l10n.riscvDecoderName,
      );
    });

    testWidgets('falls back to rawName for unknown decoder id', (tester) async {
      final l10n = await _l10n(tester);
      expect(
        DecoderStrings.decoderName(l10n, 'my_plugin', 'My Plugin'),
        'My Plugin',
      );
    });
  });

  // ── decoderDescription ───────────────────────────────────────────────────────

  group('DecoderStrings.decoderDescription', () {
    testWidgets('returns localized description for all built-in decoders', (
      tester,
    ) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.decoderDescription(l10n, 'spi', ''),
        l10n.spiDecoderDescription,
      );
      expect(
        DecoderStrings.decoderDescription(l10n, 'i2c', ''),
        l10n.i2cDecoderDescription,
      );
      expect(
        DecoderStrings.decoderDescription(l10n, 'uart', ''),
        l10n.uartDecoderDescription,
      );
      expect(
        DecoderStrings.decoderDescription(l10n, 'axi4_lite', ''),
        l10n.axi4LiteDecoderDescription,
      );
      expect(
        DecoderStrings.decoderDescription(l10n, 'apb', ''),
        l10n.apbDecoderDescription,
      );
      expect(
        DecoderStrings.decoderDescription(l10n, 'ahb_lite', ''),
        l10n.ahbLiteDecoderDescription,
      );
      expect(
        DecoderStrings.decoderDescription(l10n, 'wishbone', ''),
        l10n.wishboneDecoderDescription,
      );
      expect(
        DecoderStrings.decoderDescription(l10n, 'riscv', ''),
        l10n.riscvDecoderDescription,
      );
    });

    testWidgets('falls back to rawDescription for unknown decoder id', (
      tester,
    ) async {
      final l10n = await _l10n(tester);
      expect(
        DecoderStrings.decoderDescription(l10n, 'my_plugin', 'raw desc'),
        'raw desc',
      );
    });
  });

  // ── signalDescription ────────────────────────────────────────────────────────

  group('DecoderStrings.signalDescription', () {
    testWidgets('SPI signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'spi', 'sclk', ''),
        l10n.spiSignalSclk,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'spi', 'mosi', ''),
        l10n.spiSignalMosi,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'spi', 'miso', ''),
        l10n.spiSignalMiso,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'spi', 'cs', ''),
        l10n.spiSignalCs,
      );
    });

    testWidgets('I2C signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'i2c', 'sda', ''),
        l10n.i2cSignalSda,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'i2c', 'scl', ''),
        l10n.i2cSignalScl,
      );
    });

    testWidgets('UART signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'uart', 'tx', ''),
        l10n.uartSignalTx,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'uart', 'rx', ''),
        l10n.uartSignalRx,
      );
    });

    testWidgets('AXI4-Lite signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'axi4_lite', 'aclk', ''),
        l10n.axi4LiteSignalAclk,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'axi4_lite', 'aresetn', ''),
        l10n.axi4LiteSignalAresetn,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'axi4_lite', 'wstrb', ''),
        l10n.axi4LiteSignalWstrb,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'axi4_lite', 'awprot', ''),
        l10n.axi4LiteSignalAwprot,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'axi4_lite', 'arprot', ''),
        l10n.axi4LiteSignalArprot,
      );
    });

    testWidgets('APB signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'apb', 'pclk', ''),
        l10n.apbSignalPclk,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'apb', 'pslverr', ''),
        l10n.apbSignalPslverr,
      );
    });

    testWidgets('AHB-Lite signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'ahb_lite', 'hclk', ''),
        l10n.ahbLiteSignalHclk,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'ahb_lite', 'hmastlock', ''),
        l10n.ahbLiteSignalHmastlock,
      );
    });

    testWidgets('Wishbone signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'wishbone', 'clk', ''),
        l10n.wishboneSignalClk,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'wishbone', 'stall', ''),
        l10n.wishboneSignalStall,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'wishbone', 'tgd_o', ''),
        l10n.wishboneSignalTgdO,
      );
    });

    testWidgets('RISC-V signals resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.signalDescription(l10n, 'riscv', 'clk', ''),
        l10n.riscvSignalClk,
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'riscv', 'pc', ''),
        l10n.riscvSignalPc,
      );
    });

    testWidgets('falls back to rawDescription for unknown decoder/signal', (
      tester,
    ) async {
      final l10n = await _l10n(tester);
      expect(
        DecoderStrings.signalDescription(l10n, 'my_plugin', 'data', 'raw'),
        'raw',
      );
      expect(
        DecoderStrings.signalDescription(l10n, 'spi', 'unknown_pin', 'raw'),
        'raw',
      );
    });
  });

  // ── paramName ────────────────────────────────────────────────────────────────

  group('DecoderStrings.paramName', () {
    testWidgets('SPI params resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.paramName(l10n, 'spi', 'cpol', ''),
        l10n.spiParamCpol,
      );
      expect(
        DecoderStrings.paramName(l10n, 'spi', 'word_size', ''),
        l10n.spiParamWordSize,
      );
    });

    testWidgets('RISC-V params resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.paramName(l10n, 'riscv', 'xlen', ''),
        l10n.riscvParamXlen,
      );
      expect(
        DecoderStrings.paramName(l10n, 'riscv', 'ext_c', ''),
        l10n.riscvParamExtC,
      );
    });

    testWidgets('AHB-Lite params resolve to ARB strings', (tester) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.paramName(l10n, 'ahb_lite', 'check_alignment', ''),
        l10n.ahbLiteParamCheckAlignment,
      );
      expect(
        DecoderStrings.paramName(l10n, 'ahb_lite', 'wait_state_threshold', ''),
        l10n.ahbLiteParamWaitStateThreshold,
      );
    });

    testWidgets('falls back to rawName for unknown decoder/param', (
      tester,
    ) async {
      final l10n = await _l10n(tester);
      expect(
        DecoderStrings.paramName(l10n, 'my_plugin', 'speed', 'Speed'),
        'Speed',
      );
    });
  });

  // ── paramDescription ─────────────────────────────────────────────────────────

  group('DecoderStrings.paramDescription', () {
    testWidgets('SPI param descriptions resolve to ARB strings', (
      tester,
    ) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.paramDescription(l10n, 'spi', 'cpol', ''),
        l10n.spiParamCpolDescription,
      );
      expect(
        DecoderStrings.paramDescription(l10n, 'spi', 'cs_active_level', ''),
        l10n.spiParamCsActiveLevelDescription,
      );
    });

    testWidgets('Wishbone param descriptions resolve to ARB strings', (
      tester,
    ) async {
      final l10n = await _l10n(tester);

      expect(
        DecoderStrings.paramDescription(l10n, 'wishbone', 'revision', ''),
        l10n.wishboneParamRevisionDescription,
      );
      expect(
        DecoderStrings.paramDescription(
          l10n,
          'wishbone',
          'check_alignment',
          '',
        ),
        l10n.wishboneParamCheckAlignmentDescription,
      );
    });

    testWidgets('falls back to rawDescription for unknown decoder/param', (
      tester,
    ) async {
      final l10n = await _l10n(tester);
      expect(
        DecoderStrings.paramDescription(l10n, 'my_plugin', 'speed', 'raw desc'),
        'raw desc',
      );
    });
  });

  // ── locale sweep ─────────────────────────────────────────────────────────────

  group('locale sweep — no exceptions', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('zh'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders with locale $locale', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (ctx) {
                final l = L10N.of(ctx);
                DecoderStrings.decoderName(l, 'spi', 'SPI');
                DecoderStrings.decoderDescription(l, 'i2c', '');
                DecoderStrings.signalDescription(l, 'uart', 'tx', '');
                DecoderStrings.paramName(l, 'axi4_lite', 'addr_width', '');
                DecoderStrings.paramDescription(l, 'riscv', 'xlen', '');
                DecoderStrings.decoderName(l, 'my_plugin', 'Plugin');
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
