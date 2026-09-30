// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/_bit_string_decoder.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Linearly maps a raw bit-string or analog sample onto an output range,
/// optionally clamping out-of-range inputs.
///
/// The map is `output = outputMin + (input - inputMin) /
/// (inputMax - inputMin) * (outputMax - outputMin)`.
///
/// Bit-string samples are decoded as unsigned integers (X / Z handled per
/// [xzPolicy]); analog samples ([RawSignalSample.isAnalog] `true`) are
/// parsed as doubles. Samples whose effective input falls outside
/// `[inputMin, inputMax]` are clamped when [clamp] is `true` (the default
/// for gauge-style use); otherwise the unclamped value is returned, which
/// is useful for accumulator-style widgets that legitimately exceed the
/// nominal range.
@immutable
class LinearNormalizer extends ValueNormalizer {
  const LinearNormalizer({
    required this.inputMin,
    required this.inputMax,
    this.outputMin = 0.0,
    this.outputMax = 1.0,
    this.clamp = true,
    this.xzPolicy = XZPolicy.propagate,
    this.defaultValue = 0.0,
  }) : assert(inputMax != inputMin, 'inputMin == inputMax produces a NaN map');

  final double inputMin;
  final double inputMax;
  final double outputMin;
  final double outputMax;
  final bool clamp;
  final XZPolicy xzPolicy;

  /// Value emitted when [xzPolicy] is [XZPolicy.asDefault] and the sample
  /// resolves to X / Z.
  final double defaultValue;

  @override
  String get kind => 'linear';

  @override
  NormalizedValue normalize(RawSignalSample sample) {
    final double input;

    if (sample.isAnalog) {
      final parsed = double.tryParse(sample.rawValue);
      if (parsed == null || parsed.isNaN) {
        return _xzOrDefault(isX: true);
      }
      input = parsed;
    } else {
      final decoded = decodeBitString(sample);
      if (decoded.isAllUnknown) {
        return _xzOrDefault(isX: decoded.isX);
      }
      if (decoded.isMixedUnknown && xzPolicy == XZPolicy.propagate) {
        return _xzOrDefault(isX: true);
      }
      input = decoded.value!.toDouble();
    }

    final clamped = clamp ? input.clamp(inputMin, inputMax) : input;
    final t = (clamped - inputMin) / (inputMax - inputMin);
    final mapped = outputMin + t * (outputMax - outputMin);
    return NormalizedDouble(mapped);
  }

  NormalizedValue _xzOrDefault({required bool isX}) {
    switch (xzPolicy) {
      case XZPolicy.propagate:
        return NormalizedXZ(isX: isX);
      case XZPolicy.asDefault:
      case XZPolicy.bestEffort:
        return NormalizedDouble(defaultValue);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinearNormalizer &&
          inputMin == other.inputMin &&
          inputMax == other.inputMax &&
          outputMin == other.outputMin &&
          outputMax == other.outputMax &&
          clamp == other.clamp &&
          xzPolicy == other.xzPolicy &&
          defaultValue == other.defaultValue;

  @override
  int get hashCode => Object.hash(
    inputMin,
    inputMax,
    outputMin,
    outputMax,
    clamp,
    xzPolicy,
    defaultValue,
  );
}
