// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';

/// Serializable snapshot of a single active decoder instance, for
/// round-tripping through the `.wavecrux` session document.
///
/// Pairs the registry key ([decoderId]) and the user's per-instance
/// [config] with the [instanceNumber] that disambiguates multiple
/// instances of the same decoder type in the UI ("SPI #1", "SPI #2", …).
/// Restoring a persisted decoder preserves the same number so the user
/// sees the same labels across restarts.
///
/// The runtime `ActiveDecoder.id` (e.g. `decoder_3`) is intentionally
/// **not** persisted — it is a process-local handle re-assigned by
/// [ActiveDecodersNotifier.addDecoder] on restore, and persisting it
/// would invite stale-reference bugs (e.g. a UI cursor referencing
/// `decoder_3` after the auto-numbered run-id collided with another
/// session's). The `transactions` list is similarly omitted: it is
/// re-derived by `decodeAll` against the freshly-opened waveform.
@immutable
class PersistedDecoder {
  const PersistedDecoder({
    required this.decoderId,
    required this.instanceNumber,
    required this.config,
  });

  /// Reconstructs a [PersistedDecoder] from [json] produced by
  /// [toJson]. Missing fields fall back to safe defaults — an empty
  /// `decoderId` is preserved so the unknown-id restore path can fire
  /// rather than silently dropping the entry here.
  factory PersistedDecoder.fromJson(Map<String, Object?> json) =>
      PersistedDecoder(
        decoderId: (json['decoderId'] as String?) ?? '',
        instanceNumber: (json['instanceNumber'] as int?) ?? 1,
        config: DecoderConfig.fromJson(
          (json['config'] as Map?)?.cast<String, Object?>() ??
              const <String, Object?>{},
        ),
      );

  /// Registry key of the decoder plugin (e.g. `"spi"`, `"uart"`).
  /// Matches [ActiveDecoder.decoderId].
  final String decoderId;

  /// Per-decoder-type sequence number (1-based, never reused after
  /// removal). Persisted so "SPI #2" remains "SPI #2" across restarts.
  final int instanceNumber;

  /// Signal bindings and parameter values for this decoder instance.
  final DecoderConfig config;

  Map<String, Object?> toJson() => <String, Object?>{
    'decoderId': decoderId,
    'instanceNumber': instanceNumber,
    'config': config.toJson(),
  };

  PersistedDecoder copyWith({
    String? decoderId,
    int? instanceNumber,
    DecoderConfig? config,
  }) => PersistedDecoder(
    decoderId: decoderId ?? this.decoderId,
    instanceNumber: instanceNumber ?? this.instanceNumber,
    config: config ?? this.config,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistedDecoder &&
          runtimeType == other.runtimeType &&
          decoderId == other.decoderId &&
          instanceNumber == other.instanceNumber &&
          config == other.config;

  @override
  int get hashCode => Object.hash(decoderId, instanceNumber, config);

  @override
  String toString() =>
      'PersistedDecoder(decoderId: $decoderId, '
      'instanceNumber: $instanceNumber, config: $config)';
}
