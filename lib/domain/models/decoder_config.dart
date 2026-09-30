// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Runtime configuration for a [ProtocolDecoder] instance.
///
/// Created by the UI after the user has assigned waveform signals to each
/// logical pin and optionally customised the decoder parameters.
@immutable
class DecoderConfig {
  const DecoderConfig({
    required this.signalBindings,
    this.parameters = const {},
  });

  /// Reconstructs a [DecoderConfig] from [json] produced by [toJson].
  ///
  /// Missing or wrong-typed `bindings` → empty bindings map. Missing
  /// `parameters` → empty parameters map. Non-string binding values are
  /// dropped silently. The caller is responsible for re-validating
  /// against the active decoder's schema before kicking off a decode
  /// (the decoder will see nulls / fall back to defaults for missing
  /// parameters per [DecoderParameter.defaultValue]).
  factory DecoderConfig.fromJson(Map<String, Object?> json) {
    final bindingsRaw = json['bindings'];
    final parametersRaw = json['parameters'];

    final bindings = <String, String>{};
    if (bindingsRaw is Map) {
      for (final entry in bindingsRaw.entries) {
        if (entry.key is String && entry.value is String) {
          bindings[entry.key as String] = entry.value as String;
        }
      }
    }

    final parameters = <String, dynamic>{};
    if (parametersRaw is Map) {
      for (final entry in parametersRaw.entries) {
        if (entry.key is String) {
          parameters[entry.key as String] = entry.value;
        }
      }
    }

    return DecoderConfig(
      signalBindings: bindings,
      parameters: parameters,
    );
  }

  /// Maps logical pin names declared in `DecoderDefinition.requiredSignals`
  /// and `optionalSignals` to the actual waveform signal paths.
  ///
  /// Key: logical name (e.g. `"mosi"`).
  /// Value: waveform signal path (e.g. `"top.spi.mosi"`).
  final Map<String, String> signalBindings;

  /// Decoder-specific parameter values keyed by `DecoderParameter.name`.
  ///
  /// Unset parameters will use their `DecoderParameter.defaultValue` at
  /// decode time.
  final Map<String, dynamic> parameters;

  // ── JSON ───────────────────────────────────────────────────────────────────

  /// Serializes to a JSON-natural map for the `.wavecrux` document.
  ///
  /// Bindings are emitted as a plain `{logical-name: signalRef}` map.
  /// Parameters are emitted as-is — values are `Object?` since per-decoder
  /// schemas declare their own types (`int`, `bool`, `String`, enum
  /// `String`s, …); shape validation happens at restore time on the
  /// per-decoder side, not here, to keep this serializer
  /// decoder-agnostic.
  Map<String, Object?> toJson() => <String, Object?>{
    'bindings': Map<String, String>.from(signalBindings),
    if (parameters.isNotEmpty)
      'parameters': Map<String, Object?>.from(parameters),
  };

  // ── copyWith ───────────────────────────────────────────────────────────────

  DecoderConfig copyWith({
    Map<String, String>? signalBindings,
    Map<String, dynamic>? parameters,
  }) => DecoderConfig(
    signalBindings: signalBindings ?? this.signalBindings,
    parameters: parameters ?? this.parameters,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DecoderConfig) return false;
    if (!_stringMapEqual(signalBindings, other.signalBindings)) return false;
    return _dynamicMapEqual(parameters, other.parameters);
  }

  @override
  int get hashCode => Object.hash(
    _mapHash(signalBindings),
    _mapHash(parameters),
  );

  @override
  String toString() =>
      'DecoderConfig(bindings: ${signalBindings.keys.toList()}, '
      'params: ${parameters.keys.toList()})';

  // ── private helpers ────────────────────────────────────────────────────────

  static bool _stringMapEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }

  static bool _dynamicMapEqual(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }

  static int _mapHash(Map<dynamic, dynamic> map) =>
      map.entries.fold(0, (h, e) => h ^ Object.hash(e.key, e.value));
}
