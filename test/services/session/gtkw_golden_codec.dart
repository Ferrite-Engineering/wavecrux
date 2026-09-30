// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shared, deterministic JSON codec for GTKWave `.gtkw` golden snapshots.
//
// This file is the single source of truth for how a parsed [GtkwFile] and an
// imported [GtkwImportResult] are serialized to a stable, diffable JSON form.
// It is imported by BOTH the fixture generator (`tool/generate_gtkw_fixtures.dart`)
// and the golden test (`test/services/session/gtkw_golden_test.dart`) so the
// two can never drift: the generator writes the canonical JSON, and the test
// re-encodes the live parse/import output with the same functions and diffs it
// against the committed file.
//
// Why a bespoke codec and not `SessionService._toJson`:
//   - `SessionService` assigns a fresh UUID v4 to every signal entry, which is
//     non-deterministic — useless for a committed golden. This codec omits the
//     id and keeps only the semantically meaningful fields.
//   - The golden is the gtkw analog of a decoder's `.expected_transactions.json`:
//     it locks the full parse→import pipeline output against regression.
//
// Framework-free on purpose (no flutter_test import) so `dart run` can use it
// from a `tool/` script.

import 'dart:convert';

import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/session/gtkw_import_service.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

/// Canonical pretty-printed JSON (2-space indent, trailing newline) for a
/// golden map. Used by the generator when writing snapshot files so committed
/// goldens are human-diffable.
String encodeGolden(Map<String, Object?> map) =>
    '${const JsonEncoder.withIndent('  ').convert(map)}\n';

// ── Parse golden (GtkwFile) ───────────────────────────────────────────────────

/// Serializes the raw parser output [file] to a deterministic map.
///
/// This is the universal, VCD-independent contract — it pins exactly what the
/// parser extracts from a `.gtkw` file (directives, formats, colors, groups,
/// markers, paths) without needing the referenced waveform. Every fixture in
/// `generated/` and `captured/` carries an `.expected_parse.json` of this shape.
Map<String, Object?> encodeGtkwFile(GtkwFile file) => {
  'dumpFilePath': file.dumpFilePath,
  'timeStart': file.timeStart,
  'zoomFactor': file.zoomFactor,
  'primaryMarker': file.primaryMarker,
  'canvasBackgroundHex': file.canvasBackgroundHex,
  'openScopes': file.openScopes,
  'namedMarkers': _sortedMarkers(file.namedMarkers),
  'entries': file.entries.map(_encodeEntry).toList(),
};

Map<String, Object?> _encodeEntry(GtkwEntry entry) {
  switch (entry) {
    case GtkwSignalEntry():
      return {
        'type': 'signal',
        'path': entry.path,
        'format': entry.format.name,
        'colorArgb': entry.colorArgb,
        'translateFilterPath': entry.translateFilterPath,
        'renderAsAnalog': entry.renderAsAnalog,
        'analogInterpolation': entry.analogInterpolation.name,
      };
    case GtkwGroupBeginEntry():
      return {'type': 'groupBegin', 'name': entry.name};
    case GtkwGroupEndEntry():
      return {'type': 'groupEnd', 'name': entry.name};
    case GtkwSeparatorEntry():
      return {'type': 'separator'};
    case GtkwCommentEntry():
      return {'type': 'comment', 'text': entry.text};
  }
}

// ── Import golden (GtkwImportResult) ──────────────────────────────────────────

/// Serializes the full parse→import pipeline output [result] to a deterministic
/// map. Random per-entry UUIDs are intentionally omitted.
///
/// Only fixtures with a known paired variable set (the `generated/` tier, paired
/// with `fixture.vcd` via [fixtureVcdVariables]) carry an `.expected_session.json`
/// of this shape — captured fixtures reference dumpfiles we do not commit.
Map<String, Object?> encodeImportResult(GtkwImportResult result) => {
  'matchedSignalCount': result.matchedSignalCount,
  'groupCount': result.groupCount,
  'markerCount': result.markerCount,
  'unmatchedSignalPaths': result.unmatchedSignalPaths,
  'canvasBackgroundHex': result.canvasBackgroundHex,
  'sourceFilePath': result.sessionState.sourceFilePath,
  'panOffsetTicks': result.sessionState.panOffsetTicks,
  'primaryCursorTime': result.sessionState.cursorState.primaryCursorTime,
  'markers': _sortedMarkers(result.sessionState.markerState.markers),
  'signals': result.sessionState.signalGroup.entries
      .map(_encodeSignalEntry)
      .toList(),
};

Map<String, Object?> _encodeSignalEntry(SignalEntry entry) {
  switch (entry.kind) {
    case SignalEntryKind.signal:
      return {
        'kind': 'signal',
        'signalRef': entry.signalRef,
        'displayName': entry.displayName,
        'signalPath': entry.signalPath,
        'format': entry.format.name,
        'argbColor': entry.argbColor,
        'renderAsAnalog': entry.renderAsAnalog,
      };
    case SignalEntryKind.group:
      return {
        'kind': 'group',
        'groupName': entry.groupName,
        'children': entry.children.map(_encodeSignalEntry).toList(),
      };
    case SignalEntryKind.separator:
      return {'kind': 'separator'};
    case SignalEntryKind.comment:
      return {'kind': 'comment', 'text': entry.text};
  }
}

// ── Fixture variable set ──────────────────────────────────────────────────────

/// The flat variable list contained in `generated/fixture.vcd`, hand-declared
/// so the import golden can be computed without invoking the native wellen
/// parser. Must match `fixture.vcd`'s `$var` declarations exactly:
///
///   top.clk, top.rst, top.data, top.cpu.addr, top.cpu.dout
List<Variable> fixtureVcdVariables() => const [
  Variable(
    name: 'clk',
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: 'top.clk',
    scopePath: 'top',
    bitWidth: 1,
  ),
  Variable(
    name: 'rst',
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: 'top.rst',
    scopePath: 'top',
    bitWidth: 1,
  ),
  Variable(
    name: 'data',
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: 'top.data',
    scopePath: 'top',
    bitWidth: 8,
  ),
  Variable(
    name: 'addr',
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: 'top.cpu.addr',
    scopePath: 'top.cpu',
    bitWidth: 16,
  ),
  Variable(
    name: 'dout',
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: 'top.cpu.dout',
    scopePath: 'top.cpu',
    bitWidth: 8,
  ),
];

/// Markers serialized in deterministic (alphabetical) key order.
Map<String, int> _sortedMarkers(Map<String, int> markers) {
  final keys = markers.keys.toList()..sort();
  return {for (final k in keys) k: markers[k]!};
}
