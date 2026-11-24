// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The `wavecrux` command line around the documents: help, version, exit
// codes, the plain-text form, and the cases only the command line reaches.
// Values are worked by hand from `spec/fixtures/handshake.vcd`.

@TestOn('vm')
library;

import 'dart:convert';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/headless/cli_version.dart';
import 'package:wavecrux/headless/wavecrux_cli.dart';

import '../helpers/wellen_ffi_library_gate.dart';

Future<(int, String, String)> _run(List<String> argv) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await WaveCruxCli(telemetry: () => null).run(
    argv,
    out: out,
    err: err,
  );
  return (code, out.toString(), err.toString());
}

Map<String, Object?> _json(String text) =>
    jsonDecode(text) as Map<String, Object?>;

void main() {
  final dump = p.absolute('spec', 'fixtures', 'handshake.vcd');

  group('without a waveform', () {
    test('--version names the program and its version', () async {
      final (code, out, _) = await _run(<String>['--version']);
      expect(code, 0);
      expect(out, 'wavecrux $kWaveCruxCliVersion\n');
    });

    test('no arguments is a usage error with the help on stderr', () async {
      final (code, out, err) = await _run(const <String>[]);
      expect(code, 64);
      expect(out, isEmpty);
      expect(err, contains('transitions'));
      expect(err, contains('mcp'));
    });

    test('an unknown command is a usage error', () async {
      final (code, _, err) = await _run(<String>['advise', dump]);
      expect(code, 64);
      expect(err, contains('unknown command `advise`'));
    });

    test('each command has --help', () async {
      for (final c in <String>['info', 'search', 'values', 'transitions']) {
        final (code, out, _) = await _run(<String>[c, '--help']);
        expect(code, 0, reason: c);
        expect(out, contains('Usage: wavecrux $c'), reason: c);
        expect(out, contains('--json'), reason: c);
      }
    });

    test('mcp refuses a root that is not a directory', () async {
      final (code, _, err) = await _run(<String>['mcp', '--root', dump]);
      expect(code, 64);
      expect(err, contains('is not a directory'));
    });

    test('a missing file exits 65 with its document', () async {
      final (code, out, _) = await _run(<String>[
        'info',
        p.join(p.dirname(dump), 'missing.vcd'),
        '--json',
      ]);
      expect(code, 65);
      expect(_json(out)['outcome'], 'input_error');
    });

    test('a bad flag is a usage_error document, exit 64', () async {
      final (code, out, _) = await _run(<String>[
        'transitions',
        dump,
        '--signal',
        'top.clk',
        '--from',
        '0',
        '--json',
      ]);
      expect(code, 64);
      final doc = _json(out);
      expect(doc['outcome'], 'usage_error');
      expect(doc['command'], 'transitions');
    });

    test('the suite exit-code table', () {
      final t = McpExitCodes.suite;
      expect(
        <int>[
          for (final o in McpOutcome.values) t.exitCodeFor(o),
        ],
        <int>[0, 1, 64, 65, 3, 77],
      );
    });
  });

  if (!requireWellenFfiLibrary('wavecrux command line')) return;

  group('reading the fixture', () {
    test('without --json, a person reads the answer', () async {
      final (code, out, err) = await _run(<String>[
        'transitions',
        dump,
        '--signal',
        'top.u_sink.ready',
        '--from',
        '0',
        '--to',
        '30',
      ]);
      expect(code, 0);
      expect(err, isEmpty);
      expect(
        out,
        'top.u_sink.ready (at start: z)\n'
        '  0  z\n'
        '  10  0\n'
        '  25  1\n',
      );
    });

    test(
      'a value is the one recorded at that tick, after its changes',
      () async {
        // valid goes 0 -> 1 at tick 20; ready is 0 from 10 to 25.
        final (code, out, _) = await _run(<String>[
          'values',
          dump,
          '--signal',
          'top.valid',
          '--signal',
          'top.u_sink.ready',
          '--at',
          '20',
          '--json',
        ]);
        expect(code, 0);
        final signals =
            (_json(out)['body']! as Map<String, Object?>)['signals']!
                as List<Object?>;
        expect(
          signals.map((s) => (s! as Map<String, Object?>)['values']),
          <Object?>[
            <Object?>['1'],
            <Object?>['0'],
          ],
        );
      },
    );

    test('a window that ends on a change leaves it out', () async {
      // count changes at 15 and 25; [15, 25) holds only the first.
      final (_, out, _) = await _run(<String>[
        'transitions',
        dump,
        '--signal',
        'top.count',
        '--from',
        '15ns',
        '--to',
        '25ns',
        '--json',
      ]);
      final signal =
          ((_json(out)['body']! as Map<String, Object?>)['signals']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;
      expect(signal['transitions'], <Object?>[
        <String, Object?>{'time': 15, 'value': '0001'},
      ]);
      expect(signal['valueAtStart'], '0001');
    });

    test('a clock wider than one bit is refused', () async {
      final (code, out, _) = await _run(<String>[
        'values',
        dump,
        '--signal',
        'top.valid',
        '--clock',
        'top.count',
        '--from',
        '0',
        '--to',
        '40',
        '--json',
      ]);
      expect(code, 65);
      final doc = _json(out);
      expect(
        (doc['diagnostics']! as List<Object?>).map(
          (d) => (d! as Map<String, Object?>)['code'],
        ),
        <String>['values.clock_width'],
      );
    });

    test('a signal reference resolves like a path', () async {
      final (_, out, _) = await _run(<String>[
        'values',
        dump,
        '--signal',
        '5',
        '--at',
        '25',
        '--json',
      ]);
      final signal =
          ((_json(out)['body']! as Map<String, Object?>)['signals']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;
      expect(signal['path'], 'top.u_sink.data');
      expect(signal['values'], <Object?>['10100101']);
    });

    test(
      'a file wellen cannot parse is an input error with its reason',
      () async {
        final bad = p.absolute(
          'test',
          'fixtures',
          'vcd',
          'malformed_value_change.vcd',
        );
        final (code, out, _) = await _run(<String>['info', bad, '--json']);
        final doc = _json(out);
        expect(doc['outcome'], 'input_error');
        expect(code, 65);
        final diagnostic =
            (doc['diagnostics']! as List<Object?>).single!
                as Map<String, Object?>;
        expect(diagnostic['code'], 'input.unreadable');
        expect(diagnostic['message'], startsWith('wellen could not read'));
      },
    );
  });
}
