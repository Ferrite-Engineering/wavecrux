// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/l10n/generated/l10n.dart';

/// Widget-layer localization bridge for protocol decoder metadata.
///
/// [DecoderDefinition] is a pure-Dart domain model (no Flutter imports) so it
/// cannot access [L10N] directly.  This helper maps each decoder's id, signal
/// name, and parameter id to the corresponding ARB string at the widget layer.
///
/// Every built-in decoder id is handled by a dedicated switch arm.
/// User-contributed plugin decoders (ids not in any arm) fall back to the raw
/// string stored on the domain model — those strings are authored by the plugin
/// developer and cannot be localized here.
abstract final class DecoderStrings {
  // ── Decoder display name ──────────────────────────────────────────────────

  static String decoderName(L10N l10n, String decoderId, String rawName) =>
      switch (decoderId) {
        'spi' => l10n.spiDecoderName,
        'i2c' => l10n.i2cDecoderName,
        'uart' => l10n.uartDecoderName,
        'axi4_lite' => l10n.axi4LiteDecoderName,
        'apb' => l10n.apbDecoderName,
        'ahb_lite' => l10n.ahbLiteDecoderName,
        'wishbone' => l10n.wishboneDecoderName,
        'riscv' => l10n.riscvDecoderName,
        'spi_flash' => l10n.spiFlashDecoderName,
        _ => rawName,
      };

  // ── Decoder description ───────────────────────────────────────────────────

  static String decoderDescription(
    L10N l10n,
    String decoderId,
    String rawDescription,
  ) => switch (decoderId) {
    'spi' => l10n.spiDecoderDescription,
    'i2c' => l10n.i2cDecoderDescription,
    'uart' => l10n.uartDecoderDescription,
    'axi4_lite' => l10n.axi4LiteDecoderDescription,
    'apb' => l10n.apbDecoderDescription,
    'ahb_lite' => l10n.ahbLiteDecoderDescription,
    'wishbone' => l10n.wishboneDecoderDescription,
    'riscv' => l10n.riscvDecoderDescription,
    'spi_flash' => l10n.spiFlashDecoderDescription,
    _ => rawDescription,
  };

  // ── Signal description ────────────────────────────────────────────────────

  static String signalDescription(
    L10N l10n,
    String decoderId,
    String signalName,
    String rawDescription,
  ) => switch ((decoderId, signalName)) {
    // SPI
    ('spi', 'sclk') => l10n.spiSignalSclk,
    ('spi', 'mosi') => l10n.spiSignalMosi,
    ('spi', 'miso') => l10n.spiSignalMiso,
    ('spi', 'cs') => l10n.spiSignalCs,
    // I2C
    ('i2c', 'sda') => l10n.i2cSignalSda,
    ('i2c', 'scl') => l10n.i2cSignalScl,
    // UART
    ('uart', 'tx') => l10n.uartSignalTx,
    ('uart', 'rx') => l10n.uartSignalRx,
    // AXI4-Lite
    ('axi4_lite', 'aclk') => l10n.axi4LiteSignalAclk,
    ('axi4_lite', 'aresetn') => l10n.axi4LiteSignalAresetn,
    ('axi4_lite', 'awaddr') => l10n.axi4LiteSignalAwaddr,
    ('axi4_lite', 'awvalid') => l10n.axi4LiteSignalAwvalid,
    ('axi4_lite', 'awready') => l10n.axi4LiteSignalAwready,
    ('axi4_lite', 'wdata') => l10n.axi4LiteSignalWdata,
    ('axi4_lite', 'wvalid') => l10n.axi4LiteSignalWvalid,
    ('axi4_lite', 'wready') => l10n.axi4LiteSignalWready,
    ('axi4_lite', 'bresp') => l10n.axi4LiteSignalBresp,
    ('axi4_lite', 'bvalid') => l10n.axi4LiteSignalBvalid,
    ('axi4_lite', 'bready') => l10n.axi4LiteSignalBready,
    ('axi4_lite', 'araddr') => l10n.axi4LiteSignalAraddr,
    ('axi4_lite', 'arvalid') => l10n.axi4LiteSignalArvalid,
    ('axi4_lite', 'arready') => l10n.axi4LiteSignalArready,
    ('axi4_lite', 'rdata') => l10n.axi4LiteSignalRdata,
    ('axi4_lite', 'rresp') => l10n.axi4LiteSignalRresp,
    ('axi4_lite', 'rvalid') => l10n.axi4LiteSignalRvalid,
    ('axi4_lite', 'rready') => l10n.axi4LiteSignalRready,
    ('axi4_lite', 'awprot') => l10n.axi4LiteSignalAwprot,
    ('axi4_lite', 'arprot') => l10n.axi4LiteSignalArprot,
    ('axi4_lite', 'wstrb') => l10n.axi4LiteSignalWstrb,
    // APB
    ('apb', 'pclk') => l10n.apbSignalPclk,
    ('apb', 'presetn') => l10n.apbSignalPresetn,
    ('apb', 'psel') => l10n.apbSignalPsel,
    ('apb', 'penable') => l10n.apbSignalPenable,
    ('apb', 'pwrite') => l10n.apbSignalPwrite,
    ('apb', 'paddr') => l10n.apbSignalPaddr,
    ('apb', 'pwdata') => l10n.apbSignalPwdata,
    ('apb', 'prdata') => l10n.apbSignalPrdata,
    ('apb', 'pready') => l10n.apbSignalPready,
    ('apb', 'pslverr') => l10n.apbSignalPslverr,
    ('apb', 'pprot') => l10n.apbSignalPprot,
    ('apb', 'pstrb') => l10n.apbSignalPstrb,
    // AHB-Lite
    ('ahb_lite', 'hclk') => l10n.ahbLiteSignalHclk,
    ('ahb_lite', 'hresetn') => l10n.ahbLiteSignalHresetn,
    ('ahb_lite', 'haddr') => l10n.ahbLiteSignalHaddr,
    ('ahb_lite', 'htrans') => l10n.ahbLiteSignalHtrans,
    ('ahb_lite', 'hwrite') => l10n.ahbLiteSignalHwrite,
    ('ahb_lite', 'hsize') => l10n.ahbLiteSignalHsize,
    ('ahb_lite', 'hburst') => l10n.ahbLiteSignalHburst,
    ('ahb_lite', 'hwdata') => l10n.ahbLiteSignalHwdata,
    ('ahb_lite', 'hrdata') => l10n.ahbLiteSignalHrdata,
    ('ahb_lite', 'hready') => l10n.ahbLiteSignalHready,
    ('ahb_lite', 'hresp') => l10n.ahbLiteSignalHresp,
    ('ahb_lite', 'hprot') => l10n.ahbLiteSignalHprot,
    ('ahb_lite', 'hmastlock') => l10n.ahbLiteSignalHmastlock,
    // Wishbone
    ('wishbone', 'clk') => l10n.wishboneSignalClk,
    ('wishbone', 'rst') => l10n.wishboneSignalRst,
    ('wishbone', 'cyc') => l10n.wishboneSignalCyc,
    ('wishbone', 'stb') => l10n.wishboneSignalStb,
    ('wishbone', 'we') => l10n.wishboneSignalWe,
    ('wishbone', 'adr') => l10n.wishboneSignalAdr,
    ('wishbone', 'dat_o') => l10n.wishboneSignalDatO,
    ('wishbone', 'dat_i') => l10n.wishboneSignalDatI,
    ('wishbone', 'ack') => l10n.wishboneSignalAck,
    ('wishbone', 'sel') => l10n.wishboneSignalSel,
    ('wishbone', 'err') => l10n.wishboneSignalErr,
    ('wishbone', 'rty') => l10n.wishboneSignalRty,
    ('wishbone', 'lock') => l10n.wishboneSignalLock,
    ('wishbone', 'cti') => l10n.wishboneSignalCti,
    ('wishbone', 'bte') => l10n.wishboneSignalBte,
    ('wishbone', 'stall') => l10n.wishboneSignalStall,
    ('wishbone', 'tga') => l10n.wishboneSignalTga,
    ('wishbone', 'tgd_o') => l10n.wishboneSignalTgdO,
    ('wishbone', 'tgd_i') => l10n.wishboneSignalTgdI,
    ('wishbone', 'tgc') => l10n.wishboneSignalTgc,
    // RISC-V
    ('riscv', 'clk') => l10n.riscvSignalClk,
    ('riscv', 'instruction') => l10n.riscvSignalInstruction,
    ('riscv', 'valid') => l10n.riscvSignalValid,
    ('riscv', 'pc') => l10n.riscvSignalPc,
    // Plugin / unrecognised
    _ => rawDescription,
  };

  // ── Parameter display name ────────────────────────────────────────────────

  static String paramName(
    L10N l10n,
    String decoderId,
    String paramId,
    String rawName,
  ) => switch ((decoderId, paramId)) {
    // SPI
    ('spi', 'cpol') => l10n.spiParamCpol,
    ('spi', 'cpha') => l10n.spiParamCpha,
    ('spi', 'bit_order') => l10n.spiParamBitOrder,
    ('spi', 'word_size') => l10n.spiParamWordSize,
    ('spi', 'cs_active_level') => l10n.spiParamCsActiveLevel,
    // I2C
    ('i2c', 'address_bits') => l10n.i2cParamAddressBits,
    // UART
    ('uart', 'baud_rate') => l10n.uartParamBaudRate,
    ('uart', 'data_bits') => l10n.uartParamDataBits,
    ('uart', 'parity') => l10n.uartParamParity,
    ('uart', 'stop_bits') => l10n.uartParamStopBits,
    ('uart', 'bit_order') => l10n.uartParamBitOrder,
    ('uart', 'group_gap_bits') => l10n.uartParamGroupGapBits,
    // AXI4-Lite
    ('axi4_lite', 'addr_width') => l10n.axi4LiteParamAddrWidth,
    ('axi4_lite', 'data_width') => l10n.axi4LiteParamDataWidth,
    // APB
    ('apb', 'addr_width') => l10n.apbParamAddrWidth,
    ('apb', 'data_width') => l10n.apbParamDataWidth,
    // AHB-Lite
    ('ahb_lite', 'addr_width') => l10n.ahbLiteParamAddrWidth,
    ('ahb_lite', 'data_width') => l10n.ahbLiteParamDataWidth,
    ('ahb_lite', 'check_alignment') => l10n.ahbLiteParamCheckAlignment,
    ('ahb_lite', 'wait_state_threshold') => l10n.ahbLiteParamWaitStateThreshold,
    // Wishbone
    ('wishbone', 'revision') => l10n.wishboneParamRevision,
    ('wishbone', 'addr_width') => l10n.wishboneParamAddrWidth,
    ('wishbone', 'data_width') => l10n.wishboneParamDataWidth,
    ('wishbone', 'granularity') => l10n.wishboneParamGranularity,
    ('wishbone', 'endianness') => l10n.wishboneParamEndianness,
    ('wishbone', 'check_alignment') => l10n.wishboneParamCheckAlignment,
    // RISC-V
    ('riscv', 'xlen') => l10n.riscvParamXlen,
    ('riscv', 'ext_m') => l10n.riscvParamExtM,
    ('riscv', 'ext_a') => l10n.riscvParamExtA,
    ('riscv', 'ext_f') => l10n.riscvParamExtF,
    ('riscv', 'ext_d') => l10n.riscvParamExtD,
    ('riscv', 'ext_c') => l10n.riscvParamExtC,
    // SPI Flash (stacked)
    ('spi_flash', 'vendor_preset') => l10n.spiFlashParamVendorPreset,
    ('spi_flash', 'address_width') => l10n.spiFlashParamAddressWidth,
    ('spi_flash', 'dummy_cycles') => l10n.spiFlashParamDummyCycles,
    // Plugin / unrecognised
    _ => rawName,
  };

  // ── Parameter description ─────────────────────────────────────────────────

  static String paramDescription(
    L10N l10n,
    String decoderId,
    String paramId,
    String rawDescription,
  ) => switch ((decoderId, paramId)) {
    // SPI
    ('spi', 'cpol') => l10n.spiParamCpolDescription,
    ('spi', 'cpha') => l10n.spiParamCphaDescription,
    ('spi', 'bit_order') => l10n.spiParamBitOrderDescription,
    ('spi', 'word_size') => l10n.spiParamWordSizeDescription,
    ('spi', 'cs_active_level') => l10n.spiParamCsActiveLevelDescription,
    // I2C
    ('i2c', 'address_bits') => l10n.i2cParamAddressBitsDescription,
    // UART
    ('uart', 'baud_rate') => l10n.uartParamBaudRateDescription,
    ('uart', 'data_bits') => l10n.uartParamDataBitsDescription,
    ('uart', 'parity') => l10n.uartParamParityDescription,
    ('uart', 'stop_bits') => l10n.uartParamStopBitsDescription,
    ('uart', 'bit_order') => l10n.uartParamBitOrderDescription,
    ('uart', 'group_gap_bits') => l10n.uartParamGroupGapBitsDescription,
    // AXI4-Lite
    ('axi4_lite', 'addr_width') => l10n.axi4LiteParamAddrWidthDescription,
    ('axi4_lite', 'data_width') => l10n.axi4LiteParamDataWidthDescription,
    // APB
    ('apb', 'addr_width') => l10n.apbParamAddrWidthDescription,
    ('apb', 'data_width') => l10n.apbParamDataWidthDescription,
    // AHB-Lite
    ('ahb_lite', 'addr_width') => l10n.ahbLiteParamAddrWidthDescription,
    ('ahb_lite', 'data_width') => l10n.ahbLiteParamDataWidthDescription,
    ('ahb_lite', 'check_alignment') =>
      l10n.ahbLiteParamCheckAlignmentDescription,
    ('ahb_lite', 'wait_state_threshold') =>
      l10n.ahbLiteParamWaitStateThresholdDescription,
    // Wishbone
    ('wishbone', 'revision') => l10n.wishboneParamRevisionDescription,
    ('wishbone', 'addr_width') => l10n.wishboneParamAddrWidthDescription,
    ('wishbone', 'data_width') => l10n.wishboneParamDataWidthDescription,
    ('wishbone', 'granularity') => l10n.wishboneParamGranularityDescription,
    ('wishbone', 'endianness') => l10n.wishboneParamEndiannessDescription,
    ('wishbone', 'check_alignment') =>
      l10n.wishboneParamCheckAlignmentDescription,
    // RISC-V
    ('riscv', 'xlen') => l10n.riscvParamXlenDescription,
    ('riscv', 'ext_m') => l10n.riscvParamExtMDescription,
    ('riscv', 'ext_a') => l10n.riscvParamExtADescription,
    ('riscv', 'ext_f') => l10n.riscvParamExtFDescription,
    ('riscv', 'ext_d') => l10n.riscvParamExtDDescription,
    ('riscv', 'ext_c') => l10n.riscvParamExtCDescription,
    // SPI Flash (stacked)
    ('spi_flash', 'vendor_preset') => l10n.spiFlashParamVendorPresetDescription,
    ('spi_flash', 'address_width') => l10n.spiFlashParamAddressWidthDescription,
    ('spi_flash', 'dummy_cycles') => l10n.spiFlashParamDummyCyclesDescription,
    // Plugin / unrecognised
    _ => rawDescription,
  };
}
