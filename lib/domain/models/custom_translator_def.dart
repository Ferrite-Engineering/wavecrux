// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Domain layer — ZERO Flutter imports.
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';

/// A named, user-authored declarative bit-field translator.
///
/// Authored in Settings → Custom Translators and referenced by name when bound
/// to a signal. Binding writes [config] (plus the [kTranslatorIdConfigKey]
/// marker) into the signal's `translatorConfig`, which the `.wavecrux` session
/// persists — so a bound signal keeps its decomposition across save/load.
@immutable
class CustomTranslatorDef {
  const CustomTranslatorDef({required this.name, required this.config});

  factory CustomTranslatorDef.fromMap(Map<String, Object?> map) =>
      CustomTranslatorDef(
        name: map['name'] as String? ?? '',
        config: BitfieldTranslatorConfig.fromMap(
          (map['config'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
      );

  /// User-visible, unique name (e.g. `"AXI ARSIZE"`).
  final String name;

  /// The declarative bit-field decomposition.
  final BitfieldTranslatorConfig config;

  Map<String, Object?> toMap() => {
    'name': name,
    'config': config.toMap(),
  };

  CustomTranslatorDef copyWith({
    String? name,
    BitfieldTranslatorConfig? config,
  }) => CustomTranslatorDef(
    name: name ?? this.name,
    config: config ?? this.config,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomTranslatorDef &&
          other.name == name &&
          other.config == config;

  @override
  int get hashCode => Object.hash(name, config);

  @override
  String toString() => 'CustomTranslatorDef($name, ${config.fields.length})';
}
