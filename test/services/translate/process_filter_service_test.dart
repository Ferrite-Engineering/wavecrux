// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('!windows')
library;

import 'dart:io';

import 'package:crux_io/crux_io.dart' show SpawnHost;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/translate/process_filter_service.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// Writes a tiny shell script that echoes each stdin line back to stdout and
/// returns its path.  Used to exercise the request-response round-trip without
/// needing a real GTKWave filter program.
Future<String> _echoScript() async {
  final dir = await Directory.systemTemp.createTemp('pf_test_');
  final script = File('${dir.path}/echo_filter.sh');
  await script.writeAsString(
    '#!/bin/sh\nwhile IFS= read -r line; do echo "\$line"; done\n',
  );
  await Process.run('chmod', ['+x', script.path]);
  return script.path;
}

/// Writes a script that maps specific inputs to labels (simulates a real
/// GTKWave translate-filter program).
Future<String> _labelScript(Map<String, String> mapping) async {
  final dir = await Directory.systemTemp.createTemp('pf_label_test_');
  final script = File('${dir.path}/label_filter.sh');

  final cases = mapping.entries
      .map((e) => '    "${e.key}") echo "${e.value}";;')
      .join('\n');
  await script.writeAsString(
    '#!/bin/sh\n'
    'while IFS= read -r line; do\n'
    '  case "\$line" in\n'
    '$cases\n'
    '    *) echo "";;\n'
    '  esac\n'
    'done\n',
  );
  await Process.run('chmod', ['+x', script.path]);
  return script.path;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // These tests spawn real child processes, so they require dart:io and will
  // not run on the web platform (skipped by the test runner on web).

  group('ProcessFilterService', () {
    late ProcessFilterService service;

    setUp(() {
      service = ProcessFilterService();
    });

    tearDown(() {
      service.dispose();
    });

    // ── lifecycle ──────────────────────────────────────────────────────────────

    test('isRunning is false before startProcess', () {
      expect(service.isRunning, isFalse);
    });

    test('isRunning is true after startProcess', () async {
      final script = await _echoScript();
      await service.startProcess(script);
      expect(service.isRunning, isTrue);
    });

    test('isRunning is false after dispose', () async {
      final script = await _echoScript();
      await service.startProcess(script);
      service.dispose();
      expect(service.isRunning, isFalse);
    });

    test('startProcess throws for nonexistent executable', () async {
      await expectLater(
        () => service.startProcess('/nonexistent/path/to/filter_program'),
        throwsA(isA<ProcessException>()),
      );
    });

    // ── translate round-trip ──────────────────────────────────────────────────

    test('translate returns the line echoed by the process', () async {
      final script = await _echoScript();
      await service.startProcess(script);

      final result = await service.translate(
        'ff',
        timeout: const Duration(seconds: 10),
      );
      expect(result, 'ff');
    });

    test('translate correctly maps input → label via label script', () async {
      final script = await _labelScript({
        'ff': 'FULL',
        '0': 'ZERO',
        '1': 'ONE',
      });
      await service.startProcess(script);

      // Use a generous timeout: parallel test suites create many processes,
      // causing transient OS pressure that can delay shell script responses.
      const t = Duration(seconds: 10);
      expect(await service.translate('ff', timeout: t), 'FULL');
      expect(await service.translate('0', timeout: t), 'ZERO');
      expect(await service.translate('1', timeout: t), 'ONE');
    });

    test('translate returns null for empty-line response', () async {
      final script = await _labelScript({'known': 'LABEL'});
      await service.startProcess(script);

      // 'unknown' maps to empty echo → null
      expect(
        await service.translate(
          'unknown',
          timeout: const Duration(seconds: 10),
        ),
        isNull,
      );
    });

    test('translate handles multiple sequential requests correctly', () async {
      final script = await _labelScript({
        'a': 'ALPHA',
        'b': 'BETA',
        'c': 'GAMMA',
      });
      await service.startProcess(script);

      // The GTKWave protocol is inherently sequential (one hex value in, one
      // label out), so requests must be sent one at a time.
      const t = Duration(seconds: 10);
      final a = await service.translate('a', timeout: t);
      final b = await service.translate('b', timeout: t);
      final c = await service.translate('c', timeout: t);
      expect([a, b, c], ['ALPHA', 'BETA', 'GAMMA']);
    });

    test('translate returns null when process not started', () async {
      expect(await service.translate('ff'), isNull);
    });

    test('translate returns null after dispose', () async {
      final script = await _echoScript();
      await service.startProcess(script);
      service.dispose();
      expect(await service.translate('ff'), isNull);
    });

    // ── timeout ───────────────────────────────────────────────────────────────

    test('translate returns null on timeout (script that hangs)', () async {
      final dir = await Directory.systemTemp.createTemp('pf_hang_');
      final script = File('${dir.path}/hang.sh');
      await script.writeAsString('#!/bin/sh\nsleep 60\n');
      await Process.run('chmod', ['+x', script.path]);

      await service.startProcess(script.path);

      final result = await service.translate(
        'ff',
        timeout: const Duration(milliseconds: 100),
      );
      expect(result, isNull);
    });

    // ── process crash recovery ────────────────────────────────────────────────

    test('translate returns null gracefully when process crashes', () async {
      final dir = await Directory.systemTemp.createTemp('pf_crash_');
      final script = File('${dir.path}/crash.sh');
      // This script reads one line then exits immediately.
      await script.writeAsString('#!/bin/sh\nread -r _line\nexit 1\n');
      await Process.run('chmod', ['+x', script.path]);

      await service.startProcess(script.path);

      // The process will exit after consuming the first write.
      final result = await service.translate(
        'ff',
        timeout: const Duration(seconds: 2),
      );
      // Either null (no response) or a value is fine — the important thing is
      // that no exception is thrown.
      expect(result, anyOf(isNull, isA<String>()));
    });

    // ── dispose idempotency ───────────────────────────────────────────────────

    test('dispose is safe to call multiple times', () async {
      final script = await _echoScript();
      await service.startProcess(script);
      service.dispose();
      expect(() => service.dispose(), returnsNormally);
    });
  });

  // A filter named by bare name, on a Windows host laid out with a synthetic
  // PATH so the branch runs on every CI machine. Handed on bare, the name
  // would be searched for in the directory WaveCrux was launched from, ahead
  // of PATH, so a filter nothing on PATH answers to must start nothing.
  test('a bare filter name nothing on PATH answers to starts nothing on '
      'Windows', () async {
    final service = ProcessFilterService(
      spawnHost: SpawnHost(
        windows: true,
        environment: const {'PATH': r'C:\tools'},
        exists: (_) => false,
      ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.startProcess('riscv_filter'),
      throwsA(
        isA<ProcessException>()
            .having((e) => e.executable, 'executable', 'riscv_filter')
            .having((e) => e.message, 'message', 'not found on PATH'),
      ),
    );
    expect(service.isRunning, isFalse);
  });

  // ── _rawBitsToHex (tested indirectly via ProcessFilterNotifier) ───────────
  // Direct access isn't possible because it's private; covered by provider tests.
}
