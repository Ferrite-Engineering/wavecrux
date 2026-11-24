// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `spec/mcp/`: every tool's golden documents, one per outcome it can produce,
// against both doors.
//
// - The `wavecrux mcp` tool's `content[0]` text, with this machine's root
//   written as the goldens write it, is the golden byte for byte. The
//   goldens were written by hand from `spec/fixtures/handshake.vcd` (every
//   value, edge and window derived from the dump's own lines), not copied
//   from output. A VCD `$var` declares no port direction, so every
//   `direction` is `unknown` (`Variable.direction`'s own documentation).
// - The same text is byte for byte what `wavecrux <command> ... --json`
//   writes for the same arguments, and the command exits with the suite's
//   code for the outcome: the two doors cannot disagree.
// - Every golden keeps `spec/mcp/schemas/`: the envelope and its body.
// - Every link in every golden parses with the app's own link reader and
//   names the file, signal and tick of the location that carries it.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/links/wavecrux_link.dart';

import '../helpers/wellen_ffi_library_gate.dart';
import 'support/json_schema_check.dart';
import 'support/spec_cases.dart';

Map<String, Object?> _schema(String name) =>
    jsonDecode(File(p.join('spec', 'mcp', 'schemas', name)).readAsStringSync())
        as Map<String, Object?>;

/// Every object under [json] that has a `link` member, with its JSON path.
Iterable<(String, Map<String, Object?>)> _linked(
  Object? json,
  String at,
) sync* {
  if (json is Map<String, Object?>) {
    if (json.containsKey('link')) yield (at, json);
    for (final e in json.entries) {
      yield* _linked(e.value, '$at.${e.key}');
    }
  } else if (json is List<Object?>) {
    for (var i = 0; i < json.length; i++) {
      yield* _linked(json[i], '$at[$i]');
    }
  }
}

/// Every place location (`file` and `time`, no signal) under [json].
Iterable<Map<String, Object?>> _places(Object? json) sync* {
  if (json is Map<String, Object?>) {
    if (json.keys.toSet().containsAll(<String>['file', 'time']) &&
        !json.containsKey('signal')) {
      yield json;
    }
    for (final v in json.values) {
      yield* _places(v);
    }
  } else if (json is List<Object?>) {
    for (final v in json) {
      yield* _places(v);
    }
  }
}

void main() {
  if (!requireWellenFfiLibrary('spec goldens')) return;

  final spec = SpecCases.load();
  final documentSchema = _schema('document.schema.json');

  group('each golden is what the tool answers', () {
    for (final c in spec.cases) {
      test(c.golden, () async {
        final result = await spec.callTool(spec.cli(c), c);
        final content = result['content']! as List<Object?>;
        expect(content, hasLength(1));
        final item = content.single! as Map<String, Object?>;
        expect(item['type'], 'text');
        final text = item['text']! as String;
        expect(spec.normalize(text), spec.golden(c));
        final outcome = McpOutcome.fromWireName(
          (jsonDecode(text) as Map<String, Object?>)['outcome']! as String,
        );
        expect(result['isError'], outcome!.isError);
      });
    }
  });

  group('the tool and the command line write the same bytes', () {
    for (final c in spec.cases.where((c) => c.door == 'both')) {
      test(c.golden, () async {
        // One program for both doors, the real one, so nothing is normalized.
        final cli = spec.cli(
          c,
          program: const McpProgram(
            name: 'wavecrux',
            version: '9.9.9',
          ),
        );
        final result = await spec.callTool(cli, c);
        final toolText =
            ((result['content']! as List<Object?>).single!
                    as Map<String, Object?>)['text']!
                as String;
        final (stdoutText, code) = await spec.runCommandLine(
          spec.cli(
            c,
            program: const McpProgram(
              name: 'wavecrux',
              version: '9.9.9',
            ),
          ),
          spec.argv(cli, c),
        );
        expect(stdoutText, toolText);
        final outcome = McpOutcome.fromWireName(
          (jsonDecode(stdoutText) as Map<String, Object?>)['outcome']!
              as String,
        )!;
        expect(code, McpExitCodes.suite.exitCodeFor(outcome));
      });
    }
  });

  group('each golden keeps the schemas', () {
    for (final c in spec.cases) {
      test(c.golden, () {
        final doc = jsonDecode(spec.golden(c)) as Map<String, Object?>;
        expect(jsonSchemaProblems(doc, documentSchema), isEmpty);
        final body = doc['body'];
        if (body != null) {
          expect(
            jsonSchemaProblems(body, _schema('${c.tool}.body.schema.json')),
            isEmpty,
          );
        }
        final errors = (doc['diagnostics']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .where((d) => d['severity'] == 'error');
        if (doc['outcome'] == 'completed') {
          expect(body, isNotNull);
          expect(errors, isEmpty);
        } else {
          expect(body, isNull);
          expect(errors, isNotEmpty);
        }
      });
    }
  });

  test('the schema checker rejects what the schemas forbid', () {
    final good = jsonDecode(spec.golden(spec.cases.first));
    expect(jsonSchemaProblems(good, documentSchema), isEmpty);
    final extra = <String, Object?>{
      ...good as Map<String, Object?>,
      'extra': 1,
    };
    expect(jsonSchemaProblems(extra, documentSchema), isNotEmpty);
    final missing = Map<String, Object?>.of(good)..remove('engines');
    expect(jsonSchemaProblems(missing, documentSchema), isNotEmpty);
    final badOutcome = Map<String, Object?>.of(good)..['outcome'] = 'fine';
    expect(jsonSchemaProblems(badOutcome, documentSchema), isNotEmpty);
  });

  group('every link in every golden opens what its location names', () {
    for (final c in spec.cases) {
      test(c.golden, () {
        final doc = jsonDecode(spec.golden(c));
        for (final (at, location) in _linked(doc, r'$')) {
          final parsed = parseWaveCruxLink(location['link']! as String);
          expect(parsed, isA<WaveCruxLinkParsed>(), reason: at);
          final link = (parsed as WaveCruxLinkParsed).link;
          expect(link.file, location['file'], reason: at);
          expect(link.signal, location['signal'], reason: at);
          final time = location['time']! as Map<String, Object?>;
          expect(
            link.time,
            WaveCruxLinkTime.ticks(BigInt.from(time['at']! as int)),
          );
          // crux_mcp reads it back as the location it was built from.
          expect(McpLocation.fromJson(location), isA<McpSignalLocation>());
        }
        for (final place in _places(doc)) {
          final time = place['time']! as Map<String, Object?>;
          final link = waveCruxLink(
            place['file']! as String,
            time: McpTime.ticks(time['at']! as int),
          );
          final parsed = parseWaveCruxLink(link);
          expect(parsed, isA<WaveCruxLinkParsed>());
          expect((parsed as WaveCruxLinkParsed).link.file, place['file']);
        }
      });
    }

    test('the goldens carry links at all', () {
      final links = <String>[
        for (final c in spec.cases)
          for (final (_, l) in _linked(jsonDecode(spec.golden(c)), r'$'))
            l['link']! as String,
      ];
      expect(links.length, greaterThanOrEqualTo(6));
    });
  });

  test('every tool has a golden for each outcome it can produce', () {
    final byTool = <String, Set<String>>{};
    for (final c in spec.cases) {
      final doc = jsonDecode(spec.golden(c)) as Map<String, Object?>;
      byTool
          .putIfAbsent(c.tool, () => <String>{})
          .add(doc['outcome']! as String);
    }
    // The four free tools read; none has a gate or a licence to refuse, so
    // these four are every outcome they can produce.
    const produced = <String>{
      'completed',
      'usage_error',
      'input_error',
      'engine_error',
    };
    expect(byTool.keys.toSet(), <String>{
      'info',
      'search',
      'values',
      'transitions',
    });
    for (final entry in byTool.entries) {
      expect(entry.value, produced, reason: entry.key);
    }
  });
}
