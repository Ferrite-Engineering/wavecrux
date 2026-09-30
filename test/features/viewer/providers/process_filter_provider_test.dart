// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/process_filter_provider.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// Writes a shell script that echoes each stdin line as-is and returns its path.
Future<String> _echoScript() async {
  final dir = await Directory.systemTemp.createTemp('pf_provider_test_');
  final script = File('${dir.path}/echo.sh');
  await script.writeAsString(
    '#!/bin/sh\nwhile IFS= read -r line; do echo "\$line"; done\n',
  );
  await Process.run('chmod', ['+x', script.path]);
  return script.path;
}

/// Writes a script that maps hex values to labels (blank line = no match).
Future<String> _labelScript(Map<String, String> mapping) async {
  final dir = await Directory.systemTemp.createTemp('pf_label_provider_');
  final script = File('${dir.path}/labels.sh');
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
  group('ProcessFilterNotifier', () {
    // ── initial state ─────────────────────────────────────────────────────────

    test('initial state is empty', () {
      final c = _container();
      expect(c.read(processFilterProvider), isEmpty);
    });

    test('executablePaths is empty initially', () {
      final c = _container();
      expect(
        c.read(processFilterProvider.notifier).executablePaths,
        isEmpty,
      );
    });

    test('hasProcessFilter returns false initially', () {
      final c = _container();
      expect(
        c.read(processFilterProvider.notifier).hasProcessFilter('top.sig'),
        isFalse,
      );
    });

    // ── setProcessFilter ──────────────────────────────────────────────────────

    test('setProcessFilter adds signal to state with null cache', () async {
      final script = await _echoScript();
      final c = _container();
      await c
          .read(processFilterProvider.notifier)
          .setProcessFilter('top.sig', script);

      final state = c.read(processFilterProvider);
      expect(state, contains('top.sig'));
      expect(state['top.sig'], isNull); // no cache yet
    });

    test('setProcessFilter records executable path', () async {
      final script = await _echoScript();
      final c = _container();
      await c
          .read(processFilterProvider.notifier)
          .setProcessFilter('top.sig', script);

      expect(
        c.read(processFilterProvider.notifier).executablePaths,
        {'top.sig': script},
      );
    });

    test('hasProcessFilter returns true after assignment', () async {
      final script = await _echoScript();
      final c = _container();
      await c
          .read(processFilterProvider.notifier)
          .setProcessFilter('top.sig', script);

      expect(
        c.read(processFilterProvider.notifier).hasProcessFilter('top.sig'),
        isTrue,
      );
    });

    test('setProcessFilter is a no-op for nonexistent executable', () async {
      final c = _container();
      await c
          .read(processFilterProvider.notifier)
          .setProcessFilter('top.sig', '/nonexistent/filter_executable');

      expect(c.read(processFilterProvider), isEmpty);
    });

    test('setProcessFilter replaces existing process for same ref', () async {
      final script1 = await _echoScript();
      final script2 = await _labelScript({'ff': 'FULL'});
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script1);
      await notifier.setProcessFilter('top.sig', script2);

      expect(c.read(processFilterProvider), contains('top.sig'));
      expect(notifier.executablePaths['top.sig'], script2);
    });

    // ── removeProcessFilter ───────────────────────────────────────────────────

    test('removeProcessFilter removes signal from state', () async {
      final script = await _echoScript();
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      expect(c.read(processFilterProvider), contains('top.sig'));

      notifier.removeProcessFilter('top.sig');
      expect(c.read(processFilterProvider), isNot(contains('top.sig')));
    });

    test('removeProcessFilter clears executable path', () async {
      final script = await _echoScript();
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      notifier.removeProcessFilter('top.sig');

      expect(notifier.executablePaths, isEmpty);
    });

    test('removeProcessFilter is a no-op when signal has no filter', () {
      final c = _container();
      expect(
        () => c
            .read(processFilterProvider.notifier)
            .removeProcessFilter('top.sig'),
        returnsNormally,
      );
    });

    // ── translateValue ────────────────────────────────────────────────────────

    test(
      'translateValue returns null when no process filter assigned',
      () async {
        final c = _container();
        final result = await c
            .read(processFilterProvider.notifier)
            .translateValue('top.sig', '11111111');
        expect(result, isNull);
      },
    );

    test('translateValue sends hex and returns translated label', () async {
      // Script maps "ff" → "FULL"
      final script = await _labelScript({'ff': 'FULL'});
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      final result = await notifier.translateValue(
        'top.sig',
        '11111111',
        timeout: const Duration(seconds: 10),
      );

      expect(result, 'FULL'); // binary 11111111 → hex ff
    });

    test('translateValue returns null for empty-line response', () async {
      final script = await _labelScript({'ff': 'KNOWN'});
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      // '0' → hex '0' which isn't in the label map → empty → null
      final result = await notifier.translateValue(
        'top.sig',
        '0',
        timeout: const Duration(seconds: 10),
      );
      expect(result, isNull);
    });

    test('translateValue updates state cache with translated label', () async {
      final script = await _labelScript({'ff': 'FULL'});
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      await notifier.translateValue(
        'top.sig',
        '11111111',
        timeout: const Duration(seconds: 10),
      );

      expect(c.read(processFilterProvider)['top.sig'], 'FULL');
    });

    test(
      'translateValue leaves cache null when process returns empty',
      () async {
        final script = await _labelScript({'ff': 'KNOWN'});
        final c = _container();
        final notifier = c.read(processFilterProvider.notifier);

        await notifier.setProcessFilter('top.sig', script);
        await notifier.translateValue(
          'top.sig',
          '0',
          timeout: const Duration(seconds: 10),
        ); // no match → null

        expect(c.read(processFilterProvider)['top.sig'], isNull);
      },
    );

    // ── _rawBitsToHex (via translateValue) ────────────────────────────────────

    test('strips VCD b prefix before converting to hex', () async {
      // 'b11111111' should strip 'b' → '11111111' → hex 'ff'
      final script = await _labelScript({'ff': 'FULL'});
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      final result = await notifier.translateValue(
        'top.sig',
        'b11111111',
        timeout: const Duration(seconds: 10),
      );
      expect(result, 'FULL');
    });

    test('sends "x" for values containing x bits', () async {
      final script = await _labelScript({'x': 'UNKNOWN'});
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      final result = await notifier.translateValue(
        'top.sig',
        'bxx01',
        timeout: const Duration(seconds: 10),
      );
      expect(result, 'UNKNOWN');
    });

    test('sends "x" for values containing z bits', () async {
      final script = await _labelScript({'x': 'HIMP'});
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      final result = await notifier.translateValue(
        'top.sig',
        'bzzzz',
        timeout: const Duration(seconds: 10),
      );
      expect(result, 'HIMP');
    });

    // ── restoreFromSession ────────────────────────────────────────────────────

    test('restoreFromSession loads all provided paths', () async {
      final script1 = await _echoScript();
      final script2 = await _labelScript({'1': 'ONE'});
      final c = _container();

      await c.read(processFilterProvider.notifier).restoreFromSession({
        'top.a': script1,
        'top.b': script2,
      });

      final state = c.read(processFilterProvider);
      expect(state, contains('top.a'));
      expect(state, contains('top.b'));
    });

    test('restoreFromSession clears previous state first', () async {
      final script1 = await _echoScript();
      final script2 = await _echoScript();
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.old', script1);
      expect(c.read(processFilterProvider), contains('top.old'));

      await notifier.restoreFromSession({'top.new': script2});

      final state = c.read(processFilterProvider);
      expect(state, isNot(contains('top.old')));
      expect(state, contains('top.new'));
    });

    test(
      'restoreFromSession skips missing executables without throwing',
      () async {
        final goodScript = await _echoScript();
        final c = _container();

        await c.read(processFilterProvider.notifier).restoreFromSession({
          'top.good': goodScript,
          'top.bad': '/nonexistent/filter_exec',
        });

        final state = c.read(processFilterProvider);
        expect(state, contains('top.good'));
        expect(state, isNot(contains('top.bad')));
      },
    );

    test(
      'executablePaths mirrors all active assignments after restore',
      () async {
        final script = await _echoScript();
        final c = _container();
        await c.read(processFilterProvider.notifier).restoreFromSession({
          'top.sig': script,
        });

        expect(
          c.read(processFilterProvider.notifier).executablePaths,
          {'top.sig': script},
        );
      },
    );

    // ── clearAll ──────────────────────────────────────────────────────────────

    test('clearAll resets state to empty', () async {
      final script = await _echoScript();
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.a', script);
      await notifier.setProcessFilter('top.b', script);
      expect(c.read(processFilterProvider).length, 2);

      notifier.clearAll();

      expect(c.read(processFilterProvider), isEmpty);
    });

    test('clearAll clears executablePaths', () async {
      final script = await _echoScript();
      final c = _container();
      final notifier = c.read(processFilterProvider.notifier);

      await notifier.setProcessFilter('top.sig', script);
      expect(notifier.executablePaths, isNotEmpty);

      notifier.clearAll();

      expect(notifier.executablePaths, isEmpty);
    });

    test('clearAll is safe when already empty', () {
      final c = _container();
      expect(
        () => c.read(processFilterProvider.notifier).clearAll(),
        returnsNormally,
      );
      expect(c.read(processFilterProvider), isEmpty);
    });

    test('setProcessFilter returns null on success', () async {
      final script = await _echoScript();
      final c = _container();
      final error = await c
          .read(processFilterProvider.notifier)
          .setProcessFilter('top.sig', script);
      expect(error, isNull);
    });

    test('setProcessFilter returns null for nonexistent executable', () async {
      final c = _container();
      final error = await c
          .read(processFilterProvider.notifier)
          .setProcessFilter('top.sig', '/nonexistent/filter_executable');
      expect(error, isNull);
    });
  });
}
