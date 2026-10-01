// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Golden-snapshot tests for the GTKWave `.gtkw` session-import corpus.
//
// This is the gtkw analog of the decoders' `.expected_transactions.json`
// regression suite. It is fully filesystem-driven — adding a fixture + its
// committed golden(s) under test/fixtures/gtkw/{generated,captured}/ extends
// coverage with no edit to this file.
//
// Two tiers:
//
//   generated/  Every `.gtkw` is checked against BOTH a `.expected_parse.json`
//               (raw parser output) and a `.expected_session.json` (the full
//               parse→import pipeline run against fixture.vcd's variable set).
//
//   captured/   Real GTKWave saves from public open-source projects. Each is
//               checked against its `.expected_parse.json` (we do not commit
//               the referenced dumpfiles, so the import tier does not apply),
//               and asserted to parse without throwing into a non-empty
//               structure. This is the regression lock proving a messy,
//               real-world `.gtkw` — full of directives WaveCrux does not model
//               ([size], [pos], [sst_*], [pattern_trace], …) — still imports.
//
// Regenerate goldens with:  dart run tool/generate_gtkw_fixtures.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/session/gtkw_import_service.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

import 'gtkw_golden_codec.dart';

const _generatedDir = 'test/fixtures/gtkw/generated';
const _capturedDir = 'test/fixtures/gtkw/captured';
const _parser = GtkwParser();
const _importService = GtkwImportService();

void main() {
  group('GTKWave generated corpus goldens', () {
    final fixtures = _gtkwFiles(_generatedDir);

    test('corpus is non-empty', () => expect(fixtures, isNotEmpty));

    for (final fixture in fixtures) {
      final name = p.basename(fixture.path);
      final base = fixture.path.replaceFirst(RegExp(r'\.gtkw$'), '');

      test('$name — parse matches .expected_parse.json', () {
        final parsed = _parser.parse(fixture.readAsStringSync());
        _expectGolden(encodeGtkwFile(parsed), '$base.expected_parse.json');
      });

      test('$name — import matches .expected_session.json', () {
        final parsed = _parser.parse(fixture.readAsStringSync());
        final result = _importService.importSession(
          parsed,
          fixtureVcdVariables(),
          gtkwFilePath: fixture.path,
          fileExists: (path) => File(path).existsSync(),
        );
        _expectGolden(
          encodeImportResult(result),
          '$base.expected_session.json',
        );
      });
    }
  });

  group('GTKWave captured corpus goldens', () {
    final fixtures = _gtkwFiles(_capturedDir);

    test('corpus is non-empty', () => expect(fixtures, isNotEmpty));

    for (final fixture in fixtures) {
      final name = p.basename(fixture.path);
      final base = fixture.path.replaceFirst(RegExp(r'\.gtkw$'), '');

      test('$name — real-world file parses without throwing', () {
        late final GtkwFile parsed;
        expect(
          () => parsed = _parser.parse(fixture.readAsStringSync()),
          returnsNormally,
        );
        // A captured save always lists at least one signal trace — a parse
        // that silently produced nothing would mean the format drifted.
        expect(
          parsed.entries.whereType<GtkwSignalEntry>(),
          isNotEmpty,
          reason: '$name parsed to zero signal entries',
        );
      });

      test('$name — parse matches .expected_parse.json', () {
        final parsed = _parser.parse(fixture.readAsStringSync());
        _expectGolden(encodeGtkwFile(parsed), '$base.expected_parse.json');
      });

      test('$name — importing against an empty variable set is non-fatal', () {
        // No dumpfile is committed for captured saves, so every path is
        // unmatched — but the import must still succeed and report them
        // rather than throw or drop signals silently.
        final parsed = _parser.parse(fixture.readAsStringSync());
        final result = _importService.importSession(parsed, const []);
        final signalCount = parsed.entries.whereType<GtkwSignalEntry>().length;
        expect(result.matchedSignalCount, 0);
        expect(result.unmatchedSignalPaths.length, signalCount);
      });
    }
  });
}

/// All `.gtkw` files directly under [dir] (non-recursive), sorted for stable
/// test ordering.
List<File> _gtkwFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  final files =
      d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gtkw'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Decodes the committed [goldenPath] and the freshly-[computed] map and
/// asserts deep equality, with an actionable hint on mismatch.
void _expectGolden(Map<String, Object?> computed, String goldenPath) {
  final golden = File(goldenPath);
  expect(
    golden.existsSync(),
    isTrue,
    reason:
        'missing golden $goldenPath — run '
        '`dart run tool/generate_gtkw_fixtures.dart`',
  );
  final expected = jsonDecode(golden.readAsStringSync());
  final actual = jsonDecode(jsonEncode(computed));
  expect(
    actual,
    expected,
    reason:
        'golden drift in ${p.relative(goldenPath)} — if intentional, '
        'regenerate with `dart run tool/generate_gtkw_fixtures.dart`',
  );
}
