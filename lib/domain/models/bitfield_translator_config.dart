// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Domain layer — ZERO Flutter imports.
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/display_format.dart';

/// The `translatorConfig` map key under which a per-signal custom-translator
/// binding records the [Translator.id] to route through.
///
/// `DisplayFormat` remains the built-in namespace; when this key is present in
/// [SignalEntry.translatorConfig] the value column resolves that translator id
/// from the [TranslatorRegistry] instead of the built-in one. Authored bitfield
/// translators store their id here alongside their `fields` payload.
const String kTranslatorIdConfigKey = 'translator';

/// One named subfield of a [BitfieldTranslatorConfig].
///
/// Slices the parent bus value across the MSB-indexed inclusive range
/// `[hiBit:loBit]` and formats the slice with [format]. [subConfig] carries the
/// per-field config payload the chosen [format] needs — a [NamedEnumConfig] map
/// for [DisplayFormat.namedEnum], a [QFormatConfig] map for
/// [DisplayFormat.fixedPointQ], or a nested [BitfieldTranslatorConfig] map (a
/// `fields` key) for struct-in-struct decomposition.
@immutable
class BitFieldSpec {
  const BitFieldSpec({
    required this.name,
    required this.hiBit,
    required this.loBit,
    this.format = DisplayFormat.hexadecimal,
    this.subConfig,
  });

  factory BitFieldSpec.fromMap(Map<String, Object?> map) => BitFieldSpec(
    name: map['name'] as String? ?? '',
    hiBit: (map['hiBit'] as num?)?.toInt() ?? 0,
    loBit: (map['loBit'] as num?)?.toInt() ?? 0,
    format: _formatFromName(map['format'] as String?),
    subConfig: (map['subConfig'] as Map?)?.cast<String, Object?>(),
  );

  /// Field label, e.g. `"AxBURST"`.
  final String name;

  /// Most-significant bit of the slice within the parent value (inclusive).
  final int hiBit;

  /// Least-significant bit of the slice within the parent value (inclusive).
  final int loBit;

  /// How the sliced sub-value is rendered.
  final DisplayFormat format;

  /// Per-field config payload for [format]; null when the format needs none.
  final Map<String, Object?>? subConfig;

  /// Bit width of the slice. Non-positive when the range is malformed.
  int get width => hiBit - loBit + 1;

  /// Whether this spec is structurally valid for an [parentWidth]-bit parent.
  bool isValidFor(int parentWidth) =>
      loBit >= 0 && hiBit >= loBit && hiBit < parentWidth && name.isNotEmpty;

  Map<String, Object?> toMap() => {
    'name': name,
    'hiBit': hiBit,
    'loBit': loBit,
    'format': format.name,
    if (subConfig != null) 'subConfig': subConfig,
  };

  BitFieldSpec copyWith({
    String? name,
    int? hiBit,
    int? loBit,
    DisplayFormat? format,
    Map<String, Object?>? subConfig,
    bool clearSubConfig = false,
  }) => BitFieldSpec(
    name: name ?? this.name,
    hiBit: hiBit ?? this.hiBit,
    loBit: loBit ?? this.loBit,
    format: format ?? this.format,
    subConfig: clearSubConfig ? null : (subConfig ?? this.subConfig),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitFieldSpec &&
          other.name == name &&
          other.hiBit == hiBit &&
          other.loBit == loBit &&
          other.format == format &&
          _subConfigEquals(subConfig, other.subConfig);

  @override
  int get hashCode =>
      Object.hash(name, hiBit, loBit, format, subConfig?.length);

  @override
  String toString() => 'BitFieldSpec($name [$hiBit:$loBit] ${format.name})';
}

/// Declarative struct/bitfield translator configuration.
///
/// Stored in [SignalEntry.translatorConfig] alongside the
/// [kTranslatorIdConfigKey] binding. Decomposes a bus value into named
/// [fields], each rendered as an expandable child row aligned under the parent
/// signal. Authored in Settings → Custom Translators.
@immutable
class BitfieldTranslatorConfig {
  const BitfieldTranslatorConfig({this.fields = const []});

  factory BitfieldTranslatorConfig.fromMap(Map<String, Object?> map) {
    final raw =
        (map['fields'] as List<dynamic>?)
            ?.whereType<Map<dynamic, dynamic>>()
            .map((e) => e.cast<String, Object?>())
            .toList() ??
        const [];
    return BitfieldTranslatorConfig(
      fields: raw.map(BitFieldSpec.fromMap).toList(),
    );
  }

  final List<BitFieldSpec> fields;

  Map<String, Object?> toMap() => {
    'fields': fields.map((f) => f.toMap()).toList(),
  };

  BitfieldTranslatorConfig copyWith({List<BitFieldSpec>? fields}) =>
      BitfieldTranslatorConfig(fields: fields ?? this.fields);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BitfieldTranslatorConfig) return false;
    if (fields.length != other.fields.length) return false;
    for (var i = 0; i < fields.length; i++) {
      if (fields[i] != other.fields[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(fields);

  @override
  String toString() => 'BitfieldTranslatorConfig(${fields.length} fields)';
}

DisplayFormat _formatFromName(String? name) {
  if (name == null) return DisplayFormat.hexadecimal;
  for (final f in DisplayFormat.values) {
    if (f.name == name) return f;
  }
  return DisplayFormat.hexadecimal;
}

bool _subConfigEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    final av = a[key];
    final bv = b[key];
    if (av is List && bv is List) {
      if (av.length != bv.length) return false;
    } else if (av != bv) {
      return false;
    }
  }
  return true;
}
