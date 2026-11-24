// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The waveform queries the in-app assistant's tools, the `wavecrux` command
/// line and its MCP server answer, written once.
///
/// Flutter-free on purpose: the headless binary (`bin/wavecrux.dart`) is
/// compiled for the plain Dart VM, and `test/static/headless_cli_closure_test.dart`
/// fails when anything reachable from here imports Flutter. The in-app tools
/// (`lib/services/ai/tools/viewer_navigation_tools.dart`) read the loaded
/// source from their providers and call these functions; the command line
/// opens the file through `WellenProvider` and calls the same ones, so the
/// app, the command line and the server cannot give different answers.
library;

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/signal_query/signal_search_service.dart';

/// Every variable of a hierarchy, by full path and by signal reference.
///
/// A signal argument may name either. The path wins: paths are unique per
/// hierarchy row, whereas FST aliasing can map one signal reference onto many
/// rows.
@immutable
class WaveSignalIndex {
  /// Indexes every variable under [rootScopes].
  factory WaveSignalIndex(List<Scope> rootScopes) {
    final byPath = <String, Variable>{};
    final byRef = <String, Variable>{};
    void collect(List<Scope> scopes) {
      for (final scope in scopes) {
        for (final variable in scope.variables) {
          byPath[variable.fullPath] = variable;
          byRef[variable.signalRef] = variable;
        }
        collect(scope.childScopes);
      }
    }

    collect(rootScopes);
    return WaveSignalIndex._(byPath, byRef);
  }

  const WaveSignalIndex._(this.byPath, this.byRef);

  /// Variables by [Variable.fullPath].
  final Map<String, Variable> byPath;

  /// Variables by [Variable.signalRef].
  final Map<String, Variable> byRef;

  /// The variable [signal] names, as a full path or a signal reference, or
  /// null when it names none.
  Variable? resolve(String signal) => resolveSignal(byPath, byRef, signal);
}

/// The variable [signal] names in either map, the path-keyed one first.
Variable? resolveSignal(
  Map<String, Variable> byPath,
  Map<String, Variable> byRef,
  String signal,
) => byPath[signal] ?? byRef[signal];

/// The answer to "which signals match [query]": every match, and the first
/// [limit] of them, in hierarchy order.
@immutable
class SignalSearchAnswer {
  /// Searches every variable under [rootScopes] by name.
  factory SignalSearchAnswer.search({
    required List<Scope> rootScopes,
    required String query,
    required SearchMode mode,
    required int limit,
  }) {
    final matches = SignalSearchService.search(
      variables: SignalSearchService.flattenVariables(rootScopes),
      query: query,
      mode: mode,
    );
    return SignalSearchAnswer._(
      query,
      mode,
      matches,
      List<SearchResult>.unmodifiable(matches.take(limit)),
    );
  }

  const SignalSearchAnswer._(
    this.query,
    this.mode,
    this.matches,
    this.returned,
  );

  /// What was asked.
  final String query;

  /// How [query] was matched.
  final SearchMode mode;

  /// Every match.
  final List<SearchResult> matches;

  /// The matches returned.
  final List<SearchResult> returned;

  /// The answer as the assistant's `searchSignal` tool and the `search`
  /// command give it.
  Map<String, Object?> toJson() => <String, Object?>{
    'query': query,
    'mode': mode.name,
    'matchCount': matches.length,
    'returned': returned.length,
    'truncated': matches.length > returned.length,
    'signals': <Map<String, Object?>>[
      for (final r in returned)
        <String, Object?>{
          'signalRef': r.variable.signalRef,
          'path': r.variable.fullPath,
          'bitWidth': r.variable.bitWidth,
          'varType': r.variable.varType.name,
          'direction': r.variable.direction.name,
        },
    ],
  };
}

/// The answer to "what did [variable] do between [start] and [end]": its
/// value at [start] and every recorded change in the half-open window
/// `[start, end)`, the first [returned] of them.
@immutable
class TransitionsAnswer {
  const TransitionsAnswer._({
    required this.variable,
    required this.start,
    required this.end,
    required this.valueAtStart,
    required this.changes,
    required this.returned,
  });

  /// The signal.
  final Variable variable;

  /// The window's first tick.
  final int start;

  /// The window's end, a tick not included.
  final int end;

  /// The value at (or last recorded before) [start]; null when nothing was
  /// recorded by then.
  final String? valueAtStart;

  /// Every change in the window, in time order.
  final List<SignalChange> changes;

  /// The changes returned.
  final List<SignalChange> returned;

  /// Whether some changes were not returned.
  bool get truncated => changes.length > returned.length;

  /// The answer as the assistant's `getTransitionsInWindow` tool gives it.
  Map<String, Object?> toJson() => <String, Object?>{
    'signal': variable.fullPath,
    'signalRef': variable.signalRef,
    'bitWidth': variable.bitWidth,
    'window': <String, Object?>{'start': start, 'end': end},
    'valueAtStart': valueAtStart,
    'transitionCount': changes.length,
    'returned': returned.length,
    'truncated': truncated,
    'transitions': <Map<String, Object?>>[
      for (final c in returned)
        <String, Object?>{'time': c.time, 'value': c.value},
    ],
  };
}

/// Loads [variable] from [source] and answers what it did in `[start, end)`,
/// returning at most [limit] changes. [start] must not be after [end].
Future<TransitionsAnswer> transitionsInWindow(
  WaveformDataSource source,
  Variable variable, {
  required int start,
  required int end,
  required int limit,
}) async {
  if (start > end) {
    throw ArgumentError.value(start, 'start', 'is after end $end');
  }
  await source.loadSignal(variable.signalRef);
  final changes = source.changesInRange(variable.signalRef, start, end);
  return TransitionsAnswer._(
    variable: variable,
    start: start,
    end: end,
    valueAtStart: source.valueAt(variable.signalRef, start),
    changes: changes,
    returned: List<SignalChange>.unmodifiable(changes.take(limit)),
  );
}

/// The ticks in `[from, to)` at which [clock] rises: a recorded change to `1`
/// from any other value (`0`, `x`, `z`). The first value ever recorded is not
/// an edge, having no value before it. [clock] must be loaded.
List<int> risingEdges(
  WaveformDataSource source,
  Variable clock, {
  required int from,
  required int to,
}) {
  var previous = from > 0 ? source.valueAt(clock.signalRef, from - 1) : null;
  final edges = <int>[];
  for (final change in source.changesInRange(clock.signalRef, from, to)) {
    if (change.value == '1' && previous != null && previous != '1') {
      edges.add(change.time);
    }
    previous = change.value;
  }
  return edges;
}
