// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/user_isa_tables.dart';

/// The front door: WaveCrux scanning a directory the user chose.
///
/// Until this landed the only way to consume a hand-authored table was to
/// build from source, while the website told readers to point WaveCrux at one.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wavecrux-isa-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String table(String setName) =>
      '''
set = "$setName"
width = 32

[formats]
names = ["r_type"]
parts = [["opcode", 7, "", ""], ["imm", 25, "u32", "hexadecimal"]]

[types]
names = ["r"]
[[types.r]]
name = "opcode"
top = 6
bot = 0
[[types.r]]
name = "imm"
top = 24
bot = 0

[r_type]
type = "r"

[r_type.repr]
default = "custom {imm}"

[r_type.instructions.custom]
mask = 127
match = 11
''';

  test('a table in a configured directory is loaded', () async {
    File(p.join(tmp.path, 'ACME.toml')).writeAsStringSync(table('ACME_VLIW'));

    final result = await loadUserIsaTables(directories: <String>[tmp.path]);

    expect(result.sets.keys, contains('ACME'));
    expect(result.sets['ACME']!.setName, 'ACME_VLIW');
    expect(result.issues, isEmpty);
    expect(result.scannedDirectories, contains(tmp.path));
  });

  test('the set is keyed by file name, not by the set label', () async {
    // Two tables declaring the same `set` must not collapse into one. The file
    // name is also the thing the author can see and change.
    File(p.join(tmp.path, 'a.toml')).writeAsStringSync(table('SAME'));
    File(p.join(tmp.path, 'b.toml')).writeAsStringSync(table('SAME'));

    final result = await loadUserIsaTables(directories: <String>[tmp.path]);

    expect(result.sets.keys, containsAll(<String>['a', 'b']));
  });

  test('a malformed table is reported, and its siblings still load', () async {
    File(p.join(tmp.path, 'good.toml')).writeAsStringSync(table('GOOD'));
    File(p.join(tmp.path, 'bad.toml')).writeAsStringSync('set = "BAD"');

    final result = await loadUserIsaTables(directories: <String>[tmp.path]);

    expect(result.sets.keys, contains('good'));
    expect(result.sets.keys, isNot(contains('bad')));
    expect(result.issues, hasLength(1));
    // The path so the author knows which file; the message so they know what
    // to change. A skipped file with neither is indistinguishable from a table
    // that loaded and decoded nothing.
    expect(result.issues.single.source, contains('bad.toml'));
    expect(result.issues.single.message, contains('bad.toml'));
  });

  test('non-toml files are ignored without complaint', () async {
    File(p.join(tmp.path, 'README.md')).writeAsStringSync('not a table');
    File(p.join(tmp.path, 'ACME.toml')).writeAsStringSync(table('ACME'));

    final result = await loadUserIsaTables(directories: <String>[tmp.path]);

    expect(result.sets.keys, <String>['ACME']);
    expect(result.issues, isEmpty);
  });

  test('a relative directory is refused rather than resolved', () async {
    // What a relative path means depends on how the app was launched, which is
    // not something a user can reason about from a settings field.
    final result = await loadUserIsaTables(
      directories: const <String>['./tables'],
    );

    expect(result.scannedDirectories, isEmpty);
    expect(result.sets, isEmpty);
  });

  test('a directory that does not exist is skipped quietly', () async {
    final result = await loadUserIsaTables(
      directories: <String>[p.join(tmp.path, 'nope')],
    );

    expect(result.scannedDirectories, isEmpty);
    expect(result.issues, isEmpty);
  });

  test('the environment variable is honoured', () async {
    File(p.join(tmp.path, 'ENV.toml')).writeAsStringSync(table('FROM_ENV'));

    final result = await loadUserIsaTables(
      directories: const <String>[],
      environment: <String, String>{kIsaTablePathEnvVar: tmp.path},
    );

    expect(result.sets.keys, contains('ENV'));
  });

  test('load order is deterministic across runs', () async {
    for (final name in <String>['c', 'a', 'b']) {
      File(p.join(tmp.path, '$name.toml')).writeAsStringSync(table(name));
    }

    final first = await loadUserIsaTables(directories: <String>[tmp.path]);
    final second = await loadUserIsaTables(directories: <String>[tmp.path]);

    // Filesystem listing order is not stable; two machines with the same
    // directory must compose the same way, because the disassembler resolves
    // last-match-wins and order therefore decides decodes.
    expect(first.sets.keys.toList(), second.sets.keys.toList());
    expect(first.sets.keys.toList(), <String>['a', 'b', 'c']);
  });
}
