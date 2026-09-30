// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Coerces a scalar (1-bit) sample into a [NormalizedBool].
///
/// Bit value `1` maps to `true`, `0` to `false`. X / Z handling follows
/// [xzPolicy]:
///
/// - [XZPolicy.propagate] — emit [NormalizedXZ] (the renderer can paint
///   an indeterminate / hatched LED).
/// - [XZPolicy.asDefault] — emit [NormalizedBool] of [defaultValue].
/// - [XZPolicy.bestEffort] — same as [XZPolicy.asDefault] for scalar
///   samples (there are no "valid bits to keep" to differentiate).
///
/// Multi-bit samples are reduced via [reduction]:
///
/// - [BooleanReduction.lsb] (default) — examine bit 0 only.
/// - [BooleanReduction.anyHigh] — true if any bit is `1`.
/// - [BooleanReduction.allHigh] — true only if all bits are `1`.
@immutable
class BooleanNormalizer extends ValueNormalizer {
  const BooleanNormalizer({
    this.reduction = BooleanReduction.lsb,
    this.xzPolicy = XZPolicy.propagate,
    this.defaultValue = false,
  });

  final BooleanReduction reduction;
  final XZPolicy xzPolicy;
  final bool defaultValue;

  @override
  String get kind => 'boolean';

  @override
  NormalizedValue normalize(RawSignalSample sample) {
    if (sample.isAnalog) {
      // For analog samples non-zero ⇒ true, NaN ⇒ X.
      final parsed = double.tryParse(sample.rawValue);
      if (parsed == null || parsed.isNaN) return _xzOrDefault(isX: true);
      return NormalizedBool(value: parsed != 0.0);
    }

    final stripped = sample.rawValue.toLowerCase().startsWith('b')
        ? sample.rawValue.substring(1)
        : sample.rawValue;
    if (stripped.isEmpty) return _xzOrDefault(isX: true);

    var sawX = false;
    var sawZ = false;
    var anyOne = false;
    var allOne = true;
    final lsb = stripped[stripped.length - 1];
    for (final ch in stripped.split('')) {
      switch (ch.toLowerCase()) {
        case '1':
          anyOne = true;
        case '0':
          allOne = false;
        case 'x':
          sawX = true;
          allOne = false;
        case 'z':
          sawZ = true;
          allOne = false;
        default:
          sawX = true;
          allOne = false;
      }
    }

    bool? evaluate() {
      switch (reduction) {
        case BooleanReduction.lsb:
          switch (lsb.toLowerCase()) {
            case '1':
              return true;
            case '0':
              return false;
            default:
              return null;
          }
        case BooleanReduction.anyHigh:
          // anyHigh is unambiguous when at least one '1' exists, even if
          // other bits are X/Z (the result is definitely true).
          if (anyOne) return true;
          if (sawX || sawZ) return null;
          return false;
        case BooleanReduction.allHigh:
          // allHigh is unambiguous when at least one '0' exists (false),
          // or all bits are '1' (true). Mixed X/Z is indeterminate.
          if (!anyOne && !sawX && !sawZ) return false;
          if (allOne) return true;
          if (sawX || sawZ) return null;
          return false;
      }
    }

    final decided = evaluate();
    if (decided != null) return NormalizedBool(value: decided);
    return _xzOrDefault(isX: sawX || !sawZ);
  }

  NormalizedValue _xzOrDefault({required bool isX}) {
    switch (xzPolicy) {
      case XZPolicy.propagate:
        return NormalizedXZ(isX: isX);
      case XZPolicy.asDefault:
      case XZPolicy.bestEffort:
        return NormalizedBool(value: defaultValue);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BooleanNormalizer &&
          reduction == other.reduction &&
          xzPolicy == other.xzPolicy &&
          defaultValue == other.defaultValue;

  @override
  int get hashCode => Object.hash(reduction, xzPolicy, defaultValue);
}

/// How a [BooleanNormalizer] reduces a multi-bit sample to a single bool.
enum BooleanReduction {
  /// Examine the least-significant bit only (the default).
  lsb,

  /// True if any bit is `1`.
  anyHigh,

  /// True only if every bit is `1`.
  allHigh,
}
