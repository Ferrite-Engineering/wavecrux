// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/timescale.dart';

/// Callback that returns the signal value string at [time] for the signal
/// bound to [logicalName] in the decoder config.
///
/// Returns `null` if the signal is not loaded or has no value at that time.
typedef SignalValueQuery = String? Function(String logicalName, int time);

/// Callback that returns all value changes for the signal bound to
/// [logicalName] in the half-open interval `[startTime, endTime)`.
///
/// Each record is `(tickTime, newValue)`. The list is in ascending time order.
/// Returns an empty list if the signal has no changes in that range.
typedef SignalChangesQuery =
    List<(int, String)> Function(
      String logicalName,
      int startTime,
      int endTime,
    );

/// Abstract interface that every protocol decoder plugin must implement.
///
/// A decoder receives signal data via [SignalValueQuery] and
/// [SignalChangesQuery] callbacks and produces a list of [DecodedTransaction]s
/// for the requested time range.
abstract class ProtocolDecoder {
  /// Static metadata describing this decoder's inputs and configuration knobs.
  DecoderDefinition get definition;

  /// Decode the signal data in the half-open interval `[startTime, endTime)`
  /// and return the list of transactions found.
  ///
  /// [query] provides the held signal value at a specific tick.
  /// [changesQuery] enumerates all value changes in a tick range — required
  /// for clock-driven decoders that must walk transition edges.
  /// [timescale] is the waveform's simulation timescale, used by time-domain
  /// decoders (e.g. UART baud-rate calculation) to convert ticks ↔ real time.
  /// Falls back to 1 ns/tick when `null` (file has no `$timescale` directive).
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  });
}

/// Factory function that constructs a [ProtocolDecoder] from a [DecoderConfig].
typedef DecoderFactory = ProtocolDecoder Function(DecoderConfig config);

/// Extension of [ProtocolDecoder] for decoders that consume the output of a
/// parent decoder rather than (or in addition to) raw signal data.
///
/// A stacked decoder's [DecoderDefinition.parentDecoderId] is non-null and
/// points to the parent decoder's registry id. The two-pass loop in
/// `ActiveDecodersNotifier.decodeAll()` calls [decodeStacked] after all base
/// decoders have run, supplying the concatenated parent transactions sorted by
/// start time.
///
/// The [query] and [changesQuery] callbacks are provided for stacked decoders
/// that need to cross-reference raw signal values (e.g., to read a timestamp
/// not captured in the parent transaction). Most stacked decoders ignore them.
abstract class StackedDecoder implements ProtocolDecoder {
  const StackedDecoder();

  /// Decode by consuming [parentTransactions] from the parent decoder.
  ///
  /// [parentTransactions] is the merged, time-sorted list of all transactions
  /// produced by every active instance of the parent decoder type.
  /// [startTime] and [endTime] bound the decode range (same as [decode]).
  List<DecodedTransaction> decodeStacked(
    List<DecodedTransaction> parentTransactions,
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  });

  /// Stacked decoders delegate [decode] to [decodeStacked] with an empty
  /// parent list — this ensures the decoder is safe to call directly in tests
  /// that don't set up the two-pass infrastructure.
  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => decodeStacked(
    const [],
    startTime,
    endTime,
    query,
    changesQuery,
    timescale: timescale,
  );
}
