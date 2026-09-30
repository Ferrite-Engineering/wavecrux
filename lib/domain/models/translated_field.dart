// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Domain layer — ZERO Flutter imports. Color is carried as an int? ARGB
// (0xAARRGGBB); the UI layer converts it to a dart:ui Color when rendering.
import 'package:meta/meta.dart';

/// A single named subfield of a structured [TranslationResult].
///
/// Produced by translators that decompose a bus value into labelled pieces
/// (Stage 1 declarative struct/bitfield translators render these as expandable
/// child rows under the parent lane). The built-in value translator returns no
/// fields — it is a flat-string formatter.
@immutable
class TranslatedField {
  const TranslatedField({
    required this.name,
    required this.text,
    required this.hiBit,
    required this.loBit,
    this.fields = const [],
    this.colorArgb,
  });

  /// Human-readable field name, e.g. `"AxBURST"`.
  final String name;

  /// Formatted value text for this field, e.g. `"INCR"`.
  final String text;

  /// Most-significant bit index of this field within the parent value
  /// (inclusive). For a field spanning bits `[7:0]`, [hiBit] is `7`.
  final int hiBit;

  /// Least-significant bit index of this field within the parent value
  /// (inclusive). For a field spanning bits `[7:0]`, [loBit] is `0`.
  final int loBit;

  /// Nested decomposition of this field, or empty when the field is a leaf.
  final List<TranslatedField> fields;

  /// Optional ARGB color hint (`0xAARRGGBB`) the UI may use as a swatch or
  /// text color for this field. `null` means "no hint".
  final int? colorArgb;

  TranslatedField copyWith({
    String? name,
    String? text,
    int? hiBit,
    int? loBit,
    List<TranslatedField>? fields,
    int? colorArgb,
  }) {
    return TranslatedField(
      name: name ?? this.name,
      text: text ?? this.text,
      hiBit: hiBit ?? this.hiBit,
      loBit: loBit ?? this.loBit,
      fields: fields ?? this.fields,
      colorArgb: colorArgb ?? this.colorArgb,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslatedField &&
          name == other.name &&
          text == other.text &&
          hiBit == other.hiBit &&
          loBit == other.loBit &&
          colorArgb == other.colorArgb &&
          _fieldListEquals(fields, other.fields);

  @override
  int get hashCode => Object.hash(
    name,
    text,
    hiBit,
    loBit,
    colorArgb,
    Object.hashAll(fields),
  );

  @override
  String toString() =>
      'TranslatedField(name: $name, text: $text, '
      'bits: [$hiBit:$loBit], fields: ${fields.length}, colorArgb: $colorArgb)';
}

/// Deep equality for a list of [TranslatedField]s (domain layer has no access
/// to Flutter's `listEquals`).
bool _fieldListEquals(List<TranslatedField> a, List<TranslatedField> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
