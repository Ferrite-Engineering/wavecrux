// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/ai/ai_tool_result.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/ai/ai_tool.dart';
import 'package:wavecrux/services/signal_query/signal_search_service.dart';
import 'package:wavecrux/services/signal_query/x_trace_service.dart';

/// The open-core viewer-navigation AI tools.
///
/// Each tool is grounded in real loaded-waveform data via the live provider
/// graph: it reads signals, transitions, decoded transactions, cursor and
/// selection state through the same providers the UI uses, and every
/// substantive datum it returns carries an [AiCoordinate] citation the viewer
/// can jump to. No tool fabricates data; expected failures (no waveform loaded,
/// unknown signal) are returned as [AiToolResult.failure], never thrown.
///
/// The closed-source Pro overlay adds analysis tools (Debug Advisor,
/// decoder-aware queries, X-trace causal chains) through `extraAiToolsProvider`
/// — it does not modify this list.
List<AiTool> viewerNavigationAiTools() => <AiTool>[
  _searchSignalTool(),
  _getTransitionsInWindowTool(),
  _listDecodedTransactionsTool(),
  _getSelectionContextTool(),
  _jumpCursorTool(),
  _addMarkerTool(),
];

// ── searchSignal ──────────────────────────────────────────────────────────────

AiTool _searchSignalTool() => AiTool(
  spec: const AiToolSpec(
    name: 'searchSignal',
    description:
        'Search the loaded waveform hierarchy for signals by name. '
        'Returns matching signals with a stable signalRef, full path, bit '
        'width, type and direction.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Name pattern to match (substring by default).',
        },
        'mode': {
          'type': 'string',
          'enum': ['substring', 'glob'],
          'description': 'Match mode. Defaults to substring.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum signals to return. Defaults to 50.',
        },
      },
      'required': ['query'],
    },
  ),
  handler: (ref, args) async {
    final source = _source(ref);
    if (source == null) return AiToolResult.failure('No waveform loaded.');

    final query = _asString(args['query']) ?? '';
    final mode = _asString(args['mode']) == 'glob'
        ? SearchMode.glob
        : SearchMode.substring;
    final limit = _asInt(args['limit']) ?? 50;

    final variables = SignalSearchService.flattenVariables(source.rootScopes);
    final results = SignalSearchService.search(
      variables: variables,
      query: query,
      mode: mode,
    );
    final limited = results.take(limit).toList();

    return AiToolResult.ok(
      <String, Object?>{
        'query': query,
        'mode': mode.name,
        'matchCount': results.length,
        'returned': limited.length,
        'truncated': results.length > limited.length,
        'signals': <Map<String, Object?>>[
          for (final r in limited)
            <String, Object?>{
              'signalRef': r.variable.signalRef,
              'path': r.variable.fullPath,
              'bitWidth': r.variable.bitWidth,
              'varType': r.variable.varType.name,
              'direction': r.variable.direction.name,
            },
        ],
      },
      citations: <AiCoordinate>[
        for (final r in limited)
          AiCoordinate(
            signalRef: r.variable.signalRef,
            signalPath: r.variable.fullPath,
          ),
      ],
    );
  },
);

// ── getTransitionsInWindow ──────────────────────────────────────────────────────

AiTool _getTransitionsInWindowTool() => AiTool(
  spec: const AiToolSpec(
    name: 'getTransitionsInWindow',
    description:
        'Return the value transitions of a signal within a tick '
        'window. Each transition cites a (signal, time) coordinate the '
        'viewer can jump to.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'signal': {
          'type': 'string',
          'description': 'A signalRef or full hierarchical path.',
        },
        'startTime': {'type': 'integer', 'description': 'Window start tick.'},
        'endTime': {'type': 'integer', 'description': 'Window end tick.'},
        'limit': {
          'type': 'integer',
          'description': 'Maximum transitions to return. Defaults to 200.',
        },
      },
      'required': ['signal', 'startTime', 'endTime'],
    },
  ),
  handler: (ref, args) async {
    final source = _source(ref);
    if (source == null) return AiToolResult.failure('No waveform loaded.');

    final signalArg = _asString(args['signal']);
    if (signalArg == null) return AiToolResult.failure('Missing "signal".');
    final variable = _resolveVariable(ref, signalArg);
    if (variable == null) {
      return AiToolResult.failure('Unknown signal: "$signalArg".');
    }

    final start = _asInt(args['startTime']);
    final end = _asInt(args['endTime']);
    if (start == null || end == null) {
      return AiToolResult.failure('startTime and endTime are required.');
    }
    final (lo, hi) = _ordered(start, end);
    final limit = _asInt(args['limit']) ?? 200;

    await source.loadSignal(variable.signalRef);
    final changes = source.changesInRange(variable.signalRef, lo, hi);
    final limited = changes.take(limit).toList();
    final valueAtStart = source.valueAt(variable.signalRef, lo);

    return AiToolResult.ok(
      <String, Object?>{
        'signal': variable.fullPath,
        'signalRef': variable.signalRef,
        'bitWidth': variable.bitWidth,
        'window': <String, Object?>{'start': lo, 'end': hi},
        'valueAtStart': valueAtStart,
        'transitionCount': changes.length,
        'returned': limited.length,
        'truncated': changes.length > limited.length,
        'transitions': <Map<String, Object?>>[
          for (final c in limited)
            <String, Object?>{'time': c.time, 'value': c.value},
        ],
      },
      citations: <AiCoordinate>[
        for (final c in limited)
          AiCoordinate(
            signalRef: variable.signalRef,
            signalPath: variable.fullPath,
            time: c.time,
          ),
      ],
    );
  },
);

// ── listDecodedTransactions ─────────────────────────────────────────────────────

AiTool _listDecodedTransactionsTool() => AiTool(
  spec: const AiToolSpec(
    name: 'listDecodedTransactions',
    description:
        'List decoded protocol transactions from active decoders, '
        'optionally filtered by decoder and tick window.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'decoderId': {
          'type': 'string',
          'description': 'Restrict to a decoder instance id or decoder type.',
        },
        'startTime': {'type': 'integer', 'description': 'Window start tick.'},
        'endTime': {'type': 'integer', 'description': 'Window end tick.'},
        'limit': {
          'type': 'integer',
          'description': 'Maximum transactions to return. Defaults to 200.',
        },
      },
    },
  ),
  handler: (ref, args) async {
    final decoders = ref.read(activeDecodersProvider);
    final decoderFilter = _asString(args['decoderId']);
    final start = _asInt(args['startTime']);
    final end = _asInt(args['endTime']);
    final limit = _asInt(args['limit']) ?? 200;
    final (lo, hi) = (start != null && end != null)
        ? _ordered(start, end)
        : (null, null);

    final flat = _flattenTransactions(
      decoders,
      decoderFilter: decoderFilter,
      windowStart: lo,
      windowEnd: hi,
    );
    final limited = flat.take(limit).toList();

    return AiToolResult.ok(
      <String, Object?>{
        'transactionCount': flat.length,
        'returned': limited.length,
        'truncated': flat.length > limited.length,
        'transactions': <Map<String, Object?>>[
          for (final e in limited) _transactionMap(e.$1, e.$2, full: true),
        ],
      },
      citations: <AiCoordinate>[
        for (final e in limited) AiCoordinate(time: e.$2.startTime),
      ],
    );
  },
);

// ── getSelectionContext ─────────────────────────────────────────────────────────

AiTool _getSelectionContextTool() => AiTool(
  spec: const AiToolSpec(
    name: 'getSelectionContext',
    description:
        'Summarize the current selection (or an explicit signals + '
        'tick window) into a compact, token-efficient structured context: '
        "each signal's value at the window start, its transitions in the "
        'window, any decoded transactions overlapping the window, and an '
        'X-origin trace when a signal is unknown (X). Every datum cites a '
        'stable (signal, time) coordinate.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'signals': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'signalRefs or full paths. Defaults to the current selection.',
        },
        'startTime': {
          'type': 'integer',
          'description':
              'Window start tick. Defaults to the cursor range '
              'or the full loaded range.',
        },
        'endTime': {'type': 'integer', 'description': 'Window end tick.'},
        'maxTransitionsPerSignal': {
          'type': 'integer',
          'description': 'Per-signal transition cap. Defaults to 32.',
        },
      },
    },
  ),
  handler: (ref, args) async {
    final source = _source(ref);
    if (source == null) return AiToolResult.failure('No waveform loaded.');

    final signals = _selectionSignals(ref, args)
      ..sort((a, b) => a.fullPath.compareTo(b.fullPath));
    final (lo, hi) = _selectionWindow(ref, args, source);
    final maxPerSignal = _asInt(args['maxTransitionsPerSignal']) ?? 32;
    final timescale = ref.read(currentTimescaleProvider);
    const xtrace = XTraceService();

    final citations = <AiCoordinate>[];
    final signalEntries = <Map<String, Object?>>[];
    for (final v in signals.take(_kMaxSelectionSignals)) {
      await source.loadSignal(v.signalRef);
      final valueAtStart = source.valueAt(v.signalRef, lo);
      final changes = source.changesInRange(v.signalRef, lo, hi);
      final limited = changes.take(maxPerSignal).toList();

      citations.add(
        AiCoordinate(
          signalRef: v.signalRef,
          signalPath: v.fullPath,
          time: lo,
        ),
      );
      for (final c in limited) {
        citations.add(
          AiCoordinate(
            signalRef: v.signalRef,
            signalPath: v.fullPath,
            time: c.time,
          ),
        );
      }

      Map<String, Object?>? xOrigin;
      final valueAtEnd = source.valueAt(v.signalRef, hi);
      if (valueAtEnd != null && _containsX(valueAtEnd)) {
        final origin = xtrace.findXOrigin(v.signalRef, v.fullPath, hi, source);
        if (origin != null) {
          xOrigin = <String, Object?>{
            'originTime': origin.originTime,
            if (origin.previousValue != null)
              'previousValue': origin.previousValue,
          };
          citations.add(
            AiCoordinate(
              signalRef: v.signalRef,
              signalPath: v.fullPath,
              time: origin.originTime,
            ),
          );
        }
      }

      signalEntries.add(<String, Object?>{
        'path': v.fullPath,
        'signalRef': v.signalRef,
        'bitWidth': v.bitWidth,
        'valueAtStart': valueAtStart,
        'transitionCount': changes.length,
        'returned': limited.length,
        'truncated': changes.length > limited.length,
        'transitions': <Map<String, Object?>>[
          for (final c in limited)
            <String, Object?>{'time': c.time, 'value': c.value},
        ],
        'xOrigin': ?xOrigin,
      });
    }

    final flatTxns = _flattenTransactions(
      ref.read(activeDecodersProvider),
      windowStart: lo,
      windowEnd: hi,
    );
    final limitedTxns = flatTxns.take(_kMaxSelectionTransactions).toList();
    for (final e in limitedTxns) {
      citations.add(AiCoordinate(time: e.$2.startTime));
    }

    return AiToolResult.ok(
      <String, Object?>{
        'window': <String, Object?>{'start': lo, 'end': hi},
        'timescale': timescale == null
            ? null
            : <String, Object?>{
                'display': timescale.displayString,
                'secondsPerTick': timescale.secondsPerTick,
              },
        'signalCount': signals.length,
        'signalsReturned': signalEntries.length,
        'signals': signalEntries,
        'transactionCount': flatTxns.length,
        'transactionsReturned': limitedTxns.length,
        'transactions': <Map<String, Object?>>[
          for (final e in limitedTxns) _transactionMap(e.$1, e.$2),
        ],
      },
      citations: citations,
    );
  },
);

// ── jumpCursor ────────────────────────────────────────────────────────────────

AiTool _jumpCursorTool() => AiTool(
  spec: const AiToolSpec(
    name: 'jumpCursor',
    description:
        'Move the primary cursor to a simulation tick. Returns the '
        'resulting (clamped-to-range) cursor time.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'time': {'type': 'integer', 'description': 'Target tick.'},
      },
      'required': ['time'],
    },
  ),
  handler: (ref, args) async {
    final time = _asInt(args['time']);
    if (time == null) return AiToolResult.failure('Missing "time".');

    ref.read(cursorStateProvider.notifier).placePrimary(time);
    final result = ref.read(cursorStateProvider).primaryCursorTime;

    return AiToolResult.ok(
      <String, Object?>{'requestedTime': time, 'cursorTime': result},
      citations: <AiCoordinate>[
        if (result != null) AiCoordinate(time: result),
      ],
    );
  },
);

// ── addMarker ─────────────────────────────────────────────────────────────────

AiTool _addMarkerTool() => AiTool(
  spec: const AiToolSpec(
    name: 'addMarker',
    description:
        'Place a named marker (a–z) at a simulation tick. If no '
        'name is given, the next free letter is chosen. Returns the marker '
        'name and time.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'time': {'type': 'integer', 'description': 'Marker tick.'},
        'name': {
          'type': 'string',
          'description': 'Single lowercase letter a–z. Optional.',
        },
      },
      'required': ['time'],
    },
  ),
  handler: (ref, args) async {
    final time = _asInt(args['time']);
    if (time == null) return AiToolResult.failure('Missing "time".');

    final inUse = ref.read(markerStateProvider).markers.keys.toSet();
    var name = _asString(args['name']);
    if (name == null || !_isMarkerName(name)) {
      name = _nextFreeMarker(inUse);
      if (name == null) {
        return AiToolResult.failure('All marker slots (a–z) are in use.');
      }
    }

    ref.read(markerStateProvider.notifier).setMarker(name, time);

    return AiToolResult.ok(
      <String, Object?>{'name': name, 'time': time},
      citations: <AiCoordinate>[AiCoordinate(time: time)],
    );
  },
);

// ── shared helpers ──────────────────────────────────────────────────────────────

/// Per-call caps for `getSelectionContext` to keep the structured summary
/// token-efficient regardless of how large the selection is.
const int _kMaxSelectionSignals = 32;
const int _kMaxSelectionTransactions = 64;

WaveformDataSource? _source(Ref ref) => ref.read(waveformSourceProvider).value;

/// Resolves a signal argument that may be either a [Variable.signalRef] or a
/// full hierarchical path.
Variable? _resolveVariable(Ref ref, String signal) {
  // Prefer the path-keyed map: paths are unique per hierarchy row, whereas
  // FST aliasing can map one signalRef onto many rows.
  final byPath = ref.read(signalVariablesByPathProvider)[signal];
  if (byPath != null) return byPath;
  return ref.read(signalVariablesMapProvider)[signal];
}

/// The signals a selection-context call applies to: an explicit list (resolved
/// from refs/paths) or the current tree selection.
List<Variable> _selectionSignals(Ref ref, Map<String, Object?> args) {
  final explicit = _asStringList(args['signals']);
  if (explicit != null && explicit.isNotEmpty) {
    return <Variable>[
      for (final s in explicit) ?_resolveVariable(ref, s),
    ];
  }
  // The tree selection is keyed by fullPath (row identity), so resolve
  // through the path-keyed map.
  final map = ref.read(signalVariablesByPathProvider);
  return <Variable>[
    for (final path in ref.read(selectedVariablesProvider)) ?map[path],
  ];
}

/// The tick window a selection-context call applies to: explicit args, else the
/// two-cursor measurement range, else the full loaded range.
(int, int) _selectionWindow(
  Ref ref,
  Map<String, Object?> args,
  WaveformDataSource source,
) {
  final argStart = _asInt(args['startTime']);
  final argEnd = _asInt(args['endTime']);
  if (argStart != null && argEnd != null) return _ordered(argStart, argEnd);

  final cursor = ref.read(cursorStateProvider);
  final primary = cursor.primaryCursorTime;
  final secondary = cursor.secondaryCursorTime;
  if (primary != null && secondary != null) return _ordered(primary, secondary);

  return (source.startTime, source.endTime);
}

/// Flattens every active decoder's transactions into a single list, optionally
/// filtered by decoder and overlap with `[windowStart, windowEnd]`, sorted by
/// (startTime, decoder instance id) for deterministic output.
List<(ActiveDecoder, DecodedTransaction)> _flattenTransactions(
  List<ActiveDecoder> decoders, {
  String? decoderFilter,
  int? windowStart,
  int? windowEnd,
}) {
  final flat = <(ActiveDecoder, DecodedTransaction)>[];
  for (final d in decoders) {
    if (decoderFilter != null &&
        d.id != decoderFilter &&
        d.decoderId != decoderFilter) {
      continue;
    }
    for (final tx in d.transactions) {
      if (windowStart != null && windowEnd != null) {
        final overlaps = tx.endTime >= windowStart && tx.startTime <= windowEnd;
        if (!overlaps) continue;
      }
      flat.add((d, tx));
    }
  }
  flat.sort((a, b) {
    final byTime = a.$2.startTime.compareTo(b.$2.startTime);
    return byTime != 0 ? byTime : a.$1.id.compareTo(b.$1.id);
  });
  return flat;
}

Map<String, Object?> _transactionMap(
  ActiveDecoder decoder,
  DecodedTransaction tx, {
  bool full = false,
}) => <String, Object?>{
  'decoderInstanceId': decoder.id,
  'decoderId': decoder.decoderId,
  'startTime': tx.startTime,
  'endTime': tx.endTime,
  'label': tx.label,
  if (full) 'fields': tx.fields,
  'isError': tx.isError,
  if (tx.errorMessage != null) 'errorMessage': tx.errorMessage,
};

(int, int) _ordered(int a, int b) => a <= b ? (a, b) : (b, a);

bool _containsX(String value) => value.toLowerCase().contains('x');

bool _isMarkerName(String name) =>
    name.length == 1 &&
    name.codeUnitAt(0) >= 0x61 &&
    name.codeUnitAt(0) <= 0x7a;

String? _nextFreeMarker(Set<String> inUse) {
  for (var c = 0x61; c <= 0x7a; c++) {
    final candidate = String.fromCharCode(c);
    if (!inUse.contains(candidate)) return candidate;
  }
  return null;
}

String? _asString(Object? value) => value is String ? value : null;

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String>? _asStringList(Object? value) {
  if (value is! List) return null;
  return <String>[
    for (final e in value)
      if (e is String) e,
  ];
}
