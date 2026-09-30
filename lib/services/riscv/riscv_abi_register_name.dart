// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// ABI mnemonics for the RISC-V integer register file.
///
/// Open core owns this table because the RVFI Commit Inspector is an
/// open-core widget and must name `x10` `a0` without a license — while the
/// Pro Register File widget's `RegisterNamingService` is Pro-only *and*
/// takes a Pro `RegisterFileConfig`, so it cannot be reached from here. The
/// two are kept in agreement by the Pro service delegating its
/// `riscvAbi` scheme to [riscvAbiRegisterName] rather than by two copies of
/// the same list — ABI register naming crosses the tier boundary.
///
/// Pure Dart — no Flutter imports.
library;

/// The standard RISC-V ABI mnemonics for `x0`–`x31`, in index order.
///
/// Source: RISC-V ELF psABI specification, integer register convention.
/// This is the same list the Pro Register File widget renders, and the two
/// are required to stay identical — a register that reads `a0` in one widget
/// and `x10` in another is a bug report waiting to happen.
const List<String> kRiscvAbiRegisterNames = <String>[
  'zero',
  'ra',
  'sp',
  'gp',
  'tp',
  't0',
  't1',
  't2',
  's0',
  's1',
  'a0',
  'a1',
  'a2',
  'a3',
  'a4',
  'a5',
  'a6',
  'a7',
  's2',
  's3',
  's4',
  's5',
  's6',
  's7',
  's8',
  's9',
  's10',
  's11',
  't3',
  't4',
  't5',
  't6',
];

/// The ABI mnemonic for integer register [index] (`10` → `a0`).
///
/// Total: an index outside the ABI's `x0`–`x31` range — a negative index, or
/// a wider register file than the base ISA defines — falls back to the
/// generic `R<index>` spelling rather than returning an empty label. That
/// fallback shape is deliberate: it matches what the Pro Register File
/// widget already renders for out-of-range indices, so the delegation is a
/// behaviour-preserving refactor on the Pro side.
String riscvAbiRegisterName(int index) {
  if (index < 0 || index >= kRiscvAbiRegisterNames.length) return 'R$index';
  return kRiscvAbiRegisterNames[index];
}

/// The numeric spelling of integer register [index] (`10` → `x10`).
///
/// The RISC-V-native numeric form, as distinct from the architecture-neutral
/// `R<index>` the Pro Register File widget uses for its `numeric` scheme —
/// a RISC-V trace reads `x10`, never `R10`.
String riscvNumericRegisterName(int index) => index < 0 ? 'R$index' : 'x$index';

/// `a0 (x10)` — the ABI mnemonic with its numeric index, for surfaces with
/// room to show both. Used in diagnostics, where naming the register both
/// ways removes any doubt about which one a message means.
String riscvRegisterNameWithIndex(int index) {
  if (index < 0) return 'R$index';
  return '${riscvAbiRegisterName(index)} (${riscvNumericRegisterName(index)})';
}
