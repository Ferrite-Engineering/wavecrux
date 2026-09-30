// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';

/// Outcome of attempting to coerce a [RawSignalSample] into a numeric
/// [BigInt] interpretation of its bit-string.
///
/// Internal to the normalization framework — not part of the public SDK.
class BitStringDecodeResult {
  const BitStringDecodeResult.value(this.value)
    : isAllUnknown = false,
      isMixedUnknown = false,
      isX = false;

  const BitStringDecodeResult.allUnknown({required this.isX})
    : value = null,
      isAllUnknown = true,
      isMixedUnknown = false;

  /// All-X / all-Z bits get the [isAllUnknown] flag; the renderer picks the
  /// X-vs-Z branch from [isX] (true ⇒ X-dominant, false ⇒ Z-only).
  ///
  /// Mixed values (some valid bits, some X / Z) decode their valid bits
  /// with X/Z replaced by `0` and surface [isMixedUnknown] so caller can
  /// honour [XZPolicy.bestEffort] vs. [XZPolicy.propagate].
  const BitStringDecodeResult.mixed(this.value)
    : isAllUnknown = false,
      isMixedUnknown = true,
      isX = true;

  final BigInt? value;
  final bool isAllUnknown;
  final bool isMixedUnknown;
  final bool isX;
}

/// Strips a leading VCD `b` prefix and converts the bit-string into a
/// [BigInt]. Returns an `allUnknown` result if every bit is X or Z,
/// distinguishing X-dominant from Z-only based on the open-core
/// "X dominates Z" precedence.
BitStringDecodeResult decodeBitString(RawSignalSample sample) {
  final raw = sample.rawValue.toLowerCase();
  if (raw.isEmpty) {
    return const BitStringDecodeResult.allUnknown(isX: true);
  }
  final stripped = raw.startsWith('b') ? raw.substring(1) : raw;
  if (stripped.isEmpty) {
    return const BitStringDecodeResult.allUnknown(isX: true);
  }

  var hasX = false;
  var hasZ = false;
  var hasReal = false;
  for (final ch in stripped.codeUnits) {
    switch (ch) {
      case 0x30: // '0'
      case 0x31: // '1'
        hasReal = true;
      case 0x78: // 'x'
        hasX = true;
      case 0x7a: // 'z'
        hasZ = true;
      default:
        // Unrecognised character — treat as unknown.
        hasX = true;
    }
  }

  if (!hasReal) {
    return BitStringDecodeResult.allUnknown(isX: hasX || !hasZ);
  }

  // Build BigInt by replacing x/z with 0 (per VCD convention used by
  // GTKWave and Surfer when forced to coerce a partial-unknown value).
  final coerced = stripped.replaceAll(RegExp('[xz]'), '0');
  final value = BigInt.parse(coerced, radix: 2);

  if (hasX || hasZ) {
    return BitStringDecodeResult.mixed(value);
  }
  return BitStringDecodeResult.value(value);
}
