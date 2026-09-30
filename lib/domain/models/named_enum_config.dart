// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single entry in a user-authored value→label table.
@immutable
class NamedEnumEntry {
  const NamedEnumEntry({required this.value, required this.label});

  factory NamedEnumEntry.fromMap(Map<String, Object?> map) => NamedEnumEntry(
    value: BigInt.parse(map['value'] as String? ?? '0'),
    label: map['label'] as String? ?? '',
  );

  /// The unsigned integer value the signal must equal.
  final BigInt value;

  /// The label to display instead of the raw value.
  final String label;

  Map<String, Object?> toMap() => {
    'value': value.toString(),
    'label': label,
  };

  @override
  bool operator ==(Object other) =>
      other is NamedEnumEntry && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'NamedEnumEntry($value → $label)';
}

/// User-authored value→label mapping for the [DisplayFormat.namedEnum] format.
///
/// Serialized as the [translatorConfig] 'entries' key in [SignalEntry] and
/// stored in the `.wavecrux` session file. Import and export use the
/// GTKWave translate-filter `.txt` format for interoperability.
@immutable
class NamedEnumConfig {
  const NamedEnumConfig({this.entries = const []});

  factory NamedEnumConfig.fromMap(Map<String, Object?> map) {
    final raw =
        (map['entries'] as List<dynamic>?)
            ?.whereType<Map<String, Object?>>()
            .toList() ??
        [];
    return NamedEnumConfig(
      entries: raw.map(NamedEnumEntry.fromMap).toList(),
    );
  }

  final List<NamedEnumEntry> entries;

  /// Returns the label for [value], or null if no entry matches.
  String? translate(BigInt value) {
    for (final e in entries) {
      if (e.value == value) return e.label;
    }
    return null;
  }

  Map<String, Object?> toMap() => {
    'entries': entries.map((e) => e.toMap()).toList(),
  };

  NamedEnumConfig copyWith({List<NamedEnumEntry>? entries}) =>
      NamedEnumConfig(entries: entries ?? this.entries);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NamedEnumConfig) return false;
    if (entries.length != other.entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] != other.entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'NamedEnumConfig(${entries.length} entries)';
}
