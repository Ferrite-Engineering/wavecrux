// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Broad grouping of protocol decoders used to organise the Add-Decoder
/// picker.
///
/// Categories are declared by each [DecoderDefinition] so the picker UI can
/// render decoders in collapsible groups instead of a single flat list. The
/// enum lives in the domain layer so decoder definitions can reference it
/// without depending on Flutter.
///
/// The value order is the **fixed display order** in the picker — categories
/// render top-to-bottom in declaration order regardless of locale, so the
/// cognitive grouping ("low-speed serial → AMBA → high-speed serial → test
/// & management → Ethernet → user plugins → custom") is preserved across en,
/// zh, ja, and ko.
enum DecoderCategory {
  /// Low-pin-count chip-to-chip serial buses (SPI, I²C, UART).
  serial,

  /// Automotive and industrial-fieldbus protocols (CAN, CAN-FD, future
  /// CANopen, J1939, ISO 15765). Positioned after [serial] and before [amba]
  /// in the picker.
  automotive,

  /// ARM AMBA family (AXI4-Lite, APB, AXI4 full).
  amba,

  /// High-speed packetised serial (USB 2.0, PCIe TLP).
  highSpeed,

  /// Test, debug, and management interfaces (JTAG, MDIO).
  testManagement,

  /// Ethernet front-ends and frame-layer decoders (AXIS, MII, RMII, GMII,
  /// future RGMII).
  ethernet,

  /// Instruction-stream decoders (RISC-V, future MIPS / ARM / LoongArch).
  /// Distinct from bus decoders: consumes a single instruction-word signal
  /// (optionally paired with a PC signal) and emits one decoded transaction
  /// per fetched instruction.
  instructionTrace,

  /// Dynamically loaded user-contributed decoder plugins.
  userPlugin,

  /// Decoders that don't match a built-in category. Default for community
  /// decoders that haven't classified themselves.
  custom,
}
