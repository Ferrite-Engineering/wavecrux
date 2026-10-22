// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// A uniform **step lattice**: step k sits at `origin + k·pitch`.
///
/// A waveform has simulation ticks, not steps, so a receiver of a step-indexed
/// coordinate (CXP §9.9.2 `riscv.formal.trace_step`, §9.9.3
/// `formal.trace_step`) must recover the lattice from the trace before it can
/// convert. Both bindings use this one recovery, from a different set of
/// ticks: the RVFI resolver measures it on the RVFI channels, the formal
/// resolver on one edge of the trace's clock.
@immutable
class TraceStepLattice {
  /// Creates a lattice. [pitch] must be positive.
  const TraceStepLattice({
    required this.origin,
    required this.pitch,
    required this.lastStep,
  }) : assert(pitch > 0, 'pitch must be positive');

  /// Tick of step 0, the trace's initial state.
  final int origin;

  /// Ticks per step.
  final int pitch;

  /// Highest step the trace can address.
  final int lastStep;

  /// Whether [tick] lies on the lattice (inside or past the trace).
  bool contains(int tick) => tick >= origin && (tick - origin) % pitch == 0;

  /// The simulation tick of [step], or null when the trace does not reach it.
  int? tickForStep(int step) {
    if (step < 0 || step > lastStep) return null;
    return origin + step * pitch;
  }

  /// The lattice through [ticks], or null when they are not uniform.
  ///
  /// 1. [start] and [end] join [ticks]; ticks outside them are dropped.
  /// 2. The origin is [start]: step 0 *is* the trace's initial state, by both
  ///    bindings' definition, so the lattice's phase is not a free parameter.
  /// 3. The pitch is the **smallest positive gap** between consecutive
  ///    distinct ticks.
  /// 4. Every tick must lie on `origin + k·pitch`. Irregular ticks yield
  ///    **null**, and the caller declines the coordinate rather than landing
  ///    somewhere plausible and wrong.
  ///
  /// The bound this cannot see past: ticks that occur only on every other
  /// step give a lattice coarse by a factor of two, and nothing in the ticks
  /// tells the two cases apart. The callers choose their ticks so that every
  /// step leaves one.
  static TraceStepLattice? fromTicks(
    Iterable<int> ticks, {
    required int start,
    required int end,
  }) {
    if (end < start) return null;
    final all = <int>{start, end};
    for (final tick in ticks) {
      if (tick >= start && tick <= end) all.add(tick);
    }
    if (all.length < 2) return null;

    final sorted = all.toList()..sort();
    var pitch = sorted[1] - sorted[0];
    for (var i = 2; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap > 0 && gap < pitch) pitch = gap;
    }
    if (pitch <= 0) return null;

    for (final tick in sorted) {
      if ((tick - start) % pitch != 0) return null;
    }
    return TraceStepLattice(
      origin: start,
      pitch: pitch,
      lastStep: (end - start) ~/ pitch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TraceStepLattice &&
      other.origin == origin &&
      other.pitch == pitch &&
      other.lastStep == lastStep;

  @override
  int get hashCode => Object.hash(origin, pitch, lastStep);

  @override
  String toString() =>
      'TraceStepLattice(origin: $origin, pitch: $pitch, lastStep: $lastStep)';
}

/// The most variables [FormalTraceStepGrid.derive] reads.
///
/// A witness trace from a property check holds the design's signals, a few
/// hundred at most; an equivalence trace holds both designs. The grid needs
/// every signal it reads loaded, so the walk is bounded: past this many, the
/// first ones in hierarchy order decide it.
const int kFormalGridVariableCap = 4096;

/// What [FormalTraceStepGrid.derive] found: a lattice, or why there is none.
@immutable
class FormalTraceStepGridResult {
  const FormalTraceStepGridResult._(this.lattice, this.refusal);

  /// A grid was established.
  const FormalTraceStepGridResult.lattice(TraceStepLattice lattice)
    : this._(lattice, null);

  /// No grid; [refusal] says why, for the acknowledgement's `reason`.
  const FormalTraceStepGridResult.refused(String refusal)
    : this._(null, refusal);

  /// The grid, or null when refused.
  final TraceStepLattice? lattice;

  /// Why no grid was established; null when [lattice] is set.
  final String? refusal;
}

/// The step grid of a formal witness trace (CXP §9.9.3).
///
/// ### What the trace says about its own steps
///
/// Every witness trace in the reference corpus (written by `yosys-smtbmc`
/// under SymbiYosys and EQY) puts sample k at time 10·k, and the design's
/// clock, where the trace carries one, **rises** at exactly those instants
/// and falls half way between them. So the clock toggles twice per step: a
/// lattice measured on every transition of the trace lands on half steps, and
/// step 7 would be read as tick 35. That is the trap the RVFI grid avoids by
/// measuring only the RVFI channels, and the reason this grid measures one
/// edge of the clock.
///
/// ### How the grid is established
///
/// 1. Every variable is read (up to [kFormalGridVariableCap]) and every tick
///    at which any of them changes is collected.
/// 2. A **toggler** is a one-bit signal with at least one rise and one fall.
///    With no toggler at all (an equivalence check of combinational logic
///    has no clock wire), the lattice comes from every tick of the trace:
///    uniform spacing is the step grid, and non-uniform spacing is a refusal.
/// 3. A toggler is **clock-shaped** when its rising edges form a lattice
///    ([TraceStepLattice.fromTicks]) and every one of its falls lies strictly
///    between two steps of it. A signal that changes on the steps themselves
///    is data, however often it toggles. With togglers but none
///    clock-shaped, the trace is refused, never read by rule 2: the
///    half-step trap is exactly a trace whose every tick is uniform.
/// 4. A clock-shaped lattice **holds** only when every tick off it is a
///    transition of a clock-shaped toggler with that same lattice (the trace
///    repeats the clock at every level of the hierarchy: `clk`, `gold.clk`,
///    `gate.clk`). Anything else changing between two steps means that
///    rising edge is not the step edge. A one-bit data signal can look
///    clock-shaped (high for one step near the end of a trace); the real
///    clock's own edges between its steps are what rule it out.
/// 5. Exactly one lattice must hold. None is a refusal; two are two clocks,
///    which the binding does not cover, and also a refusal.
///
/// The trace also declares `smt_step`, the solver's own step counter, outside
/// any scope. The waveform readers do not expose variables declared outside a
/// scope, so this grid does not read it; the corpus test checks the grid
/// against it from the file's text instead.
abstract final class FormalTraceStepGrid {
  /// Derives the grid from [source] over [variables], every one of which the
  /// caller has loaded. See the class doc for the five rules.
  static FormalTraceStepGridResult derive({
    required WaveformDataSource source,
    required List<Variable> variables,
  }) {
    final start = source.startTime;
    final end = source.endTime;
    if (end < start) {
      return const FormalTraceStepGridResult.refused(
        'the loaded trace has no time range',
      );
    }
    final read = variables.length > kFormalGridVariableCap
        ? variables.sublist(0, kFormalGridVariableCap)
        : variables;

    // Every tick, and for each tick the variables that change there.
    final changersAt = <int, Set<String>>{};
    final edges = <String, _Edges>{};
    for (final variable in read) {
      final changes = source.changesInRange(
        variable.signalRef,
        start,
        end + 1,
      );
      String? previous;
      final rises = <int>[];
      final falls = <int>[];
      for (final change in changes) {
        if (change.time < start || change.time > end) continue;
        (changersAt[change.time] ??= <String>{}).add(variable.signalRef);
        if (variable.bitWidth == 1) {
          final value = change.value;
          if (previous == '0' && value == '1') rises.add(change.time);
          if (previous == '1' && value == '0') falls.add(change.time);
          previous = value;
        }
      }
      if (rises.isNotEmpty && falls.isNotEmpty) {
        edges[variable.signalRef] = _Edges(rises, falls);
      }
    }

    if (edges.isEmpty) {
      final lattice = TraceStepLattice.fromTicks(
        changersAt.keys,
        start: start,
        end: end,
      );
      if (lattice == null) {
        return const FormalTraceStepGridResult.refused(
          'the loaded trace has no clock and its samples are not evenly '
          'spaced, so a formal step cannot be converted to a time',
        );
      }
      return FormalTraceStepGridResult.lattice(lattice);
    }

    // Rule 3: the clock-shaped togglers, grouped by the lattice each gives.
    final clocksOn = <TraceStepLattice, Set<String>>{};
    for (final toggler in edges.entries) {
      final lattice = TraceStepLattice.fromTicks(
        toggler.value.rises,
        start: start,
        end: end,
      );
      if (lattice == null) continue;
      if (toggler.value.falls.any(lattice.contains)) continue;
      (clocksOn[lattice] ??= <String>{}).add(toggler.key);
    }
    // Rules 4 and 5: the lattices between whose steps only their own clocks
    // move.
    final holding = <TraceStepLattice>[
      for (final entry in clocksOn.entries)
        if (_onlyClocksMoveBetweenSteps(entry.key, entry.value, changersAt))
          entry.key,
    ];
    if (holding.isEmpty) {
      return const FormalTraceStepGridResult.refused(
        'no clock edge in the loaded trace gives an even step grid, so a '
        'formal step cannot be converted to a time',
      );
    }
    if (holding.length > 1) {
      return const FormalTraceStepGridResult.refused(
        'the loaded trace has more than one clock, so a formal step cannot '
        'be converted to a time',
      );
    }
    return FormalTraceStepGridResult.lattice(holding.single);
  }

  /// Whether every tick off [lattice] is a transition of one of [clocks].
  static bool _onlyClocksMoveBetweenSteps(
    TraceStepLattice lattice,
    Set<String> clocks,
    Map<int, Set<String>> changersAt,
  ) {
    for (final entry in changersAt.entries) {
      if (lattice.contains(entry.key)) continue;
      if (!entry.value.every(clocks.contains)) return false;
    }
    return true;
  }
}

/// The rising and falling edges of one one-bit signal.
class _Edges {
  _Edges(this.rises, this.falls);

  final List<int> rises;
  final List<int> falls;
}

/// What resolving a `formal.trace_step` coordinate produced: a tick to place
/// the cursor at, or why there is none.
@immutable
class FormalCoordinateResolution {
  /// The coordinate resolved to [time], the tick of [step].
  const FormalCoordinateResolution.landed({
    required int this.time,
    required int this.step,
  }) : reason = null;

  /// The coordinate could not be resolved. The caller still honours the
  /// element (CXP §9.4) and reports [reason] in the acknowledgement.
  const FormalCoordinateResolution.declined(String this.reason)
    : time = null,
      step = null;

  /// The tick to place the primary cursor at; null when declined.
  final int? time;

  /// The step that landed; null when declined.
  final int? step;

  /// Why the coordinate was declined; null when it landed.
  final String? reason;

  /// Whether the coordinate produced a cursor placement.
  bool get landed => time != null;
}

/// Resolves a CXP §9.9.3 `formal.trace_step` coordinate into a tick of
/// **this** loaded trace: the consumer half of a counterexample or cover
/// hand-off.
///
/// The producer states the step the solver reported (step 0 is the initial
/// state); whoever holds the trace owns the conversion to time. The step is
/// placed on [FormalTraceStepGrid]'s lattice, and a trace whose grid cannot be
/// established declines the coordinate rather than guessing.
///
/// `sub_id` (an equivalence partition) and every attribute are display
/// material: CXP §9.9's rule 2 forbids needing them to resolve.
///
/// Pure Dart, so every decision is directly testable.
class FormalStreamCoordinateResolver {
  /// Creates a resolver.
  const FormalStreamCoordinateResolver();

  /// Whether [streamId] is the stream this resolver implements.
  static bool implementsStream(String streamId) =>
      streamId == CxpStreamCoordinate.formalTraceStepStreamId;

  /// Resolves [coordinate] against [source], whose [variables] the caller has
  /// loaded.
  FormalCoordinateResolution resolve({
    required CxpStreamCoordinate coordinate,
    required WaveformDataSource source,
    required List<Variable> variables,
  }) {
    if (!implementsStream(coordinate.streamId)) {
      return FormalCoordinateResolution.declined(
        'wavecrux does not implement the "${coordinate.streamId}" stream; '
        'the element was honoured without it',
      );
    }
    final grid = FormalTraceStepGrid.derive(
      source: source,
      variables: variables,
    );
    final lattice = grid.lattice;
    if (lattice == null) {
      return FormalCoordinateResolution.declined(grid.refusal!);
    }
    final step = coordinate.sequenceIndex;
    final tick = lattice.tickForStep(step);
    if (tick == null) {
      return FormalCoordinateResolution.declined(
        'step $step is past the end of the loaded trace '
        '(last step ${lattice.lastStep})',
      );
    }
    return FormalCoordinateResolution.landed(time: tick, step: step);
  }
}
