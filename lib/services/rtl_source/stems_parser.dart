// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';

/// Parses GTKWave-compatible RTL stems files into a [StemsFile].
///
/// Stems files are produced by Verilog/VHDL parser tools such as GTKWave's
/// `vermin` and `xml2stems`, and map signal/scope hierarchical paths to
/// source-file locations. The format is line-oriented ASCII; each meaningful
/// line begins with `++` (scope/module/file) or `+++` (variable inside the
/// most recent scope).
///
/// Supported line forms:
/// ```text
/// # comment
/// ++ comp <id> file <path>          file-table entry, may be quoted
/// ++ module <full.path> <fileRef> <line>
/// ++ scope  <full.path> <fileRef> <line>
/// ++ var    <full.path> <fileRef> <line>     # variable with full path
/// +++ var   <localName> <fileRef> <line>     # var in current scope
/// ```
///
/// `fileRef` is either:
/// - a non-negative integer that indexes into the `comp` file table, or
/// - an inline file path (any token that contains a `/`, `\`, `.`, or is
///   wrapped in quotes).
///
/// Unrecognised, malformed, or missing-data lines are skipped silently —
/// stems files from third-party tools commonly contain extra metadata, and
/// throwing on every unknown directive would make adoption painful.
class StemsParser {
  const StemsParser();

  /// Parses [content] into a [StemsFile].
  StemsFile parse(String content) {
    final fileTable = <int, String>{};
    final entries = <StemsEntry>[];
    String? currentScopePath;

    for (final rawLine in content.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#') || line.startsWith('//')) continue;

      // `+++` first (longer prefix wins).
      final isVar = line.startsWith('+++');
      final isScope = !isVar && line.startsWith('++');
      if (!isVar && !isScope) continue;
      line = line.substring(isVar ? 3 : 2).trim();
      if (line.isEmpty) continue;

      final tokens = _tokenize(line);
      if (tokens.isEmpty) continue;

      final keyword = tokens[0].toLowerCase();

      // ── file table: `comp <id> file <path>` ──────────────────────────────
      if (keyword == 'comp' &&
          tokens.length >= 4 &&
          tokens[2].toLowerCase() == 'file') {
        final id = int.tryParse(tokens[1]);
        if (id == null) continue;
        // Everything after `file` is the path; rejoin tokens[3..] verbatim.
        // _tokenize preserves quoted strings as a single token.
        final path = tokens.sublist(3).join(' ');
        if (path.isEmpty) continue;
        fileTable[id] = _unquote(path);
        continue;
      }

      // ── module / scope ──────────────────────────────────────────────────
      if (!isVar && (keyword == 'module' || keyword == 'scope')) {
        final entry = _decodeLocation(
          tokens: tokens,
          fileTable: fileTable,
          kind: StemsEntryKind.scope,
        );
        if (entry == null) continue;
        entries.add(entry);
        currentScopePath = entry.path;
        continue;
      }

      // ── variable ────────────────────────────────────────────────────────
      if (keyword == 'var') {
        final entry = _decodeVariable(
          tokens: tokens,
          fileTable: fileTable,
          currentScopePath: currentScopePath,
          isNested: isVar,
        );
        if (entry == null) continue;
        entries.add(entry);
        continue;
      }

      // Other keywords (e.g. `param`, `arch`, vendor extensions) are ignored.
    }

    return StemsFile(entries: entries);
  }

  // ── decoders ───────────────────────────────────────────────────────────────

  StemsEntry? _decodeLocation({
    required List<String> tokens,
    required Map<int, String> fileTable,
    required StemsEntryKind kind,
  }) {
    // Expected: `module <path> <fileRef> <line>` or `scope <path> <fileRef> <line>`.
    if (tokens.length < 4) return null;
    final path = _unquote(tokens[1]);
    if (path.isEmpty) return null;
    final fileRef = tokens[tokens.length - 2];
    final lineToken = tokens[tokens.length - 1];
    final lineNumber = int.tryParse(lineToken);
    if (lineNumber == null || lineNumber < 1) return null;
    final source = _resolveFileRef(fileRef, fileTable);
    if (source == null || source.isEmpty) return null;
    return StemsEntry(
      path: path,
      sourceFile: source,
      lineNumber: lineNumber,
      kind: kind,
    );
  }

  StemsEntry? _decodeVariable({
    required List<String> tokens,
    required Map<int, String> fileTable,
    required String? currentScopePath,
    required bool isNested,
  }) {
    // `var <name_or_path> <fileRef> <line>`.
    if (tokens.length < 4) return null;
    final nameOrPath = _unquote(tokens[1]);
    if (nameOrPath.isEmpty) return null;
    final lineNumber = int.tryParse(tokens[tokens.length - 1]);
    if (lineNumber == null || lineNumber < 1) return null;
    final source = _resolveFileRef(tokens[tokens.length - 2], fileTable);
    if (source == null || source.isEmpty) return null;

    // `+++` form: name is local to the current scope. Prepend scope path.
    final fullPath = isNested && currentScopePath != null
        ? '$currentScopePath.$nameOrPath'
        : nameOrPath;
    return StemsEntry(
      path: fullPath,
      sourceFile: source,
      lineNumber: lineNumber,
      kind: StemsEntryKind.variable,
    );
  }

  String? _resolveFileRef(String token, Map<int, String> fileTable) {
    final id = int.tryParse(token);
    if (id != null) return fileTable[id];
    return _unquote(token);
  }

  // Splits a stems-line body into whitespace-separated tokens, treating
  // double-quoted runs as a single token (paths may contain spaces).
  List<String> _tokenize(String line) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        buffer.write(ch);
        continue;
      }
      if (!inQuotes && (ch == ' ' || ch == '\t')) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(ch);
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }

  String _unquote(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}
