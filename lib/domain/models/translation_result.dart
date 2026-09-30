// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Domain layer — ZERO Flutter imports. Color is carried as an int? ARGB
// (0xAARRGGBB); the UI layer converts it to a dart:ui Color when rendering.
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/value_validity.dart';
import 'package:wavecrux/domain/models/translated_field.dart';

/// The structured result of translating one raw signal value.
///
/// Replaces the flat `String` returned by `ValueFormatService.format` with a
/// richer type: the primary [text] (always present, byte-for-byte identical to
/// the legacy formatted string for built-in formats), optional named [fields]
/// for translators that decompose a value into child rows, a per-value
/// [validity] hint, and an optional [colorArgb] color hint.
///
/// For scalar / flat values [fields] is empty and the consumer reads [text].
@immutable
class TranslationResult {
  const TranslationResult({
    required this.text,
    this.fields = const [],
    this.validity = ValueValidity.ok,
    this.colorArgb,
  });

  /// The primary human-readable text for this value (e.g. `"ff"`, `"-3"`).
  final String text;

  /// Named subfields for structured decompositions. Empty for scalar/flat
  /// values such as everything the built-in translator produces.
  final List<TranslatedField> fields;

  /// Whether the value is fully known, or carries unknown (`x`) / high-impedance
  /// (`z`) bits.
  final ValueValidity validity;

  /// Optional ARGB color hint (`0xAARRGGBB`) the UI may use as a swatch or text
  /// color. `null` means "no hint" (use the default lane color).
  final int? colorArgb;

  TranslationResult copyWith({
    String? text,
    List<TranslatedField>? fields,
    ValueValidity? validity,
    int? colorArgb,
  }) {
    return TranslationResult(
      text: text ?? this.text,
      fields: fields ?? this.fields,
      validity: validity ?? this.validity,
      colorArgb: colorArgb ?? this.colorArgb,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationResult &&
          text == other.text &&
          validity == other.validity &&
          colorArgb == other.colorArgb &&
          _fieldListEquals(fields, other.fields);

  @override
  int get hashCode =>
      Object.hash(text, validity, colorArgb, Object.hashAll(fields));

  @override
  String toString() =>
      'TranslationResult(text: $text, '
      'fields: ${fields.length}, validity: $validity, colorArgb: $colorArgb)';
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
