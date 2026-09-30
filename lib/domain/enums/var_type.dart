// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The type of a variable (signal) as declared in the source file.
///
/// VCD, SystemVerilog, and VHDL types are represented in a single flat enum.
/// The `sv` prefix denotes SystemVerilog-specific types that clash with
/// common Dart type names (e.g. [svInt] for SV `int`).
enum VarType {
  // ── VCD / Verilog ──────────────────────────────────────────────────────────
  event,
  integer,
  parameter,
  real,
  reg,
  supply0,
  supply1,
  time,
  tri,
  triAnd,
  triOr,
  triReg,
  tri0,
  tri1,
  wAnd,
  wire,
  wOr,
  string,
  port,
  sparseArray,
  realTime,

  realParameter,

  /// A parameter declared with `event` type. Emitted by wellen 0.24+ for the
  /// rare case of an event-typed parameter; rendered like an [event].
  eventParameter,

  // ── SystemVerilog ──────────────────────────────────────────────────────────
  bit,
  logic,

  /// SystemVerilog `int` (32-bit signed). Named `svInt` to avoid shadowing
  /// Dart's built-in `int` type name at the use-site.
  svInt,
  svShortInt,
  svLongInt,
  svByte,
  svEnum,
  svShortReal,

  // ── VHDL (types emitted by GHDL) ──────────────────────────────────────────
  boolean,
  bitVector,
  stdLogic,
  stdLogicVector,
  stdULogic,
  stdULogicVector,
}
