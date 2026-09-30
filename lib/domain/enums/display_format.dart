// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How a signal's raw bit-vector value should be rendered for the user.
enum DisplayFormat {
  binary,
  hexadecimal,
  octal,
  unsignedDecimal,
  signedDecimal,
  ascii,
  // ── radix translators ─────────────────────────────────────────────────────
  /// IEEE 754 single-precision (32-bit) floating-point.
  ieee754Single,

  /// IEEE 754 double-precision (64-bit) floating-point.
  ieee754Double,

  /// Fixed-point Q-format (TI/Xilinx Qm.n notation). Requires [translatorConfig]
  /// with keys 'm' (int), 'n' (int), and 'signed' (bool).
  fixedPointQ,

  /// Sign-magnitude encoding. MSB is the sign bit; remaining bits are the
  /// magnitude. Distinct −0 renders as "−0".
  signedMagnitude,

  /// Binary-reflected Gray code decoded to unsigned binary.
  grayCode,

  /// User-authored value→label table. Requires [translatorConfig] with a
  /// 'entries' key containing the serialized [NamedEnumConfig].
  namedEnum,
}
