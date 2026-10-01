// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

// ── GtkwFilterIssue ───────────────────────────────────────────────────────────

/// Which kind of GTKWave filter a [GtkwFilterIssue] is about.
enum GtkwFilterIssueKind {
  /// A translate filter file (`^n`) that was not found on this machine.
  missingFile,

  /// A filter process (`^>n`). Not imported: WaveCrux does not start a
  /// program named by an imported save file.
  process,

  /// A transaction filter process (`^<n`). Not imported, for the same reason.
  transaction,
}

/// A filter named by the `.gtkw` that the import did not apply.
@immutable
class GtkwFilterIssue {
  const GtkwFilterIssue({
    required this.signalPath,
    required this.filterPath,
    required this.kind,
  });

  /// The trace's path as the `.gtkw` wrote it.
  final String signalPath;

  /// The filter path as the `.gtkw` wrote it.
  final String filterPath;

  final GtkwFilterIssueKind kind;

  @override
  bool operator ==(Object other) =>
      other is GtkwFilterIssue &&
      other.signalPath == signalPath &&
      other.filterPath == filterPath &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(signalPath, filterPath, kind);

  @override
  String toString() => 'GtkwFilterIssue($signalPath, $filterPath, $kind)';
}

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
    this.filterIssues = const [],
    this.ticksPerPixel,
    this.panOffsetTicks,
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

  /// Filters the `.gtkw` names for matched signals that were not applied: a
  /// translate filter file that could not be found, or a filter process.
  final List<GtkwFilterIssue> filterIssues;

  /// The zoom GTKWave had, as WaveCrux ticks per pixel, or null when the
  /// `.gtkw` has no zoom. Also stored on [sessionState]; kept separately so
  /// callers can tell "absent" from the session default.
  final double? ticksPerPixel;

  /// The time at the left edge of GTKWave's view (`[timestart]`), or null
  /// when the `.gtkw` has none. Also stored on [sessionState].
  final double? panOffsetTicks;

  /// Canvas background color from a `[bgcolor]` directive in the `.gtkw` file,
  /// as a `#RRGGBB` hex string, or null if absent. Reported only: the import
  /// does not change the canvas background, which the WaveCrux theme owns.
  final String? canvasBackgroundHex;

  /// `true` when at least one signal path could not be resolved.
  bool get hasUnmatchedSignals => unmatchedSignalPaths.isNotEmpty;

  /// `true` when at least one named filter was not applied.
  bool get hasFilterIssues => filterIssues.isNotEmpty;

  @override
  String toString() =>
      'GtkwImportResult('
      'matched: $matchedSignalCount, '
      'groups: $groupCount, '
      'markers: $markerCount, '
      'unmatched: ${unmatchedSignalPaths.length}, '
      'filterIssues: ${filterIssues.length})';
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
///
/// Beyond the trace list, the session carries the translate filter file of
/// each matched trace ([SessionState.translateFilterPaths], keyed by signal
/// ref), the zoom ([SessionState.ticksPerPixel]), the left-edge time
/// ([SessionState.panOffsetTicks]) and the expanded scopes
/// ([SessionState.expandedScopePaths]).
///
/// ### Time units
///
/// GTKWave's markers, `[timestart]` and zoom are in its internal time unit.
/// They are taken here as ticks of the loaded dump, the same reading the
/// markers have always had.
///
/// ### Zoom
///
/// GTKWave stores a zoom exponent `z` (`*z …`). Its `calczoom`
/// (`wavewindow.c`) turns it into `zoombase^-z` time units per 200-pixel
/// frame, never less than one unit, with `zoombase` defaulting to 2. So
/// ticks per pixel = `max(2^-z, 1) / 200`. The viewer clamps the result to
/// the range the loaded dump allows, so a zoom wider than the dump lands on
/// fit-all.
class GtkwImportService {
  const GtkwImportService();

  /// GTKWave's default `zoombase` (its `.gtkwaverc` can change it).
  static const double gtkwaveZoomBase = 2;

  /// GTKWave's `pixelsperframe`.
  static const double gtkwavePixelsPerFrame = 200;

  /// Converts a GTKWave zoom exponent to ticks per pixel.
  static double ticksPerPixelForZoom(double zoom) =>
      math.max(math.pow(gtkwaveZoomBase, -zoom).toDouble(), 1) /
      gtkwavePixelsPerFrame;

  /// Imports [gtkwFile] into a [SessionState].
  ///
  /// [variables] must be the flat list of all [Variable] instances from the
  /// currently loaded waveform file. Pass an empty list when no file is open.
  ///
  /// [sourceFilePath] overrides the path stored in the `.gtkw` `[dumpfile]`
  /// directive. Pass the path of the currently loaded waveform so the resulting
  /// session references the correct file.
  ///
  /// [gtkwFilePath] is where the `.gtkw` was read from, and [fileExists] tells
  /// whether a path names a readable file. Both are needed to resolve
  /// translate filter files (see [resolveFilterPath]); without [fileExists]
  /// every filter is reported missing.
  GtkwImportResult importSession(
    GtkwFile gtkwFile,
    List<Variable> variables, {
    String? sourceFilePath,
    String? gtkwFilePath,
    bool Function(String path)? fileExists,
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
    final filterPaths = <String, String>{};
    final filterIssues = <GtkwFilterIssue>[];
    final dumpPath = sourceFilePath ?? gtkwFile.dumpFilePath;

    void collectFilters(GtkwSignalEntry entry, Variable variable) {
      final file = entry.translateFilterPath;
      if (file != null) {
        final resolved = resolveFilterPath(
          file,
          gtkwFilePath: gtkwFilePath,
          savedFilePath: gtkwFile.savedFilePath,
          dumpFilePath: dumpPath,
          fileExists: fileExists ?? _noFileExists,
        );
        if (resolved != null) {
          filterPaths[variable.signalRef] = resolved;
        } else {
          filterIssues.add(
            GtkwFilterIssue(
              signalPath: entry.path,
              filterPath: file,
              kind: GtkwFilterIssueKind.missingFile,
            ),
          );
        }
      }
      final process = entry.processFilterPath;
      if (process != null) {
        filterIssues.add(
          GtkwFilterIssue(
            signalPath: entry.path,
            filterPath: process,
            kind: GtkwFilterIssueKind.process,
          ),
        );
      }
      final transaction = entry.transactionFilterPath;
      if (transaction != null) {
        filterIssues.add(
          GtkwFilterIssue(
            signalPath: entry.path,
            filterPath: transaction,
            kind: GtkwFilterIssueKind.transaction,
          ),
        );
      }
    }

    // Assemble the nested SignalGroup from the flat GtkwEntry list.
    final cursor = _Cursor(gtkwFile.entries);
    final topLevelEntries = _buildLevel(
      cursor,
      exactLookup,
      lowerLookup,
      nameLookup,
      unmatchedPaths,
      groupCounter: (n) => groupCount += n,
      onMatched: collectFilters,
    );

    // Build MarkerState from the named markers in the .gtkw file.
    var markerState = const MarkerState();
    for (final entry in gtkwFile.namedMarkers.entries) {
      markerState = markerState.setMarker(entry.key, entry.value);
    }

    // GTKWave's primary marker is its cursor, so it lands on WaveCrux's
    // primary cursor rather than among the named markers.
    final cursorState = CursorState(primaryCursorTime: gtkwFile.primaryMarker);

    final zoom = gtkwFile.zoomFactor;
    final ticksPerPixel = zoom == null || !zoom.isFinite
        ? null
        : ticksPerPixelForZoom(zoom);
    final panOffsetTicks = gtkwFile.timeStart?.toDouble();

    final sessionState = SessionState(
      sourceFilePath: dumpPath,
      signalGroup: SignalGroup(entries: topLevelEntries),
      cursorState: cursorState,
      markerState: markerState,
      ticksPerPixel: ticksPerPixel ?? 1.0,
      panOffsetTicks: panOffsetTicks ?? 0.0,
      expandedScopePaths: _resolveOpenScopes(gtkwFile.openScopes, variables),
      translateFilterPaths: Map.unmodifiable(filterPaths),
    );

    return GtkwImportResult(
      sessionState: sessionState,
      matchedSignalCount: _countSignals(topLevelEntries),
      groupCount: groupCount,
      markerCount: gtkwFile.namedMarkers.length,
      unmatchedSignalPaths: List.unmodifiable(unmatchedPaths),
      filterIssues: List.unmodifiable(filterIssues),
      ticksPerPixel: ticksPerPixel,
      panOffsetTicks: panOffsetTicks,
      canvasBackgroundHex: gtkwFile.canvasBackgroundHex,
    );
  }

  // ── Filter paths ──────────────────────────────────────────────────────────

  /// Finds the translate filter file a `.gtkw` names as [writtenPath], or
  /// returns null when no candidate exists.
  ///
  /// GTKWave writes the filter's absolute path on the machine that saved the
  /// file. Candidates are tried in this order, and the first for which
  /// [fileExists] is true wins:
  ///
  /// 1. Re-anchored beside this save file: the path relative to the directory
  ///    of the original save ([savedFilePath], from `[savefile]`), joined to
  ///    the directory of [gtkwFilePath]. This is GTKWave's own rule
  ///    (`get_relative_adjusted_name`), and it finds filters in a project
  ///    that was moved or checked out somewhere else.
  /// 2. A relative [writtenPath] against the save file's directory, then the
  ///    dump's.
  /// 3. [writtenPath] itself, when absolute.
  /// 4. The file name alone, beside the save file, then beside the dump.
  static String? resolveFilterPath(
    String writtenPath, {
    required bool Function(String path) fileExists,
    String? gtkwFilePath,
    String? savedFilePath,
    String? dumpFilePath,
  }) {
    // Every path here is read in its own style rather than this platform's:
    // the written ones come from whichever machine saved the file, and the
    // local ones are joined the way they were spelled.
    final written = _pathContextFor(writtenPath);
    final isAbsolute = written.isAbsolute(writtenPath);
    final name = written.basename(writtenPath);

    final candidates = <String>[
      if (gtkwFilePath != null) ...[
        if (isAbsolute && savedFilePath != null)
          ?_reanchor(writtenPath, savedFilePath, gtkwFilePath),
        if (!isAbsolute) _sibling(gtkwFilePath, [writtenPath]),
      ],
      if (dumpFilePath != null && !isAbsolute)
        _sibling(dumpFilePath, [writtenPath]),
      if (isAbsolute) writtenPath,
      if (gtkwFilePath != null) _sibling(gtkwFilePath, [name]),
      if (dumpFilePath != null) _sibling(dumpFilePath, [name]),
    ];
    for (final candidate in candidates) {
      if (fileExists(candidate)) return candidate;
    }
    return null;
  }

  /// [parts] joined onto the directory holding [file], in [file]'s style.
  static String _sibling(String file, List<String> parts) {
    final ctx = _pathContextFor(file);
    return ctx.normalize(ctx.joinAll([ctx.dirname(file), ...parts]));
  }

  /// [writtenPath] relative to the directory of [savedFilePath], joined to
  /// the directory of [gtkwFilePath]. Null when the two recorded paths share
  /// no root.
  static String? _reanchor(
    String writtenPath,
    String savedFilePath,
    String gtkwFilePath,
  ) {
    final ctx = _pathContextFor(writtenPath);
    if (_pathContextFor(savedFilePath).style != ctx.style) return null;
    if (!ctx.isAbsolute(savedFilePath)) return null;
    if (ctx.rootPrefix(writtenPath) != ctx.rootPrefix(savedFilePath)) {
      return null;
    }
    final relative = ctx.relative(
      writtenPath,
      from: ctx.dirname(savedFilePath),
    );
    return _sibling(gtkwFilePath, ctx.split(relative));
  }

  /// The path style a recorded path was written in: Windows when it has a
  /// drive letter or a backslash, POSIX otherwise.
  static p.Context _pathContextFor(String path) =>
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.contains(r'\')
      ? p.windows
      : p.posix;

  static bool _noFileExists(String _) => false;

  // ── Expanded scopes ───────────────────────────────────────────────────────

  /// Maps GTKWave's `[treeopen]` scopes onto the loaded dump's scope paths.
  ///
  /// GTKWave writes each open scope with a trailing `.` (`top.cpu.`). The
  /// match is exact first, then case-insensitive; a scope the dump does not
  /// have is dropped, since there is nothing to expand.
  static Set<String> _resolveOpenScopes(
    List<String> openScopes,
    List<Variable> variables,
  ) {
    if (openScopes.isEmpty) return const <String>{};
    final known = <String>{};
    for (final v in variables) {
      var scope = v.scopePath;
      while (scope.isNotEmpty && known.add(scope)) {
        final dot = scope.lastIndexOf('.');
        scope = dot < 0 ? '' : scope.substring(0, dot);
      }
    }
    final byLower = {for (final s in known) s.toLowerCase(): s};
    final result = <String>{};
    for (final raw in openScopes) {
      var scope = raw.trim();
      while (scope.endsWith('.')) {
        scope = scope.substring(0, scope.length - 1);
      }
      if (scope.isEmpty) continue;
      final match = known.contains(scope)
          ? scope
          : byLower[scope.toLowerCase()];
      if (match != null) result.add(match);
    }
    return Set.unmodifiable(result);
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
    required void Function(GtkwSignalEntry entry, Variable variable) onMatched,
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
            onMatched(entry, variable);
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
            onMatched: onMatched,
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
