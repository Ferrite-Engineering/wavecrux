// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A reader that failed never gives an answer.
//
// `classifyReaderFailure` maps what wellen (or the worker around it) threw to
// how a command ends. The oracle below runs every command against a reader
// that fails each way it can (a refused file, an unreadable one, a hang, a
// worker that cannot start, a signal that cannot be loaded), when opening and
// when loading a signal, and lists every run that came back as an answer.
// The mutation proof runs the same oracle with a broken mapping that calls
// every failure `completed` and asserts that the oracle catches it, so the
// oracle cannot be vacuous.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/headless/wave_commands.dart';
import 'package:wavecrux/headless/wave_file_cache.dart';
import 'package:wavecrux/headless/wavecrux_cli.dart';

import 'support/fake_wave_source.dart';

/// Every failure the reader can raise.
final Map<String, Object> _failures = <String, Object>{
  'a file wellen refuses': const WaveformOpenException('bad header'),
  'a file that cannot be read': const FileSystemException('denied'),
  'a reader that hangs': TimeoutException('open'),
  'a worker that cannot start': Exception('library not found'),
  'anything else': StateError('broken'),
};

/// Each command's arguments, after its name.
List<List<String>> _commands(String file) => <List<String>>[
  <String>['info', file, '--json'],
  <String>['search', file, 'clk', '--json'],
  <String>['values', file, '--signal', 'top.clk', '--at', '5', '--json'],
  <String>[
    'values', file, '--signal', 'top.clk', '--clock', 'top.clk', //
    '--from', '0', '--to', '40', '--json',
  ],
  <String>[
    'transitions', file, '--signal', 'top.clk', '--from', '0', '--to', //
    '40', '--json',
  ],
];

/// The runs that ended as an answer although the reader failed, or wrote no
/// valid document: empty when [mapFailure] never lets a failure through.
Future<List<String>> _answersFromFailedReaders(
  ReaderFailureMap mapFailure,
) async {
  final file = p.absolute('spec', 'fixtures', 'handshake.vcd');
  final problems = <String>[];
  for (final failure in _failures.entries) {
    for (final when in <String>['open', 'load']) {
      for (final args in _commands(file)) {
        // `search` and `info` load no signal, so a load failure cannot
        // reach them; every other run must fail.
        if (when == 'load' &&
            (args.first == 'info' || args.first == 'search')) {
          continue;
        }
        final cli = WaveCruxCli(
          cache: WaveFileCache(
            opener: (path) async {
              if (when == 'open') {
                Error.throwWithStackTrace(failure.value, StackTrace.current);
              }
              return fakeWaveFile(loadError: failure.value);
            },
          ),
          telemetry: () => null,
          mapFailure: mapFailure,
        );
        final out = StringBuffer();
        final label = '${failure.key} at $when: ${args.take(1).join()}';
        int code;
        try {
          code = await cli.run(args, out: out, err: StringBuffer());
        } on Object catch (e) {
          problems.add('$label threw $e');
          continue;
        }
        final outcome = mcpDocumentOutcome(out.toString());
        if (outcome == null) {
          problems.add('$label wrote no document');
        } else if (outcome.isAnswer) {
          problems.add('$label answered ${outcome.wireName}');
        } else if (code == 0) {
          problems.add('$label exited 0');
        }
      }
    }
  }
  return problems;
}

void main() {
  test('no reader failure becomes an answer', () async {
    expect(await _answersFromFailedReaders(classifyReaderFailure), isEmpty);
  });

  test(
    'mutation proof: a mapping that calls a failure completed is caught',
    () async {
      ReaderFailure broken(Object error, {required String file}) =>
          const ReaderFailure(
            McpOutcome.completed,
            McpDiagnostic(
              severity: McpSeverity.note,
              code: 'engine.failed',
              message: 'ignored',
            ),
          );
      final problems = await _answersFromFailedReaders(broken);
      // Every run of the oracle reports the mutant, not just one.
      expect(problems, hasLength(_failures.length * (5 + 3)));
    },
  );

  test(
    'mutation proof: a mapping that drops the engine error is caught',
    () async {
      // The subtler break: the outcome right, the reason gone. A document
      // without its error diagnostic is never written, so the run fails loudly.
      ReaderFailure silent(Object error, {required String file}) =>
          const ReaderFailure(
            McpOutcome.engineError,
            McpDiagnostic(
              severity: McpSeverity.warning,
              code: 'engine.failed',
              message: 'ignored',
            ),
          );
      expect(await _answersFromFailedReaders(silent), isNotEmpty);
    },
  );

  group('classifyReaderFailure', () {
    test("a file wellen refuses or cannot read is the input's fault", () {
      for (final error in <Object>[
        const WaveformOpenException('bad'),
        const FileSystemException('denied'),
      ]) {
        final f = classifyReaderFailure(error, file: '/x.vcd');
        expect(f.outcome, McpOutcome.inputError);
        expect(f.diagnostic.severity, McpSeverity.error);
        expect(f.diagnostic.code, 'input.unreadable');
      }
    });

    test("wellen's own reason reaches the reader", () {
      final f = classifyReaderFailure(
        const WaveformOpenException('expected an id for a value change'),
        file: '/x.vcd',
      );
      expect(
        f.diagnostic.message,
        contains('expected an id for a value change'),
      );
    });

    test("a hang or a worker failure is the engine's", () {
      expect(
        classifyReaderFailure(
          TimeoutException('t'),
          file: '/x',
        ).diagnostic.code,
        'engine.timeout',
      );
      final f = classifyReaderFailure(Exception('no lib'), file: '/x');
      expect(f.outcome, McpOutcome.engineError);
      expect(f.diagnostic.code, 'engine.failed');
    });
  });
}
