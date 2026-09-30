// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// What kind of HDL element a stems entry refers to.
enum StemsEntryKind {
  /// A scope (module/architecture/process) declaration site.
  scope,

  /// A variable (signal/wire/reg/port) declaration site.
  variable,
}

/// A single signal-or-scope → source-location mapping parsed from a
/// GTKWave-compatible stems file (produced by `xml2stems` for Verilog
/// and by `vermin` / similar tools for VHDL).
///
/// The full hierarchical [path] (e.g. `"top.cpu.clk"`) is matched against the
/// signals loaded from the waveform; on a match, the user can jump straight
/// to the [sourceFile]:[lineNumber] location in the RTL source view.
@immutable
class StemsEntry {
  const StemsEntry({
    required this.path,
    required this.sourceFile,
    required this.lineNumber,
    required this.kind,
  });

  /// Full hierarchical path, dot-separated, of the variable or scope this
  /// entry refers to (e.g. `"top.cpu.clk"`). For scope entries this is the
  /// scope's own path (e.g. `"top.cpu"`).
  final String path;

  /// Absolute or relative path of the source file containing the declaration.
  final String sourceFile;

  /// 1-based line number in [sourceFile] of the declaration.
  final int lineNumber;

  /// Whether this entry refers to a variable or to its enclosing scope.
  final StemsEntryKind kind;

  // ── copyWith ───────────────────────────────────────────────────────────────

  StemsEntry copyWith({
    String? path,
    String? sourceFile,
    int? lineNumber,
    StemsEntryKind? kind,
  }) => StemsEntry(
    path: path ?? this.path,
    sourceFile: sourceFile ?? this.sourceFile,
    lineNumber: lineNumber ?? this.lineNumber,
    kind: kind ?? this.kind,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StemsEntry &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          sourceFile == other.sourceFile &&
          lineNumber == other.lineNumber &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(path, sourceFile, lineNumber, kind);

  @override
  String toString() => 'StemsEntry($kind $path → $sourceFile:$lineNumber)';
}
