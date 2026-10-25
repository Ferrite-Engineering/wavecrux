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
    this.signalPaths = const {},
  });

  /// Reconstructs a [DecoderConfig] from [json] produced by [toJson].
  ///
  /// Missing or wrong-typed `bindings` → empty bindings map. Missing
  /// `parameters` → empty parameters map. Missing `bindingPaths` (every
  /// session written before 1.1.1) → empty paths map. Non-string binding and
  /// path values are dropped silently. The caller is responsible for re-validating
  /// against the active decoder's schema before kicking off a decode
  /// (the decoder will see nulls / fall back to defaults for missing
  /// parameters per [DecoderParameter.defaultValue]).
  factory DecoderConfig.fromJson(Map<String, Object?> json) {
    final parametersRaw = json['parameters'];

    final bindings = _stringMapFromJson(json['bindings']);
    final paths = _stringMapFromJson(json['bindingPaths']);

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
      signalPaths: paths,
    );
  }

  static Map<String, String> _stringMapFromJson(Object? raw) {
    final out = <String, String>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is String) {
          out[entry.key as String] = entry.value as String;
        }
      }
    }
    return out;
  }

  /// Maps logical pin names declared in `DecoderDefinition.requiredSignals`
  /// and `optionalSignals` to the bound waveform signals.
  ///
  /// Key: logical name (e.g. `"mosi"`).
  /// Value: the backend-local `signalRef` of the bound signal (e.g. `"28"`).
  /// A ref is only meaningful against the file it came from; [signalPaths]
  /// is what survives a change to the dump.
  final Map<String, String> signalBindings;

  /// The canonical hierarchical path of each bound signal (e.g.
  /// `"top.spi.mosi"`), keyed like [signalBindings].
  ///
  /// Recorded when a session is saved and used on load and on reload to
  /// re-resolve each binding's ref against the opened waveform, because refs
  /// are renumbered whenever the dump changes. A slot whose path matches
  /// nothing keeps its path here with an empty ref, so it binds again once
  /// the signal returns. Empty for configs built in the UI before a save.
  final Map<String, String> signalPaths;

  /// Decoder-specific parameter values keyed by `DecoderParameter.name`.
  ///
  /// Unset parameters will use their `DecoderParameter.defaultValue` at
  /// decode time.
  final Map<String, dynamic> parameters;

  // ── JSON ───────────────────────────────────────────────────────────────────

  /// Serializes to a JSON-natural map for the `.wavecrux` document.
  ///
  /// Bindings are emitted as a plain `{logical-name: signalRef}` map, so a
  /// build that predates [signalPaths] still reads them; the paths ride in a
  /// sibling `bindingPaths` map, omitted when empty.
  /// Parameters are emitted as-is — values are `Object?` since per-decoder
  /// schemas declare their own types (`int`, `bool`, `String`, enum
  /// `String`s, …); shape validation happens at restore time on the
  /// per-decoder side, not here, to keep this serializer
  /// decoder-agnostic.
  Map<String, Object?> toJson() => <String, Object?>{
    'bindings': Map<String, String>.from(signalBindings),
    if (signalPaths.isNotEmpty)
      'bindingPaths': Map<String, String>.from(signalPaths),
    if (parameters.isNotEmpty)
      'parameters': Map<String, Object?>.from(parameters),
  };

  // ── copyWith ───────────────────────────────────────────────────────────────

  DecoderConfig copyWith({
    Map<String, String>? signalBindings,
    Map<String, dynamic>? parameters,
    Map<String, String>? signalPaths,
  }) => DecoderConfig(
    signalBindings: signalBindings ?? this.signalBindings,
    parameters: parameters ?? this.parameters,
    signalPaths: signalPaths ?? this.signalPaths,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DecoderConfig) return false;
    if (!_stringMapEqual(signalBindings, other.signalBindings)) return false;
    if (!_stringMapEqual(signalPaths, other.signalPaths)) return false;
    return _dynamicMapEqual(parameters, other.parameters);
  }

  @override
  int get hashCode => Object.hash(
    _mapHash(signalBindings),
    _mapHash(parameters),
    _mapHash(signalPaths),
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
