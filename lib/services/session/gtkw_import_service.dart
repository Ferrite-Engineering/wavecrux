// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

// ── GtkwImportResult ──────────────────────────────────────────────────────────

/// The outcome of a GTKWave `.gtkw` session import.
@immutable
class GtkwImportResult {
  const GtkwImportResult({
    required this.sessionState,
    required this.matchedSignalCount,
    required this.groupCount,
    required this.markerCount,
    required this.unmatchedSignalPaths,
    this.canvasBackgroundHex,
  });

  /// The WaveCrux [SessionState] constructed from the `.gtkw` file.
  final SessionState sessionState;

  /// Number of signal paths from the `.gtkw` that were matched to a variable
  /// in the loaded waveform file.
  final int matchedSignalCount;

  /// Number of named groups imported.
  final int groupCount;

  /// Number of named markers (a–z) imported.
  final int markerCount;

  /// Signal paths from the `.gtkw` that could not be resolved to any variable
  /// in the waveform file. These entries are omitted from [sessionState].
  final List<String> unmatchedSignalPaths;

  /// Canvas background color from a `[bgcolor]` directive in the `.gtkw` file,
  /// as a `#RRGGBB` hex string, or null if absent. Callers should apply this
  /// as `AppSettings.themeOverrides['canvas.background']`.
  final String? canvasBackgroundHex;

  /// `true` when at least one signal path could not be resolved.
  bool get hasUnmatchedSignals => unmatchedSignalPaths.isNotEmpty;

  @override
  String toString() =>
      'GtkwImportResult('
      'matched: $matchedSignalCount, '
      'groups: $groupCount, '
      'markers: $markerCount, '
      'unmatched: ${unmatchedSignalPaths.length})';
}

// ── GtkwImportService ─────────────────────────────────────────────────────────

/// Converts a parsed [GtkwFile] into a WaveCrux [SessionState].
///
/// Signal path matching is performed against the flat [Variable] list derived
/// from the waveform's scope hierarchy. Matching proceeds in priority order:
///
/// 1. **Exact full-path match** — the `.gtkw` path (with any bit-range suffix
///    stripped) equals `variable.fullPath`.
/// 2. **Case-insensitive full-path match** — same comparison, ignoring case.
/// 3. **Name-only suffix match** — the last dot-separated component of the
///    `.gtkw` path equals `variable.name` (case-insensitive). Used when the
///    `.gtkw` file was saved with a different top-level scope prefix.
///
/// Groups are assembled recursively from [GtkwGroupBeginEntry] /
/// [GtkwGroupEndEntry] pairs. Unmatched signals are recorded in
/// [GtkwImportResult.unmatchedSignalPaths] and excluded from the session.
class GtkwImportService {
  const GtkwImportService();

  /// Imports [gtkwFile] into a [SessionState].
  ///
  /// [variables] must be the flat list of all [Variable] instances from the
  /// currently loaded waveform file. Pass an empty list when no file is open.
  ///
  /// [sourceFilePath] overrides the path stored in the `.gtkw` `[dumpfile]`
  /// directive. Pass the path of the currently loaded waveform so the resulting
  /// session references the correct file.
  GtkwImportResult importSession(
    GtkwFile gtkwFile,
    List<Variable> variables, {
    String? sourceFilePath,
  }) {
    // Build lookup maps keyed by the variable's full hierarchical path.
    final exactLookup = <String, Variable>{};
    final lowerLookup = <String, Variable>{};
    final nameLookup = <String, Variable>{}; // last-component-only fallback

    for (final v in variables) {
      final path = v.fullPath;
      exactLookup[path] = v;
      lowerLookup[path.toLowerCase()] = v;
      // Name-only lookup: keep last writer (arbitrary but deterministic).
      nameLookup[v.name.toLowerCase()] = v;
    }

    final unmatchedPaths = <String>[];
    var groupCount = 0;

    // Assemble the nested SignalGroup from the flat GtkwEntry list.
    final cursor = _Cursor(gtkwFile.entries);
    final topLevelEntries = _buildLevel(
      cursor,
      exactLookup,
      lowerLookup,
      nameLookup,
      unmatchedPaths,
      groupCounter: (n) => groupCount += n,
    );

    // Build MarkerState from the named markers in the .gtkw file.
    var markerState = const MarkerState();
    for (final entry in gtkwFile.namedMarkers.entries) {
      markerState = markerState.setMarker(entry.key, entry.value);
    }

    // GTKWave's primary marker is its cursor, so it lands on WaveCrux's
    // primary cursor rather than among the named markers.
    final cursorState = CursorState(primaryCursorTime: gtkwFile.primaryMarker);

    // Pan offset from [timestart]; zoom left at default so viewer fits all.
    final panOffsetTicks = (gtkwFile.timeStart ?? 0).toDouble();

    final sessionState = SessionState(
      sourceFilePath: sourceFilePath ?? gtkwFile.dumpFilePath,
      signalGroup: SignalGroup(entries: topLevelEntries),
      cursorState: cursorState,
      markerState: markerState,
      panOffsetTicks: panOffsetTicks,
    );

    return GtkwImportResult(
      sessionState: sessionState,
      matchedSignalCount: _countSignals(topLevelEntries),
      groupCount: groupCount,
      markerCount: gtkwFile.namedMarkers.length,
      unmatchedSignalPaths: List.unmodifiable(unmatchedPaths),
      canvasBackgroundHex: gtkwFile.canvasBackgroundHex,
    );
  }

  // ── Tree assembly ─────────────────────────────────────────────────────────

  /// Recursively builds [SignalEntry] rows until the cursor is exhausted or a
  /// [GtkwGroupEndEntry] is encountered (which closes the current group).
  List<SignalEntry> _buildLevel(
    _Cursor cursor,
    Map<String, Variable> exactLookup,
    Map<String, Variable> lowerLookup,
    Map<String, Variable> nameLookup,
    List<String> unmatchedPaths, {
    required void Function(int) groupCounter,
  }) {
    final result = <SignalEntry>[];

    while (cursor.hasMore) {
      final entry = cursor.consume();

      switch (entry) {
        case GtkwSignalEntry():
          final variable = _resolveSignal(
            entry.path,
            exactLookup,
            lowerLookup,
            nameLookup,
          );
          if (variable != null) {
            result.add(
              SignalEntry.signal(
                signalRef: variable.signalRef,
                signalPath: variable.fullPath,
                displayName: variable.name,
                argbColor: entry.colorArgb,
                format: entry.format,
                renderAsAnalog: entry.renderAsAnalog,
              ),
            );
          } else {
            unmatchedPaths.add(entry.path);
          }

        case GtkwGroupBeginEntry(:final name):
          groupCounter(1);
          final children = _buildLevel(
            cursor,
            exactLookup,
            lowerLookup,
            nameLookup,
            unmatchedPaths,
            groupCounter: groupCounter,
          );
          result.add(
            SignalEntry.group(
              groupName: name,
              children: children,
            ),
          );

        case GtkwGroupEndEntry():
          // End of the current group level — return to the caller.
          return result;

        case GtkwSeparatorEntry():
          result.add(const SignalEntry.separator());

        case GtkwCommentEntry(:final text):
          result.add(SignalEntry.comment(text: text));
      }
    }

    return result;
  }

  // ── Signal matching ───────────────────────────────────────────────────────

  /// Resolves a GTKWave signal path to a [Variable] using a three-tier lookup.
  Variable? _resolveSignal(
    String gtkwPath,
    Map<String, Variable> exactLookup,
    Map<String, Variable> lowerLookup,
    Map<String, Variable> nameLookup,
  ) {
    // Strip bit-range suffix: `top.data[7:0]` → `top.data`.
    final normalised = _stripBitRange(gtkwPath);

    // 1. Exact match.
    final exact = exactLookup[normalised];
    if (exact != null) return exact;

    // 2. Case-insensitive full-path match.
    final lower = lowerLookup[normalised.toLowerCase()];
    if (lower != null) return lower;

    // 3. Name-only suffix match (last dot-component).
    final lastDot = normalised.lastIndexOf('.');
    if (lastDot >= 0) {
      final nameOnly = normalised.substring(lastDot + 1).toLowerCase();
      final nameMatch = nameLookup[nameOnly];
      if (nameMatch != null) return nameMatch;
    }

    return null;
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Strips a trailing bit-range like `[7:0]` or `[0]` from a path.
  static String _stripBitRange(String path) {
    final bracketIdx = path.indexOf('[');
    return bracketIdx >= 0 ? path.substring(0, bracketIdx) : path;
  }

  /// Recursively counts [SignalEntryKind.signal] rows in [entries].
  static int _countSignals(List<SignalEntry> entries) {
    var count = 0;
    for (final e in entries) {
      if (e.kind == SignalEntryKind.signal) {
        count++;
      } else if (e.kind == SignalEntryKind.group) {
        count += _countSignals(e.children);
      }
    }
    return count;
  }
}

// ── _Cursor ───────────────────────────────────────────────────────────────────

/// Mutable index into a flat [GtkwEntry] list for recursive tree assembly.
class _Cursor {
  _Cursor(this._entries);

  final List<GtkwEntry> _entries;
  int _index = 0;

  bool get hasMore => _index < _entries.length;

  /// Returns the current entry and advances the index.
  GtkwEntry consume() => _entries[_index++];
}
