// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';
import 'package:wavecrux/services/rtl_source/stems_parser.dart';
import 'package:wavecrux/services/rtl_source/stems_writer.dart';

void main() {
  const writer = StemsWriter();
  const parser = StemsParser();

  StemsFile sample() => const StemsFile(
    entries: [
      StemsEntry(
        path: 'top',
        sourceFile: '/src/top.v',
        lineNumber: 2,
        kind: StemsEntryKind.scope,
      ),
      StemsEntry(
        path: 'top.clk',
        sourceFile: '/src/top.v',
        lineNumber: 3,
        kind: StemsEntryKind.variable,
      ),
      StemsEntry(
        path: 'top.cpu',
        sourceFile: '/src/cpu sub.v',
        lineNumber: 5,
        kind: StemsEntryKind.scope,
      ),
      StemsEntry(
        path: 'top.cpu.sum',
        sourceFile: '/src/cpu sub.v',
        lineNumber: 9,
        kind: StemsEntryKind.variable,
      ),
    ],
  );

  test('emits a comp file table referenced by index', () {
    final text = writer.write(sample());
    expect(text, contains('++ comp 0 file /src/top.v'));
    // A path with a space is quoted so it survives the tokenizer.
    expect(text, contains('++ comp 1 file "/src/cpu sub.v"'));
  });

  test('round-trips through StemsParser to equivalent entries', () {
    final original = sample();
    final reparsed = parser.parse(writer.write(original));

    expect(reparsed.entries, hasLength(original.entries.length));
    for (final entry in original.entries) {
      final hit = reparsed.lookup(entry.path);
      expect(hit, isNotNull, reason: 'missing ${entry.path}');
      expect(hit!.sourceFile, entry.sourceFile);
      expect(hit.lineNumber, entry.lineNumber);
      expect(hit.kind, entry.kind);
    }
  });

  test('an empty stems file still parses back to empty', () {
    final reparsed = parser.parse(writer.write(const StemsFile()));
    expect(reparsed.isEmpty, isTrue);
  });
}
