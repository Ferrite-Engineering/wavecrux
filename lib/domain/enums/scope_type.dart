// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The structural type of a scope in the signal hierarchy.
///
/// Maps 1-to-1 with the `WELLEN_SCOPE_*` constants in the native library so
/// that the service layer can convert without a lookup table.
enum ScopeType {
  // ── Verilog / SystemVerilog ────────────────────────────────────────────────
  module,
  task,
  function,
  begin,
  fork,
  generate,
  struct,
  union,
  svClass,
  svInterface,
  svPackage,
  svProgram,

  // ── VHDL ──────────────────────────────────────────────────────────────────
  vhdlArchitecture,
  vhdlProcedure,
  vhdlFunction,
  vhdlRecord,
  vhdlProcess,
  vhdlBlock,
  vhdlForGenerate,
  vhdlIfGenerate,
  vhdlGenerate,
  vhdlPackage,

  // ── GHW (GHDL) ────────────────────────────────────────────────────────────
  ghwGeneric,
  vhdlArray,
}
