// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// 4-state bit-string decoding for the RISC-V trace substrate.
///
/// `WaveformDataSource` answers value queries with bit-strings (`"0"`,
/// `"b1010xz"`, `"3.14"`), never integers, and returns null both for "the
/// signal has no value at or before this tick" and for "the signal is not
/// loaded" — the two are indistinguishable at this layer, which is exactly
/// why every bound pin must be watched through `stageBoundSignalProvider`
/// for its lazy-load side effect before the substrate walks the source.
///
/// The decode shape here matches the one the Pro register-file snapshot
/// service uses, so the two agree on what an `x` means.
///
/// Pure Dart — no Flutter imports.
library;

/// Three-valued view of a single-bit signal.
enum RiscvBit {
  /// Driven 0.
  low,

  /// Driven 1.
  high,

  /// Unknown: `x`, `z`, unloaded, or before the first transition.
  unknown,
}

/// Decodes a bit-string as a single-bit level.
///
/// A multi-bit value decodes on its least-significant bit, so a 1-bit signal
/// dumped as a width-1 vector (`"b1"`) behaves the same as a scalar (`"1"`).
RiscvBit riscvBitState(String? raw) {
  if (raw == null || raw.isEmpty) return RiscvBit.unknown;
  var s = raw.toLowerCase();
  if (s.startsWith('b')) s = s.substring(1);
  if (s.isEmpty) return RiscvBit.unknown;
  if (s.length > 1) {
    if (s.contains('x') || s.contains('z')) return RiscvBit.unknown;
    final last = s[s.length - 1];
    if (last == '0') return RiscvBit.low;
    if (last == '1') return RiscvBit.high;
    return RiscvBit.unknown;
  }
  if (s == '0') return RiscvBit.low;
  if (s == '1') return RiscvBit.high;
  return RiscvBit.unknown;
}

/// An unsigned integer decoded from a bit-string, plus whether any bit of
/// the source was unknown.
class RiscvDecodedUint {
  const RiscvDecodedUint(this.value, {required this.hasUnknown});

  /// Null when the value could not be decoded.
  final int? value;

  /// True when the source carried `x` / `z`, was unloaded, or was a real
  /// number rather than a bit vector.
  final bool hasUnknown;
}

/// Decodes a bit-string as an unsigned integer.
///
/// Values wider than 62 bits are masked into Dart's safe integer range
/// rather than throwing — a 64-bit `rvfi_order` counter is a real thing and
/// truncating its top bits is preferable to losing the whole retirement.
RiscvDecodedUint riscvDecodeUint(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const RiscvDecodedUint(null, hasUnknown: true);
  }
  var s = raw.toLowerCase();
  if (s.startsWith('b')) s = s.substring(1);
  if (s.isEmpty) return const RiscvDecodedUint(null, hasUnknown: true);
  if (s.contains('.') || s.contains('e')) {
    return const RiscvDecodedUint(null, hasUnknown: true);
  }
  if (s.contains('x') || s.contains('z')) {
    return const RiscvDecodedUint(null, hasUnknown: true);
  }
  try {
    final big = BigInt.parse(s, radix: 2);
    if (big.bitLength > 62) {
      final mask = (BigInt.one << 62) - BigInt.one;
      return RiscvDecodedUint((big & mask).toInt(), hasUnknown: false);
    }
    return RiscvDecodedUint(big.toInt(), hasUnknown: false);
  } on FormatException {
    return const RiscvDecodedUint(null, hasUnknown: true);
  }
}
