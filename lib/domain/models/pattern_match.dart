// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A contiguous time region where a [PatternExpression] evaluated to `true`.
///
/// [time] is the first tick at which the pattern became true.
/// [endTime] is the first tick at which the pattern is no longer true.
/// [signalValues] is a snapshot of all signals referenced in the expression,
/// captured at [time] using raw VCD value strings.
@immutable
class PatternMatch {
  const PatternMatch({
    required this.time,
    required this.endTime,
    required this.signalValues,
  }) : assert(endTime >= time, 'endTime must be >= time');

  /// First tick at which the pattern is true.
  final int time;

  /// First tick at which the pattern is no longer true (exclusive end).
  final int endTime;

  /// Raw VCD values of all signals referenced in the expression, at [time].
  ///
  /// Keys are signal path strings; values are raw VCD bit-strings
  /// (e.g. `'1'`, `'b1011'`, `'x'`, `'3.14'`).
  final Map<String, String> signalValues;

  /// Duration in ticks that the pattern holds true.
  int get duration => endTime - time;

  PatternMatch copyWith({
    int? time,
    int? endTime,
    Map<String, String>? signalValues,
  }) => PatternMatch(
    time: time ?? this.time,
    endTime: endTime ?? this.endTime,
    signalValues: signalValues ?? Map.of(this.signalValues),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternMatch &&
          runtimeType == other.runtimeType &&
          time == other.time &&
          endTime == other.endTime &&
          _mapsEqual(signalValues, other.signalValues);

  @override
  int get hashCode => Object.hash(
    time,
    endTime,
    Object.hashAllUnordered(
      signalValues.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'PatternMatch(time: $time, endTime: $endTime, signals: $signalValues)';

  static bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
