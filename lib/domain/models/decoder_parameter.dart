// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';

/// A configuration knob exposed by a protocol decoder.
///
/// For example, an SPI decoder might expose parameters for clock polarity,
/// bit order, and chip-select polarity.
@immutable
class DecoderParameter {
  const DecoderParameter({
    required this.name,
    required this.type,
    required this.defaultValue,
    required this.description,
    this.displayName,
    this.enumValues,
    this.enumLabels,
    this.labelKey,
    this.descriptionKey,
    this.enumLabelKeys,
  });

  /// Machine-readable identifier (e.g. `"cpol"`, `"baud_rate"`).
  final String name;

  /// Data type that determines how this parameter is presented in the UI.
  final DecoderParameterType type;

  /// Value used when the user has not explicitly configured this parameter.
  ///
  /// The runtime type must be consistent with [type]:
  /// - [DecoderParameterType.boolean] → [bool]
  /// - [DecoderParameterType.integer] → [int]
  /// - [DecoderParameterType.enumeration] → [String] (must be in [enumValues])
  /// - [DecoderParameterType.string] → [String]
  final dynamic defaultValue;

  /// Human-readable explanation of what this parameter controls.
  final String description;

  /// Optional human-readable label shown in the decoder config dialog instead
  /// of [name].  When `null`, [name] is displayed as a fallback.
  ///
  /// Example: `"Bit Order"` for a parameter whose [name] is `"bit_order"`.
  final String? displayName;

  /// Valid choices for [DecoderParameterType.enumeration] parameters.
  ///
  /// `null` for non-enumeration parameter types.
  final List<String>? enumValues;

  /// Optional human-readable labels for [DecoderParameterType.enumeration]
  /// values, shown in the dropdown instead of the raw machine value.
  ///
  /// Maps each entry in [enumValues] to a display label.  When a value has
  /// no entry here, the raw value is shown as a fallback.
  ///
  /// Example: `{'0': 'Active Low', '1': 'Active High'}`.
  final Map<String, String>? enumLabels;

  /// Optional ARB key for the parameter label, resolved at the widget layer
  /// through the decoder config label resolver
  /// (`decoderConfigLabelResolverFactoryProvider`).
  ///
  /// The domain layer has zero Flutter imports, so this is a plain key string;
  /// the dialog resolves it to a localized label. When `null`, the dialog
  /// falls back to [displayName] (then [name]).
  ///
  /// Example: `'spiParamCpol'`.
  final String? labelKey;

  /// Optional ARB key for the parameter description, resolved at the widget
  /// layer through the decoder config label resolver. When `null`, the dialog
  /// falls back to [description].
  ///
  /// Example: `'spiParamCpolDescription'`.
  final String? descriptionKey;

  /// Optional ARB keys for [DecoderParameterType.enumeration] value labels,
  /// resolved at the widget layer through the decoder config label resolver.
  ///
  /// Maps each enum value to its ARB key. When a value has no entry here (or
  /// this map is `null`), the dialog falls back to [enumLabels] (then the raw
  /// value).
  ///
  /// Example: `{'0': 'spiChoiceCpol0', '1': 'spiChoiceCpol1'}`.
  final Map<String, String>? enumLabelKeys;

  // ── copyWith ───────────────────────────────────────────────────────────────

  DecoderParameter copyWith({
    String? name,
    DecoderParameterType? type,
    dynamic defaultValue,
    String? description,
    String? displayName,
    bool clearDisplayName = false,
    List<String>? enumValues,
    bool clearEnumValues = false,
    Map<String, String>? enumLabels,
    bool clearEnumLabels = false,
    String? labelKey,
    bool clearLabelKey = false,
    String? descriptionKey,
    bool clearDescriptionKey = false,
    Map<String, String>? enumLabelKeys,
    bool clearEnumLabelKeys = false,
  }) => DecoderParameter(
    name: name ?? this.name,
    type: type ?? this.type,
    defaultValue: defaultValue ?? this.defaultValue,
    description: description ?? this.description,
    displayName: clearDisplayName ? null : (displayName ?? this.displayName),
    enumValues: clearEnumValues ? null : (enumValues ?? this.enumValues),
    enumLabels: clearEnumLabels ? null : (enumLabels ?? this.enumLabels),
    labelKey: clearLabelKey ? null : (labelKey ?? this.labelKey),
    descriptionKey: clearDescriptionKey
        ? null
        : (descriptionKey ?? this.descriptionKey),
    enumLabelKeys: clearEnumLabelKeys
        ? null
        : (enumLabelKeys ?? this.enumLabelKeys),
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DecoderParameter) return false;
    if (name != other.name) return false;
    if (type != other.type) return false;
    if (defaultValue != other.defaultValue) return false;
    if (description != other.description) return false;
    if (displayName != other.displayName) return false;
    if (labelKey != other.labelKey) return false;
    if (descriptionKey != other.descriptionKey) return false;
    // enumValues
    final ev = enumValues;
    final otherEv = other.enumValues;
    if (ev == null && otherEv == null) {
      // fall through to enumLabels check
    } else if (ev == null || otherEv == null) {
      return false;
    } else {
      if (ev.length != otherEv.length) return false;
      for (var i = 0; i < ev.length; i++) {
        if (ev[i] != otherEv[i]) return false;
      }
    }
    // enumLabels
    final el = enumLabels;
    final otherEl = other.enumLabels;
    if (el == null && otherEl == null) {
      // fall through to enumLabelKeys check
    } else if (el == null || otherEl == null) {
      return false;
    } else {
      if (el.length != otherEl.length) return false;
      for (final key in el.keys) {
        if (!otherEl.containsKey(key) || otherEl[key] != el[key]) return false;
      }
    }
    // enumLabelKeys
    final elk = enumLabelKeys;
    final otherElk = other.enumLabelKeys;
    if (elk == null && otherElk == null) return true;
    if (elk == null || otherElk == null) return false;
    if (elk.length != otherElk.length) return false;
    for (final key in elk.keys) {
      if (!otherElk.containsKey(key) || otherElk[key] != elk[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    type,
    defaultValue,
    description,
    displayName,
    enumValues == null ? null : Object.hashAll(enumValues!),
    enumLabels == null
        ? null
        : Object.hashAll(
            enumLabels!.entries.map((e) => Object.hash(e.key, e.value)),
          ),
    labelKey,
    descriptionKey,
    enumLabelKeys == null
        ? null
        : Object.hashAll(
            enumLabelKeys!.entries.map((e) => Object.hash(e.key, e.value)),
          ),
  );

  @override
  String toString() =>
      'DecoderParameter(name: $name, type: $type, default: $defaultValue)';
}
