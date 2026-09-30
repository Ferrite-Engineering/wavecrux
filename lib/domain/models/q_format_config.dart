// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Configuration for the [DisplayFormat.fixedPointQ] translator.
///
/// Uses TI/Xilinx Qm.n notation:
/// - Signed Qm.n: 1 sign bit + m integer bits + n fractional bits = m+n+1 total bits
/// - Unsigned Qm.n: m integer bits + n fractional bits = m+n total bits
///
/// The value is interpreted as: integer_part = raw >> n, frac = raw & ((1<<n)−1)
@immutable
class QFormatConfig {
  const QFormatConfig({
    this.m = 7,
    this.n = 8,
    this.signed = true,
  });

  factory QFormatConfig.fromMap(Map<String, Object?> map) => QFormatConfig(
    m: (map['m'] as num?)?.toInt() ?? 7,
    n: (map['n'] as num?)?.toInt() ?? 8,
    signed: (map['signed'] as bool?) ?? true,
  );

  /// Integer bits (not counting the sign bit for signed formats).
  final int m;

  /// Fractional bits.
  final int n;

  /// Whether the format uses two's-complement sign interpretation.
  final bool signed;

  /// Total declared bit width (signal must have exactly this many bits).
  int get totalBits => signed ? m + n + 1 : m + n;

  /// Human-readable notation, e.g. "Q7.8" or "UQ4.12".
  String get notation => signed ? 'Q$m.$n' : 'UQ$m.$n';

  Map<String, Object?> toMap() => {'m': m, 'n': n, 'signed': signed};

  QFormatConfig copyWith({int? m, int? n, bool? signed}) => QFormatConfig(
    m: m ?? this.m,
    n: n ?? this.n,
    signed: signed ?? this.signed,
  );

  @override
  bool operator ==(Object other) =>
      other is QFormatConfig &&
      other.m == m &&
      other.n == n &&
      other.signed == signed;

  @override
  int get hashCode => Object.hash(m, n, signed);

  @override
  String toString() => 'QFormatConfig($notation)';
}
