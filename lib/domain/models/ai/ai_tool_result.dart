// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A stable coordinate reference into the loaded waveform that a citation can
/// later resolve to — i.e. that the viewer can jump the cursor to or anchor a
/// marker on.
///
/// At least one field is non-null. A `(signalRef, time)` pair points at a
/// specific transition on a specific signal; a bare `time` points at a moment
/// (e.g. a decoded transaction's start); a bare `signalRef`/`signalPath` points
/// at a signal with no specific time.
///
/// This is the grounding primitive for the "ground everything, hallucinate
/// nothing" discipline: every substantive datum a tool returns carries the
/// coordinate the user can click to verify it.
@immutable
class AiCoordinate {
  const AiCoordinate({this.signalRef, this.signalPath, this.time});

  /// Opaque [Variable.signalRef] the coordinate refers to, if any.
  final String? signalRef;

  /// Full hierarchical signal path (`top.cpu.clk`), if any. Human-readable
  /// companion to [signalRef].
  final String? signalPath;

  /// Simulation tick the coordinate refers to, if any.
  final int? time;

  /// JSON-natural map, omitting null fields so the serialized form stays
  /// compact (token-efficient) when handed to a model.
  Map<String, Object?> toMap() => <String, Object?>{
    if (signalRef != null) 'signalRef': signalRef,
    if (signalPath != null) 'signalPath': signalPath,
    if (time != null) 'time': time,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiCoordinate &&
          signalRef == other.signalRef &&
          signalPath == other.signalPath &&
          time == other.time;

  @override
  int get hashCode => Object.hash(signalRef, signalPath, time);

  @override
  String toString() =>
      'AiCoordinate(signalRef: $signalRef, path: $signalPath, time: $time)';
}

/// The structured result of invoking an AI tool.
///
/// [data] is a JSON-natural map describing the result (the payload fed back to
/// the model). [citations] is the list of stable coordinates the data is
/// grounded in, so the rendering layer can turn each into a clickable,
/// cursor-jumping reference. A failure carries [isError] = `true` and an
/// [error] message and an empty payload — tools report expected failures (no
/// waveform loaded, unknown signal) as a value, never by throwing.
@immutable
class AiToolResult {
  const AiToolResult({
    required this.isError,
    required this.data,
    required this.citations,
    this.error,
  });

  /// Successful result with [data] and optional [citations].
  factory AiToolResult.ok(
    Map<String, Object?> data, {
    List<AiCoordinate> citations = const [],
  }) => AiToolResult(isError: false, data: data, citations: citations);

  /// Failed result carrying a human-readable [message] and an empty payload.
  factory AiToolResult.failure(String message) => AiToolResult(
    isError: true,
    data: const {},
    citations: const [],
    error: message,
  );

  /// Whether the invocation failed.
  final bool isError;

  /// JSON-natural result payload (empty on failure).
  final Map<String, Object?> data;

  /// Stable coordinates the [data] is grounded in.
  final List<AiCoordinate> citations;

  /// Human-readable failure message, or `null` on success.
  final String? error;

  /// JSON-natural map of the whole result (for handing back to the model).
  Map<String, Object?> toMap() => <String, Object?>{
    'ok': !isError,
    if (error != null) 'error': error,
    'data': data,
    if (citations.isNotEmpty)
      'citations': [for (final c in citations) c.toMap()],
  };

  @override
  String toString() =>
      'AiToolResult(${isError ? 'error: $error' : 'ok'}, '
      '${citations.length} citations)';
}
