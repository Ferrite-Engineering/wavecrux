// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';

/// Abstract base for every Stage Pro value normalizer.
///
/// Normalizers turn a raw waveform [RawSignalSample] into a
/// [NormalizedValue] suitable for binding to an animation parameter on
/// a custom widget. They are pure-Dart, side-effect-free, and stateless
/// — given the same input sample the same normalizer always produces the
/// same output. Implementations must be `const`-constructible where
/// possible so manifests can declare them at load time without per-frame
/// allocation.
///
/// Normalizers compose: a [NormalizerChain] runs an ordered list left to
/// right, feeding the output of one stage into the next.
@immutable
abstract class ValueNormalizer {
  const ValueNormalizer();

  /// Stable identifier for this normalizer kind, used by the manifest
  /// loader to dispatch from a YAML `kind:` discriminator to the matching
  /// concrete subtype. Use lower-snake-case (`"linear"`, `"enum"`,
  /// `"bit_field"`, `"boolean"`).
  String get kind;

  /// Transforms [sample] into a [NormalizedValue].
  ///
  /// Implementations should never throw on well-formed inputs — instead
  /// they return [NormalizedXZ] for samples whose values they cannot
  /// meaningfully coerce (per the normalizer's documented X/Z policy).
  /// Throwing a [StateError] is reserved for true programmer errors
  /// (e.g. running a [BitFieldNormalizer] over an analog sample).
  NormalizedValue normalize(RawSignalSample sample);
}

/// Policy for how a normalizer treats X (unknown) and Z (high-impedance)
/// bits in the input sample.
///
/// The policy chosen is per-normalizer; chained normalizers each apply
/// their own policy at their stage. The default for numeric normalizers
/// (`LinearNormalizer`) is [propagate]; the default for `EnumNormalizer`
/// is [defaultLabel] because mapping unknown values to a labeled state is
/// usually friendlier in instrument-style readouts.
enum XZPolicy {
  /// Emit a [NormalizedXZ] marker so the renderer can hatch/dash the
  /// affected widget. The most common default — preserves the meaning
  /// engineers expect from a logic analyser.
  propagate,

  /// Treat X / Z as the normalizer's `defaultValue` (e.g. `0.0` for
  /// linear scaling, the configured default label for enums). Useful when
  /// the widget cannot render an unknown state at all.
  asDefault,

  /// Reject the sample and emit `NormalizedXZ` only when *every* bit is
  /// X or Z. If the value contains a mix of valid bits and X/Z bits, the
  /// normalizer attempts to coerce as if X/Z were `0`. Approximates the
  /// "best effort" view used by some commercial tools.
  bestEffort,
}
