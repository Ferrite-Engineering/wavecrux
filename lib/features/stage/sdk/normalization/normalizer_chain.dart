// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Composes an ordered list of [ValueNormalizer]s into a single normalizer.
///
/// Each stage runs over the *adapted* output of the previous stage. The
/// adaptation rules turn a [NormalizedValue] back into a synthetic
/// [RawSignalSample] for the next stage to consume:
///
/// - [NormalizedDouble] → analog sample (`isAnalog: true`,
///   `rawValue: value.toString()`).
/// - [NormalizedBool] → single-bit `'1'` / `'0'` scalar sample.
/// - [NormalizedString] → analog sample carrying the string text. Any
///   downstream stage that interprets numerically (e.g. linear) will
///   reach the [NormalizedXZ] fallback when the string isn't parseable.
/// - [NormalizedNumList] → not adaptable; chains stop here and return
///   the list as the final output. Adding a downstream stage after a
///   `NormalizedNumList` is a manifest validation error.
/// - [NormalizedXZ] → propagates immediately; no further stages run.
///
/// In practice the most common chain is `BitFieldNormalizer →
/// LinearNormalizer` (slice a multi-bit field, scale the result) — the
/// integer slice flows through as a [NormalizedDouble] and the linear
/// stage maps it onto the gauge range.
@immutable
class NormalizerChain extends ValueNormalizer {
  NormalizerChain(List<ValueNormalizer> stages)
    : assert(
        stages.isNotEmpty,
        'NormalizerChain needs at least one stage',
      ),
      stages = List<ValueNormalizer>.unmodifiable(stages);

  final List<ValueNormalizer> stages;

  @override
  String get kind => 'chain';

  @override
  NormalizedValue normalize(RawSignalSample sample) {
    var current = stages.first.normalize(sample);
    for (var i = 1; i < stages.length; i++) {
      if (current is NormalizedXZ) return current;
      final adapted = _adapt(current, sample);
      if (adapted == null) {
        // Reached a non-adaptable terminal value; stop chain here.
        return current;
      }
      current = stages[i].normalize(adapted);
    }
    return current;
  }

  RawSignalSample? _adapt(NormalizedValue value, RawSignalSample original) {
    switch (value) {
      case NormalizedDouble(value: final v):
        return RawSignalSample(
          rawValue: v.toString(),
          bitWidth: 0,
          timeTicks: original.timeTicks,
          isAnalog: true,
        );
      case NormalizedBool(value: final v):
        return RawSignalSample(
          rawValue: v ? '1' : '0',
          bitWidth: 1,
          timeTicks: original.timeTicks,
        );
      case NormalizedString(value: final s):
        return RawSignalSample(
          rawValue: s,
          bitWidth: 0,
          timeTicks: original.timeTicks,
          isAnalog: true,
        );
      case NormalizedNumList():
        return null;
      case NormalizedXZ():
        return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NormalizerChain) return false;
    if (stages.length != other.stages.length) return false;
    for (var i = 0; i < stages.length; i++) {
      if (stages[i] != other.stages[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(stages);
}
