// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `wavecrux mcp`: what it lists, what that costs, what it refuses and what it
// counts.
//
// The expected definitions are the MCP tool contracts' own text for the four
// free tools, copied here verbatim; the budget is held to the measured sizes
// in the same contracts.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crux_mcp/crux_mcp_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/headless/cli_version.dart';
import 'package:wavecrux/headless/wave_file_cache.dart';
import 'package:wavecrux/headless/wavecrux_cli.dart';

/// The contracts' definitions of the four free tools, verbatim.
const List<String> _contractDefinitions = <String>[
  _info,
  _search,
  _values,
  _transitions,
];

const String _info =
    '{"name": "info", "description": "Open a waveform file (VCD, FST, GHW and '
    'others) and return its timescale, time range, top scopes and signal '
    'count. Every WaveCrux tool gives times in ticks of this timescale.", '
    '"inputSchema": {"type": "object", "properties": {"file": {"type": '
    '"string"}}, "required": ["file"]}}';

const String _search =
    '{"name": "search", "description": "Find signals in a waveform by name. '
    'Returns full hierarchical paths, widths and types.", "inputSchema": '
    '{"type": "object", "properties": {"file": {"type": "string"}, "query": '
    '{"type": "string"}, "glob": {"type": "boolean", "description": "Match * '
    'and ? as a glob, not a substring."}, "limit": {"type": "integer", '
    '"description": "Default 50, at most 500."}}, "required": ["file", '
    '"query"]}}';

const String _values =
    '{"name": "values", "description": "Values of signals at one time, or at '
    'each rising edge of a clock between two times. Each signal carries a '
    'link that opens it in WaveCrux.", "inputSchema": {"type": "object", '
    '"properties": {"file": {"type": "string"}, "signals": {"type": "array", '
    '"items": {"type": "string"}, "description": "Full paths, at most 32."}, '
    '"at": {"type": ["integer", "string"], "description": "A tick, or a time '
    'such as 1500ns."}, "clock": {"type": "string"}, "from": {"type": '
    '["integer", "string"]}, "to": {"type": ["integer", "string"]}, "limit": '
    '{"type": "integer", "description": "Clock edges, default 200, at most '
    '5000."}}, "required": ["file", "signals"]}}';

const String _transitions =
    '{"name": "transitions", "description": "Every value change of signals '
    "between two times, exactly as recorded, with each signal's value at "
    'the start. Use instead of sampling. A truncated signal gives next_from '
    'to continue.", "inputSchema": {"type": "object", "properties": {"file": '
    '{"type": "string"}, "signals": {"type": "array", "items": {"type": '
    '"string"}, "description": "Full paths, at most 32."}, "from": {"type": '
    '["integer", "string"]}, "to": {"type": ["integer", "string"]}, "limit": '
    '{"type": "integer", "description": "Changes per signal, default 200, at '
    'most 10000."}}, "required": ["file", "signals", "from", "to"]}}';

/// A cache whose opener records every path it is asked for and opens none.
(WaveFileCache, List<String>) _recordingCache() {
  final opened = <String>[];
  final cache = WaveFileCache(
    opener: (path) async {
      opened.add(path);
      throw StateError('the test opens nothing');
    },
  );
  return (cache, opened);
}

Future<Map<String, Object?>> _call(
  McpServer server,
  String tool,
  Map<String, Object?> arguments,
) async {
  final line = await server.handleLine(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'tools/call',
      'params': <String, Object?>{'name': tool, 'arguments': arguments},
    }),
  );
  return jsonDecode(line!) as Map<String, Object?>;
}

Map<String, Object?> _document(Map<String, Object?> reply) {
  final result = reply['result']! as Map<String, Object?>;
  final text =
      ((result['content']! as List<Object?>).single!
              as Map<String, Object?>)['text']!
          as String;
  return jsonDecode(text) as Map<String, Object?>;
}

void main() {
  final fixtures = p.absolute('spec', 'fixtures');

  group('initialize and tools/list', () {
    test(
      'a scripted client gets the instructions and the four tools',
      () async {
        final server = WaveCruxCli(
          telemetry: () => null,
        ).server(root: fixtures);
        final client = McpScriptedClient.inProcess(server);
        final init = await client.request('initialize', <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{'name': 'test', 'version': '0'},
        });
        final result = init['result']! as Map<String, Object?>;
        expect(result['protocolVersion'], '2025-06-18');
        expect(result['serverInfo'], <String, Object?>{
          'name': 'wavecrux',
          'version': kWaveCruxCliVersion,
        });
        expect(result['instructions'], kWaveCruxMcpInstructions);
        final list = await client.request('tools/list');
        final tools =
            (list['result']! as Map<String, Object?>)['tools']!
                as List<Object?>;
        expect(
          tools.map((t) => (t! as Map<String, Object?>)['name']),
          <String>['info', 'search', 'values', 'transitions'],
        );
        await client.close();
      },
    );

    test("each definition is the contracts' text exactly", () {
      final server = WaveCruxCli(telemetry: () => null).server(root: fixtures);
      final definitions = server.definitions();
      expect(definitions, hasLength(_contractDefinitions.length));
      for (var i = 0; i < definitions.length; i++) {
        expect(
          mcpRenderJsonLine(definitions[i]),
          jsonEncode(jsonDecode(_contractDefinitions[i])),
        );
      }
    });

    test('the instructions say when to call and to cite, and nothing more', () {
      expect(kWaveCruxMcpInstructions.length, lessThanOrEqualTo(600));
      expect(kWaveCruxMcpInstructions, contains('link'));
      expect(kWaveCruxMcpInstructions, contains('re-running the simulation'));
      for (final word in <String>['better', 'improv', 'faster', 'accura']) {
        expect(kWaveCruxMcpInstructions.toLowerCase(), isNot(contains(word)));
      }
      expect(kWaveCruxMcpInstructions, isNot(contains('\u2014')));
    });
  });

  group('the definition budget', () {
    final server = WaveCruxCli(telemetry: () => null).server(root: fixtures);

    test(
      'stays inside the ceilings of 2,000 per tool and 4,000 per server',
      () {
        expectDefinitionBudget(server);
      },
    );

    test("matches the contracts' measured sizes", () {
      // Measured in the contracts (definition budget table): `values` is
      // WaveCrux's largest tool at 632 characters, and the five tools (these
      // four and the Pro `advise`) total 2,386.
      final byName = <String, int>{
        for (final t in server.tools) t.name: t.definitionLength,
      };
      expect(byName['values'], 632);
      for (final length in byName.values) {
        expect(length, lessThanOrEqualTo(632));
      }
      final four = byName.values.fold<int>(0, (a, b) => a + b);
      expect(four, lessThan(2386));
      expect(
        mcpServerDefinitionLength(server),
        four + kWaveCruxMcpInstructions.length,
      );
      expect(mcpServerDefinitionLength(server), lessThanOrEqualTo(2986));
    });

    test('a tool past its ceiling fails the check', () {
      final bloated = McpServer(
        program: kWaveCruxCliProgramForTest,
        instructions: kWaveCruxMcpInstructions,
        tools: <McpTool>[
          ...server.tools,
          McpTool(
            name: 'padding',
            description: 'x' * 2000,
            fields: const <McpField>[],
          ),
        ],
        confinement: Confinement(fixtures),
        runner: (_) async => throw StateError('never run'),
      );
      expect(
        () => expectDefinitionBudget(bloated),
        throwsA(isA<McpBudgetExceeded>()),
      );
    });
  });

  group('confinement: refused paths are never opened', () {
    late Directory root;
    late Directory outside;

    setUp(() {
      root = Directory.systemTemp.createTempSync('wavecrux_mcp_root_');
      outside = Directory.systemTemp.createTempSync('wavecrux_mcp_out_');
      File(p.join(fixtures, 'handshake.vcd')).copySync(
        p.join(outside.path, 'secret.vcd'),
      );
      Link(p.join(root.path, 'escape.vcd')).createSync(
        p.join(outside.path, 'secret.vcd'),
      );
      Link(p.join(root.path, 'escape_dir')).createSync(outside.path);
    });

    tearDown(() {
      root.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });

    final refused = <String, String>{
      'an absolute path outside the root': '<outside>/secret.vcd',
      'a relative path climbing out': '../outside.vcd',
      'a symbolic link to a file outside': 'escape.vcd',
      'a symbolic link to a directory outside': 'escape_dir/secret.vcd',
      'a `..` below a name that does not exist': 'no_such_dir/../../x.vcd',
      'a Windows network path': r'\\server\share\dump.vcd',
      'a network path spelled with slashes': '//server/share/dump.vcd',
      'a Windows device path': r'\\?\C:\dump.vcd',
    };

    for (final entry in refused.entries) {
      for (final tool in <String>['info', 'search', 'values', 'transitions']) {
        test('$tool: ${entry.key}', () async {
          final (cache, opened) = _recordingCache();
          final server = WaveCruxCli(
            cache: cache,
            telemetry: () => null,
          ).server(root: root.path);
          final file = entry.value.replaceFirst('<outside>', outside.path);
          final arguments = <String, Object?>{
            'file': file,
            if (tool == 'search') 'query': 'clk',
            if (tool == 'values' || tool == 'transitions')
              'signals': <String>['top.clk'],
            if (tool == 'values') 'at': 0,
            if (tool == 'transitions') ...<String, Object?>{
              'from': 0,
              'to': 10,
            },
          };
          final reply = await _call(server, tool, arguments);
          final result = reply['result']! as Map<String, Object?>;
          expect(result['isError'], isTrue);
          final doc = _document(reply);
          expect(doc['outcome'], 'usage_error');
          expect(doc['body'], isNull);
          expect(opened, isEmpty, reason: 'a refused path was opened');
        });
      }
    }

    test('a path inside the root, through a link that stays inside, is '
        'opened', () async {
      File(p.join(fixtures, 'handshake.vcd')).copySync(
        p.join(root.path, 'dump.vcd'),
      );
      Link(
        p.join(root.path, 'alias.vcd'),
      ).createSync(p.join(root.path, 'dump.vcd'));
      final (cache, opened) = _recordingCache();
      final server = WaveCruxCli(
        cache: cache,
        telemetry: () => null,
      ).server(root: root.path);
      await _call(server, 'info', <String, Object?>{'file': 'alias.vcd'});
      expect(opened, <String>[p.join(root.path, 'alias.vcd')]);
    });
  });

  group('arguments the contracts refuse', () {
    final server = WaveCruxCli(telemetry: () => null).server(root: fixtures);

    test('an unknown field is a usage error and runs nothing', () async {
      final doc = _document(
        await _call(server, 'info', <String, Object?>{
          'file': 'handshake.vcd',
          'export': 'out.json',
        }),
      );
      expect(doc['outcome'], 'usage_error');
    });

    test('a wrong type is a usage error', () async {
      final doc = _document(
        await _call(server, 'values', <String, Object?>{
          'file': 'handshake.vcd',
          'signals': 'top.clk',
          'at': 0,
        }),
      );
      expect(doc['outcome'], 'usage_error');
    });

    test('an unknown tool is a JSON-RPC error, not a document', () async {
      final reply = await _call(server, 'advise', <String, Object?>{});
      expect((reply['error']! as Map<String, Object?>)['code'], -32602);
    });
  });

  group('telemetry', () {
    test(
      'one mcp.tool_call per call: tool, outcome and duration only',
      () async {
        final events = <(String, Map<String, Object?>)>[];
        final telemetry = McpTelemetry(
          consented: () => true,
          sink: (name, properties) => events.add((name, properties)),
          environment: const <String, String>{},
        );
        final server = WaveCruxCli(
          telemetry: () => null,
        ).server(root: fixtures, telemetry: telemetry);
        final client = McpScriptedClient.inProcess(server);
        await client.request('tools/call', <String, Object?>{
          'name': 'info',
          'arguments': <String, Object?>{'file': 'missing.vcd'},
        });
        await client.close();
        expect(events, hasLength(1));
        expect(events.single.$1, 'mcp.tool_call');
        expect(events.single.$2, <String, Object?>{
          'tool': 'info',
          'outcome': 'input_error',
          'duration': 'lt_1s',
        });
      },
    );

    test('nothing is counted when CI is set', () async {
      final events = <String>[];
      final telemetry = McpTelemetry(
        consented: () => true,
        sink: (name, _) => events.add(name),
        environment: const <String, String>{'CI': 'true'},
      );
      final server = WaveCruxCli(
        telemetry: () => null,
      ).server(root: fixtures, telemetry: telemetry);
      await _call(server, 'info', <String, Object?>{'file': 'missing.vcd'});
      expect(events, isEmpty);
    });

    test("the binary counts under the WaveCrux desktop app's consent", () {
      final headless = waveCruxHeadlessTelemetry();
      expect(headless.product, CruxTelemetryProduct.wavecrux);
      expect(headless.pro, isFalse);
      expect(headless.appVersion, kWaveCruxCliVersion);
      expect(headless.licenseTier, 'openCore');
    });
  });
}

/// A program for servers built in tests.
const McpProgram kWaveCruxCliProgramForTest = McpProgram(
  name: 'wavecrux',
  version: kWaveCruxCliVersion,
);
