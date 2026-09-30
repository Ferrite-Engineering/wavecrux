// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single decoded protocol transaction produced by a [ProtocolDecoder].
///
/// Transactions are rendered as labelled spans on a dedicated overlay lane
/// in the waveform canvas. Clicking a transaction jumps the cursor to
/// [startTime].
@immutable
class DecodedTransaction {
  const DecodedTransaction({
    required this.startTime,
    required this.endTime,
    required this.label,
    this.fields = const {},
    this.isError = false,
    this.errorMessage,
  });

  /// Simulation tick at which this transaction begins.
  final int startTime;

  /// Simulation tick at which this transaction ends (inclusive).
  final int endTime;

  /// Short human-readable summary shown in the waveform lane
  /// (e.g. `"Write 0xFF"`, `"Read 0x50"`).
  final String label;

  /// Decoded field name → formatted value pairs shown in the detail view.
  ///
  /// Example for an I²C transfer:
  /// `{"address": "0x50", "rw": "W", "data": "0xFF", "ack": "ACK"}`.
  final Map<String, String> fields;

  /// `true` when the decoder detected a protocol violation within this
  /// transaction's time range.
  final bool isError;

  /// Human-readable description of the violation. Non-null only when
  /// [isError] is `true`.
  final String? errorMessage;

  // ── copyWith ───────────────────────────────────────────────────────────────

  DecodedTransaction copyWith({
    int? startTime,
    int? endTime,
    String? label,
    Map<String, String>? fields,
    bool? isError,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => DecodedTransaction(
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    label: label ?? this.label,
    fields: fields ?? this.fields,
    isError: isError ?? this.isError,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DecodedTransaction) return false;
    if (startTime != other.startTime) return false;
    if (endTime != other.endTime) return false;
    if (label != other.label) return false;
    if (isError != other.isError) return false;
    if (errorMessage != other.errorMessage) return false;
    return _fieldsEqual(fields, other.fields);
  }

  @override
  int get hashCode => Object.hash(
    startTime,
    endTime,
    label,
    isError,
    errorMessage,
    fields.entries.fold<int>(0, (h, e) => h ^ Object.hash(e.key, e.value)),
  );

  @override
  String toString() =>
      'DecodedTransaction(start: $startTime, end: $endTime, '
      'label: "$label", isError: $isError)';

  // ── private helpers ────────────────────────────────────────────────────────

  static bool _fieldsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }
}
