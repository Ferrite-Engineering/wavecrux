// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Broad grouping of Stage widgets used to organise the Add-Widget picker.
///
/// Categories let users filter the picker by intent — primitive elements,
/// advanced peripheral primitives, instrument-style readouts, board
/// emulations, protocol dashboards, or user-supplied compositions. The
/// enum lives in the domain layer so widget definitions can reference it
/// without depending on Flutter.
///
/// The value order is the **fixed display order** in the picker —
/// categories render top-to-bottom in declaration order regardless of
/// locale, so the cognitive grouping ("simple primitives → richer
/// peripherals → instruments → boards → protocols → user-supplied") is
/// preserved across en, zh, ja, and ko.
enum StageWidgetCategory {
  /// Simple, single-purpose visual elements (LED, switch, bus readout).
  primitive,

  /// Advanced peripheral primitive widgets that go beyond the simple
  /// primitives (framebuffer, audio waveform, 3-axis orientation,
  /// character LCD, OLED graphic display, PS/2 keyboard/mouse, RGB LED).
  /// Each is the foundation for a peripheral category that exceeds what
  /// a simple LED or seven-segment can express; they ship in the curated
  /// Pro widget pack.
  peripheral,

  /// Instrument-style readouts (gauges, level bars, signal graphs).
  instrument,

  /// Board emulations that compose primitives onto a backdrop
  /// (Basys 3, DE10-Lite, Nexys A7, …).
  board,

  /// Protocol-aware dashboards (UART terminal, SPI/I²C bus monitor).
  protocol,

  /// User- or vendor-supplied widgets that don't match a built-in category.
  custom,
}
