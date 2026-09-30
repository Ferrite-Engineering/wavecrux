// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// One per-binding normalizer declaration in a manifest's `parameters`
/// block.
///
/// Each entry binds a [ValueNormalizer] (or chain) to a signal binding by
/// name. The runtime instantiates the normalizer at manifest load time so
/// the per-frame hot path only invokes [ValueNormalizer.normalize].
///
/// Manifest authors write parameters like:
///
/// ```yaml
/// parameters:
///   - binding: data
///     normalizer:
///       chain:
///         - kind: bit_field
///           high_bit: 15
///           low_bit: 8
///         - kind: linear
///           input_min: 0
///           input_max: 255
///           output_min: 0.0
///           output_max: 1.0
/// ```
@immutable
class ManifestParameter {
  const ManifestParameter({
    required this.binding,
    required this.normalizer,
  });

  /// Name of the binding this parameter applies to. Must reference a
  /// declared [ManifestSignalBinding.name].
  final String binding;

  /// The normalizer (possibly a [NormalizerChain]) to apply to samples
  /// drawn from the bound signal.
  final ValueNormalizer normalizer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManifestParameter &&
          binding == other.binding &&
          normalizer == other.normalizer;

  @override
  int get hashCode => Object.hash(binding, normalizer);

  @override
  String toString() =>
      'ManifestParameter(binding: $binding, normalizer: ${normalizer.kind})';
}
