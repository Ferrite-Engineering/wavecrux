// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';

/// A synthetic clocked bus whose signals behave like registered RTL outputs:
/// every change lands exactly on a rising clock edge.
///
/// The clock rises at `10 * cycle + 5` and falls at `10 * (cycle + 1)`, one
/// tick per unit. The value a signal has at the rising edge of cycle N (the
/// value a synchronous design captures there) is set by [set] for cycle N, and
/// it becomes visible at the timestamp of edge N-1 itself (cycle 0 at t=0), so
/// a read AT an edge's timestamp sees the next cycle's value. A decoder must
/// read the value in effect just before the edge.
///
/// Cycle `cycles` is one past the last edge: its values appear at the last
/// edge's timestamp and are never captured. A decoder that reads the value at
/// the edge instead of before it picks them up as one cycle too many.
class EdgeBus {
  EdgeBus({required this.cycles, this.clock = 'clk'});

  /// Number of rising edges in the trace.
  final int cycles;

  /// Logical name of the clock signal.
  final String clock;

  static const period = 10;

  /// Tick of the rising clock edge of [cycle].
  static int edge(int cycle) => period * cycle + 5;

  final _values = <String, List<String>>{};

  /// Defines [signal]: the value it has at each rising edge. Cycles not named
  /// in [at] take [fill]. [at] may name cycle [cycles] (see the class doc).
  void set(String signal, Map<int, String> at, {String fill = '0'}) {
    _values[signal] = [for (var c = 0; c <= cycles; c++) at[c] ?? fill];
  }

  /// A vector value of [width] bits.
  static String bin(int value, int width) =>
      'b${value.toUnsigned(width).toRadixString(2).padLeft(width, '0')}';

  /// The end of the trace: just after the last rising edge's falling edge.
  int get endTime => period * cycles;

  late final Map<String, List<(int, String)>> changes = _build();

  Map<String, List<(int, String)>> _build() {
    final out = <String, List<(int, String)>>{};
    final clk = <(int, String)>[(0, '0')];
    for (var c = 0; c < cycles; c++) {
      clk
        ..add((edge(c), '1'))
        ..add((period * (c + 1), '0'));
    }
    out[clock] = clk;
    for (final entry in _values.entries) {
      final list = <(int, String)>[];
      for (var c = 0; c <= cycles; c++) {
        final t = c == 0 ? 0 : edge(c - 1);
        final v = entry.value[c];
        if (list.isEmpty || list.last.$2 != v) list.add((t, v));
      }
      out[entry.key] = list;
    }
    return out;
  }

  SignalValueQuery get query => queryOf(changes);

  SignalChangesQuery get changesQuery => changesQueryOf(changes);
}

/// `query(name, t)` over explicit change lists: the last change at or before
/// `t`, or `null` before the first.
SignalValueQuery queryOf(Map<String, List<(int, String)>> changes) {
  return (signal, time) {
    String? held;
    for (final (t, v) in changes[signal] ?? const <(int, String)>[]) {
      if (t > time) break;
      held = v;
    }
    return held;
  };
}

/// `changesQuery(name, start, end)` over explicit change lists.
SignalChangesQuery changesQueryOf(Map<String, List<(int, String)>> changes) {
  return (signal, start, end) => [
    for (final e in changes[signal] ?? const <(int, String)>[])
      if (e.$1 >= start && e.$1 < end) e,
  ];
}
