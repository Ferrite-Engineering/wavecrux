// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/_bit_string_decoder.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Maps a vector / scalar bit-string sample to a labeled state string.
///
/// Powers state-machine widgets and badges (`"IDLE"`, `"RUNNING"`,
/// `"ERROR"`). Unmatched values fall back to [defaultLabel] when set, or
/// emit [NormalizedXZ] when no default is provided. X / Z handling
/// follows [xzPolicy]:
///
/// - [XZPolicy.propagate] (default) — any X / Z bit emits
///   [NormalizedXZ] regardless of [defaultLabel].
/// - [XZPolicy.asDefault] — X / Z samples emit [defaultLabel] when set,
///   else [NormalizedXZ].
/// - [XZPolicy.bestEffort] — X / Z bits coerce to `0` and the resulting
///   numeric value is looked up in [labels].
///
/// Lookup keys are [BigInt] so widths beyond 64 bits work correctly. The
/// constructor accepts `int` or [BigInt] keys and normalises internally.
@immutable
class EnumNormalizer extends ValueNormalizer {
  EnumNormalizer({
    required Map<Object, String> labels,
    this.defaultLabel,
    this.xzPolicy = XZPolicy.propagate,
  }) : labels = Map<BigInt, String>.unmodifiable({
         for (final entry in labels.entries) _coerceKey(entry.key): entry.value,
       });

  static BigInt _coerceKey(Object key) {
    if (key is BigInt) return key;
    if (key is int) return BigInt.from(key);
    throw ArgumentError(
      'EnumNormalizer label keys must be int or BigInt, got ${key.runtimeType}',
    );
  }

  /// Map of integer value → label string.
  final Map<BigInt, String> labels;

  /// Label returned when the input value is not present in [labels].
  /// Null disables the default fallback (unmatched ⇒ [NormalizedXZ]).
  final String? defaultLabel;

  final XZPolicy xzPolicy;

  @override
  String get kind => 'enum';

  @override
  NormalizedValue normalize(RawSignalSample sample) {
    if (sample.isAnalog) {
      throw StateError(
        'EnumNormalizer cannot consume analog samples; chain with a '
        'sample-converter first or bind to a scalar/vector signal.',
      );
    }

    final decoded = decodeBitString(sample);
    if (decoded.isAllUnknown) {
      return _xzOrDefault(isX: decoded.isX);
    }
    if (decoded.isMixedUnknown && xzPolicy == XZPolicy.propagate) {
      return _xzOrDefault(isX: true);
    }

    final value = decoded.value!;
    final label = labels[value];
    if (label != null) return NormalizedString(label);
    if (defaultLabel != null) return NormalizedString(defaultLabel!);
    return const NormalizedXZ(isX: false);
  }

  NormalizedValue _xzOrDefault({required bool isX}) {
    switch (xzPolicy) {
      case XZPolicy.propagate:
        return NormalizedXZ(isX: isX);
      case XZPolicy.asDefault:
      case XZPolicy.bestEffort:
        if (defaultLabel != null) return NormalizedString(defaultLabel!);
        return NormalizedXZ(isX: isX);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EnumNormalizer) return false;
    if (defaultLabel != other.defaultLabel) return false;
    if (xzPolicy != other.xzPolicy) return false;
    if (labels.length != other.labels.length) return false;
    for (final entry in labels.entries) {
      if (other.labels[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    defaultLabel,
    xzPolicy,
    labels.length,
    // Hash a stable digest of the labels map.
    Object.hashAll(labels.entries.map((e) => Object.hash(e.key, e.value))),
  );
}
