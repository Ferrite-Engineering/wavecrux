// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/_bit_string_decoder.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Extracts a contiguous bit-range from a vector sample, optionally
/// re-applying a [sub] normalizer to the extracted slice.
///
/// Bits are indexed in VCD / SystemVerilog convention: bit `0` is the
/// least-significant bit, bit `width - 1` is the most-significant bit.
/// `[highBit:lowBit]` follows: `highBit >= lowBit`, both inclusive.
///
/// The sliced output is itself a synthetic [RawSignalSample] containing
/// the bit-string for the selected range and a [bitWidth] of
/// `highBit - lowBit + 1`. If [sub] is null the slice is returned as a
/// numeric [NormalizedDouble] (its unsigned integer value), which is the
/// common pattern when the caller intends to feed the field straight into
/// a gauge.
///
/// Cannot consume analog samples — bit fields and analog reals are
/// incompatible. Throws [StateError] if invoked on an analog sample.
@immutable
class BitFieldNormalizer extends ValueNormalizer {
  const BitFieldNormalizer({
    required this.highBit,
    required this.lowBit,
    this.sub,
  }) : assert(lowBit >= 0, 'lowBit must be >= 0'),
       assert(highBit >= lowBit, 'highBit must be >= lowBit');

  /// Inclusive most-significant bit index of the field.
  final int highBit;

  /// Inclusive least-significant bit index of the field.
  final int lowBit;

  /// Optional second-stage normalizer applied to the synthetic
  /// [RawSignalSample] containing only the extracted slice. When null the
  /// slice is emitted as a [NormalizedDouble] of its unsigned integer
  /// value.
  final ValueNormalizer? sub;

  /// Number of bits in the extracted field.
  int get fieldWidth => highBit - lowBit + 1;

  @override
  String get kind => 'bit_field';

  @override
  NormalizedValue normalize(RawSignalSample sample) {
    if (sample.isAnalog) {
      throw StateError(
        'BitFieldNormalizer cannot consume analog samples; bind to a '
        'scalar / vector signal instead.',
      );
    }

    if (sample.bitWidth > 0 && highBit >= sample.bitWidth) {
      // Out-of-range bit selection: treat as unknown rather than throw.
      // Manifest validation already rejects bit ranges that overflow the
      // declared signal width; reaching here at runtime means the bound
      // signal is narrower than expected.
      return const NormalizedXZ(isX: true);
    }

    final stripped = sample.rawValue.toLowerCase().startsWith('b')
        ? sample.rawValue.substring(1)
        : sample.rawValue;
    if (stripped.isEmpty) {
      return const NormalizedXZ(isX: true);
    }

    // Pad on the left so highBit indexing is well-defined for short
    // bit-strings (VCD omits leading zeros).
    final declaredWidth = sample.bitWidth > 0
        ? sample.bitWidth
        : stripped.length;
    final padded = stripped.length < declaredWidth
        ? stripped.padLeft(declaredWidth, '0')
        : stripped;

    // Translate VCD ordering (rightmost char = bit 0) into a slice.
    final length = padded.length;
    final highIndex = length - 1 - highBit;
    final lowIndex = length - 1 - lowBit;
    if (highIndex < 0 || lowIndex >= length) {
      return const NormalizedXZ(isX: true);
    }
    final slice = padded.substring(highIndex, lowIndex + 1);

    final sliceSample = RawSignalSample(
      rawValue: slice,
      bitWidth: fieldWidth,
      timeTicks: sample.timeTicks,
    );

    if (sub != null) {
      return sub!.normalize(sliceSample);
    }

    final decoded = decodeBitString(sliceSample);
    if (decoded.isAllUnknown) {
      return NormalizedXZ(isX: decoded.isX);
    }
    if (decoded.isMixedUnknown) {
      return const NormalizedXZ(isX: true);
    }
    return NormalizedDouble(decoded.value!.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitFieldNormalizer &&
          highBit == other.highBit &&
          lowBit == other.lowBit &&
          sub == other.sub;

  @override
  int get hashCode => Object.hash(highBit, lowBit, sub);
}
