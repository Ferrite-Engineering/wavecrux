// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The output of a [ValueNormalizer] — a sealed-class union over the small
/// set of animation-parameter types Stage Pro widgets consume.
///
/// Stage Pro custom widgets bind their animation parameters to one of the
/// concrete subtypes:
///
/// - [NormalizedDouble] — analog gauges, level bars, alpha values, any
///   parameter expressed as a real number (commonly clamped to 0.0–1.0
///   by [LinearNormalizer]).
/// - [NormalizedBool] — LEDs, toggle switches, on/off indicators.
/// - [NormalizedString] — labeled state machines, decoded enum names,
///   anything whose visual representation is a textual label.
/// - [NormalizedNumList] — multi-channel parameters such as RGB triplets
///   or per-bit indicator strips.
/// - [NormalizedXZ] — explicit "unknown" or "high-impedance" rendering
///   path. Carries [isX] so renderers can choose hatch (X) versus dashed
///   (Z) treatments without re-inspecting the raw sample.
///
/// Pure Dart, no Flutter imports. Subclasses are immutable. Sealed so
/// downstream switch-statements are exhaustive — adding a new variant
/// triggers a compile-time error on every consumer.
@immutable
sealed class NormalizedValue {
  const NormalizedValue();
}

/// Real-valued normalized output. By convention numeric ranges produced
/// by [LinearNormalizer] sit in `0.0..1.0` (with optional clamping); other
/// normalizers may emit unclamped doubles for parameters such as gauge
/// rotation or scaled measurement values.
@immutable
final class NormalizedDouble extends NormalizedValue {
  const NormalizedDouble(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedDouble && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NormalizedDouble($value)';
}

/// Boolean normalized output. Used by LEDs, switches, status indicators.
@immutable
final class NormalizedBool extends NormalizedValue {
  const NormalizedBool({required this.value});

  final bool value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NormalizedBool && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NormalizedBool($value)';
}

/// String normalized output — a labeled state for FSM-style widgets, a
/// decoded enum name, or any other text the widget renders verbatim.
@immutable
final class NormalizedString extends NormalizedValue {
  const NormalizedString(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedString && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NormalizedString($value)';
}

/// Numeric-list normalized output — for example an RGB triplet
/// `[r, g, b]` driven from a 24-bit bus, or a per-bit indicator strip.
@immutable
final class NormalizedNumList extends NormalizedValue {
  NormalizedNumList(List<num> values) : values = List<num>.unmodifiable(values);

  final List<num> values;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NormalizedNumList) return false;
    if (values.length != other.values.length) return false;
    for (var i = 0; i < values.length; i++) {
      if (values[i] != other.values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);

  @override
  String toString() => 'NormalizedNumList($values)';
}

/// Marker output indicating the underlying sample is an unknown ([isX]
/// `true`) or high-impedance ([isX] `false`) value the normalizer chose
/// not to coerce. Renderers map this to hatch / dashed visualisations
/// rather than to a meaningful number, bool, or string.
@immutable
final class NormalizedXZ extends NormalizedValue {
  const NormalizedXZ({required this.isX});

  /// True for unknown (X), false for high-impedance (Z).
  final bool isX;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NormalizedXZ && isX == other.isX;

  @override
  int get hashCode => isX.hashCode;

  @override
  String toString() => 'NormalizedXZ(isX: $isX)';
}
