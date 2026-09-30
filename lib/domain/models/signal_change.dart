// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single value-change event: the signal took [value] at simulation tick [time].
///
/// [value] is always the wellen bit-string representation (e.g. `"0"`, `"1"`,
/// `"10xz"`, `"3.14"`) — formatting into hex/decimal/etc. is done by the
/// value-formatter service.
@immutable
class SignalChange {
  const SignalChange({required this.time, required this.value});

  /// Simulation time in ticks (unit determined by the file's [Timescale]).
  final int time;

  /// Raw value string as reported by the parser.
  final String value;

  // ── copyWith ───────────────────────────────────────────────────────────────

  SignalChange copyWith({int? time, String? value}) =>
      SignalChange(time: time ?? this.time, value: value ?? this.value);

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalChange &&
          runtimeType == other.runtimeType &&
          time == other.time &&
          value == other.value;

  @override
  int get hashCode => Object.hash(time, value);

  @override
  String toString() => 'SignalChange(time: $time, value: $value)';
}
