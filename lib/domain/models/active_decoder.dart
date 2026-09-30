// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';

/// An active instance of a protocol decoder in the waveform viewer.
///
/// Binds a specific decoder plugin (identified by [decoderId]) to a
/// [DecoderConfig] and accumulates the decoded [transactions] after
/// [ActiveDecodersNotifier.decodeAll] runs.
///
/// [instanceNumber] is a per-decoder-type monotonically increasing counter
/// (never reused after removal) so that two SPI instances show as "SPI #1"
/// and "SPI #2" rather than both showing as "SPI".
@immutable
class ActiveDecoder {
  const ActiveDecoder({
    required this.id,
    required this.decoderId,
    required this.config,
    required this.instanceNumber,
    this.transactions = const [],
  });

  /// Unique instance identifier assigned when this decoder is added.
  final String id;

  /// Registry key of the decoder plugin (e.g., `"spi"`, `"uart"`).
  final String decoderId;

  /// Signal bindings and parameter values for this decoder instance.
  final DecoderConfig config;

  /// Transactions produced by the last [ActiveDecodersNotifier.decodeAll] run.
  final List<DecodedTransaction> transactions;

  /// Per-decoder-type sequence number (1-based, never reused after removal).
  ///
  /// Used to disambiguate multiple instances of the same decoder type:
  /// "SPI #1", "SPI #2", etc.
  final int instanceNumber;

  /// Returns a display label combining [baseName] and [instanceNumber].
  ///
  /// Used by providers that lack a [BuildContext] for localisation. Widgets
  /// with a [BuildContext] should use the `decoderInstanceLabel` ARB string.
  String instanceLabel(String baseName) => '$baseName #$instanceNumber';

  ActiveDecoder copyWith({
    String? id,
    String? decoderId,
    DecoderConfig? config,
    List<DecodedTransaction>? transactions,
    int? instanceNumber,
  }) {
    return ActiveDecoder(
      id: id ?? this.id,
      decoderId: decoderId ?? this.decoderId,
      config: config ?? this.config,
      transactions: transactions ?? this.transactions,
      instanceNumber: instanceNumber ?? this.instanceNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveDecoder &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          decoderId == other.decoderId &&
          config == other.config &&
          instanceNumber == other.instanceNumber &&
          listEquals(transactions, other.transactions);

  @override
  int get hashCode => Object.hash(id, decoderId, config, instanceNumber);

  @override
  String toString() =>
      'ActiveDecoder(id: $id, decoderId: $decoderId, '
      'instanceNumber: $instanceNumber, transactions: ${transactions.length})';
}
