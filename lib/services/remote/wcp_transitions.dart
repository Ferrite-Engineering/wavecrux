// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// WCP's `wavecrux.getTransitionsInWindow`, extracted from
// remote_control_notifier.dart: its bounds and its handler, which answers
// from the same `transitionsInWindow` the `transitions` command and the
// in-app assistant's tool call. A part file, so the handler keeps the
// notifier's private access.

part of 'remote_control_notifier.dart';

/// `wavecrux.getTransitionsInWindow`: the most signals one call names, as for
/// the `transitions` command.
const int kWcpTransitionsMaxSignals = 32;

/// `wavecrux.getTransitionsInWindow`: changes per signal when `limit` is not
/// given, as for the `transitions` command.
const int kWcpTransitionsLimitDefault = 200;

/// `wavecrux.getTransitionsInWindow`: the largest `limit`, as for the
/// `transitions` command.
const int kWcpTransitionsLimitMax = 10000;

/// `wavecrux.getTransitionsInWindow`: the most changes one reply carries
/// across all its signals. Bounds the reply the app encodes on its UI thread
/// (about 2 MB at worst) whatever the number of signals.
const int kWcpTransitionsWindowMax = 20000;

/// The changes per signal a `wavecrux.getTransitionsInWindow` reply naming
/// [signalCount] signals returns when `limit` is [requested]: [requested],
/// lowered alike for every signal so that the reply carries at most
/// [kWcpTransitionsWindowMax] changes.
int wcpTransitionsLimit(int requested, int signalCount) {
  final share = kWcpTransitionsWindowMax ~/ signalCount;
  return requested < share ? requested : share;
}

extension _WcpTransitions on RemoteControlNotifier {
  /// Every recorded change of each of `signal_paths` in the half-open window
  /// `[start, end)`, with its value at `start`: per signal, the in-app
  /// assistant's `getTransitionsInWindow` answer and `next_from`, from the
  /// same [transitionsInWindow] the `transitions` command calls.
  ///
  /// Bounded twice: `limit` changes per signal (default
  /// [kWcpTransitionsLimitDefault], at most [kWcpTransitionsLimitMax]), and
  /// [kWcpTransitionsWindowMax] changes in the whole reply, met by lowering
  /// every signal's limit alike. The reply's `limit` is the one applied; a
  /// signal cut short says `truncated` and gives `next_from`, the tick after
  /// its last change returned, to ask again from.
  Future<Map<String, dynamic>?> _handleGetTransitionsInWindow(
    Map<String, dynamic> data,
  ) async {
    final rawPaths = data['signal_paths'];
    if (rawPaths is! List ||
        rawPaths.isEmpty ||
        rawPaths.any((p) => p is! String || p.isEmpty)) {
      throw const WcpException(
        '"signal_paths" must be a non-empty list of signal paths',
        code: 3,
      );
    }
    if (rawPaths.length > kWcpTransitionsMaxSignals) {
      throw const WcpException(
        '"signal_paths" names at most $kWcpTransitionsMaxSignals signals',
        code: 3,
      );
    }
    final paths = rawPaths.cast<String>();
    final start = data['start'];
    final end = data['end'];
    if (start is! int || end is! int || start < 0 || end < 0) {
      throw const WcpException(
        '"start" and "end" must be whole ticks, not negative',
        code: 3,
      );
    }
    if (start > end) {
      throw WcpException('"start" $start is after "end" $end', code: 3);
    }
    final rawLimit = data['limit'] ?? kWcpTransitionsLimitDefault;
    if (rawLimit is! int ||
        rawLimit < 1 ||
        rawLimit > kWcpTransitionsLimitMax) {
      throw const WcpException(
        '"limit" must be a whole number from 1 to $kWcpTransitionsLimitMax',
        code: 3,
      );
    }
    final source = _activeTab.read(waveformSourceProvider).value;
    if (source == null) {
      throw const WcpException('No waveform file loaded', code: 5);
    }
    final index = WaveSignalIndex(source.rootScopes);
    final variables = <Variable>[];
    for (final path in paths) {
      final variable = index.resolve(path);
      if (variable == null) {
        throw WcpException('Item not found: $path', code: 6);
      }
      variables.add(variable);
    }
    final limit = wcpTransitionsLimit(rawLimit, variables.length);
    final answers = <TransitionsAnswer>[
      for (final v in variables)
        await transitionsInWindow(
          source,
          v,
          start: start,
          end: end,
          limit: limit,
        ),
    ];
    return {
      'window': {'start': start, 'end': end},
      'limit': limit,
      'truncated': answers.any((a) => a.truncated),
      // A limit that fell among several changes at one tick: next_from
      // starts after that tick, so the rest of it needs a higher limit.
      'same_tick_split': [
        for (final a in answers)
          if (a.splitsLastTick) a.variable.fullPath,
      ],
      'signals': [for (final a in answers) a.toPagedJson()],
    };
  }
}
