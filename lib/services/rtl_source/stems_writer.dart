// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';

/// Serializes a [StemsFile] into the GTKWave-compatible stems text format that
/// [StemsParser] reads back. The inverse of `StemsParser.parse`.
///
/// Output shape (a file table followed by full-path scope/var entries):
/// ```text
/// # WaveCrux RTL stems — generated
/// ++ comp 0 file "/abs/cpu.v"
/// ++ scope top 0 12
/// ++ var   top.clk 0 14
/// ++ scope top.cpu 0 40
/// ++ var   top.cpu.sum 0 47
/// ```
///
/// Full hierarchical paths are always emitted (the `++ scope`/`++ var <path>`
/// form), never the scope-relative `+++ var <localName>` form — round-tripping
/// through full paths is unambiguous and order-independent. Source files are
/// de-duplicated into a `comp` table and referenced by index; paths are quoted
/// so spaces survive.
class StemsWriter {
  const StemsWriter({this.header = 'WaveCrux RTL stems — generated'});

  /// First-line `#` comment written to the file. Purely informational; the
  /// parser ignores `#` lines.
  final String header;

  /// Serializes [stems] to stems-file text.
  String write(StemsFile stems) {
    // Build a stable file table in first-appearance order.
    final fileIndex = <String, int>{};
    for (final entry in stems.entries) {
      fileIndex.putIfAbsent(entry.sourceFile, () => fileIndex.length);
    }

    final buffer = StringBuffer()
      ..writeln('# $header')
      ..writeln(
        '# ${fileIndex.length} file(s), ${stems.entries.length} entries',
      );

    final ordered = fileIndex.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final f in ordered) {
      buffer.writeln('++ comp ${f.value} file ${_quote(f.key)}');
    }

    for (final entry in stems.entries) {
      final keyword = entry.kind == StemsEntryKind.scope ? 'scope' : 'var';
      final ref = fileIndex[entry.sourceFile]!;
      buffer.writeln(
        '++ $keyword ${_quote(entry.path)} $ref ${entry.lineNumber}',
      );
    }

    return buffer.toString();
  }

  /// Quotes [s] when it contains whitespace or is empty so it survives the
  /// parser's whitespace tokenizer as a single token. Embedded quotes are
  /// dropped (paths legitimately never contain `"`).
  static String _quote(String s) {
    final cleaned = s.replaceAll('"', '');
    final needsQuote = cleaned.isEmpty || RegExp(r'\s').hasMatch(cleaned);
    return needsQuote ? '"$cleaned"' : cleaned;
  }
}
