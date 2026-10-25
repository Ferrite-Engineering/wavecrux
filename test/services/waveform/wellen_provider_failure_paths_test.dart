// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/waveform/wellen_isolate_orchestrator.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

/// Reusable fake-worker plumbing for the provider failure-path tests.
///
/// Unlike the in-isolate FFI worker, this fake lives in the test isolate
/// and lets us trigger timeouts, error responses, and clean-shutdown paths
/// deterministically without touching the wellen native library.
class _FakeWorker {
  /// Function the test installs to react to each message. If it returns a
  /// non-null map, that map is sent back to the orchestrator. Returning
  /// null leaves the request pending — used for timeout tests.
  Map<String, dynamic>? Function(Map<String, dynamic>)? handler;
  final List<Map<String, dynamic>> received = [];
  int killCount = 0;

  /// Every message op and every kill, in the order the fake saw them.
  final List<String> events = [];
  SendPort? _mainPort;
  ReceivePort? _myPort;

  IsolateSpawner get spawner => (mainPort, {debugName}) async {
    _mainPort = mainPort;
    final myPort = ReceivePort();
    _myPort = myPort;
    myPort.listen(_onMessage);
    mainPort.send(myPort.sendPort);
    return IsolateHandle(_onKill);
  };

  void _onMessage(dynamic raw) {
    final msg = (raw as Map).cast<String, dynamic>();
    received.add(msg);
    events.add('op:${msg['op']}');
    final h = handler;
    if (h == null) return;
    final reply = h(msg);
    if (reply != null) _mainPort?.send(reply);
  }

  void _onKill() {
    killCount++;
    events.add('kill');
    _myPort?.close();
    _myPort = null;
  }
}

void main() {
  group('WellenProvider — openFile timeout path', () {
    test(
      'openFile timeout surfaces a TimeoutException and resets state',
      () async {
        final fake = _FakeWorker()..handler = (_) => null; // never respond
        final provider = WellenProvider(
          openTimeout: const Duration(milliseconds: 50),
          spawner: fake.spawner,
        );

        await expectLater(
          provider.openFile('/tmp/never-opens.vcd'),
          throwsA(isA<TimeoutException>()),
        );

        // The orchestrator killed the fake worker.
        expect(fake.killCount, 1);
        // Cached state is reset, ready for a retry.
        expect(provider.rootScopes, isEmpty);
        expect(provider.endTime, 0);
        expect(provider.fileFormat, 'Unknown');

        provider.close();
      },
    );

    test('openFile recovery: a subsequent open with a working worker '
        'succeeds after a prior timeout', () async {
      var calls = 0;
      final fake = _FakeWorker()
        ..handler = (msg) {
          calls++;
          if (calls == 1) return null; // first call hangs → timeout
          // Second call: simulate a successful open response.
          return {
            'id': msg['id'],
            'ok': true,
            'rootScopes': <Object?>[],
            'endTime': 100,
            'timescale': null,
            'date': null,
            'version': null,
            'fileFormat': 'VCD',
            'totalTransitions': 0,
          };
        };

      final provider = WellenProvider(
        openTimeout: const Duration(milliseconds: 50),
        spawner: fake.spawner,
      );

      await expectLater(
        provider.openFile('/tmp/hang.vcd'),
        throwsA(isA<TimeoutException>()),
      );
      // Worker killed.
      expect(fake.killCount, 1);

      // Second attempt — the provider must respawn via _ensureOrchestrator.
      await provider.openFile('/tmp/ok.vcd');
      expect(provider.endTime, 100);
      expect(provider.fileFormat, 'VCD');

      provider.close();
    });
  });

  group('WellenProvider — error-response paths', () {
    test('openFile surfaces ok=false error from worker', () async {
      final fake = _FakeWorker()
        ..handler = (msg) => {
          'id': msg['id'],
          'ok': false,
          'error': 'Parse error at line 42',
        };
      final provider = WellenProvider(spawner: fake.spawner);

      await expectLater(
        provider.openFile('/tmp/bad.vcd'),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('Parse error'),
          ),
        ),
      );

      provider.close();
    });

    test('loadSignal surfaces ok=false error from worker', () async {
      final fake = _FakeWorker()
        ..handler = (msg) {
          final op = msg['op'] as String;
          if (op == 'open') {
            return {
              'id': msg['id'],
              'ok': true,
              'rootScopes': <Object?>[],
              'endTime': 0,
              'timescale': null,
              'date': null,
              'version': null,
              'fileFormat': 'VCD',
              'totalTransitions': 0,
            };
          }
          // loadSignal: report failure.
          return {
            'id': msg['id'],
            'ok': false,
            'error': 'unknown signal ref',
          };
        };

      final provider = WellenProvider(spawner: fake.spawner);
      await provider.openFile('/tmp/x.vcd');
      await expectLater(
        provider.loadSignal('99'),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('unknown signal'),
          ),
        ),
      );

      provider.close();
    });
  });

  group('WellenProvider — guard paths', () {
    test('loadSignal before openFile throws a StateError', () async {
      final fake = _FakeWorker();
      final provider = WellenProvider(spawner: fake.spawner);
      await expectLater(
        provider.loadSignal('0'),
        throwsA(isA<StateError>()),
      );
      provider.close();
    });

    test('unloadSignal before openFile is a silent no-op', () async {
      final fake = _FakeWorker();
      // Pre-populate the cache so the early-return guards line up.
      final provider = WellenProvider(spawner: fake.spawner)
        ..injectLoadedSignal('0', const []);
      await expectLater(provider.unloadSignal('0'), completes);
      provider.close();
    });

    test('memoryUsageBytes before openFile returns 0', () async {
      final fake = _FakeWorker();
      final provider = WellenProvider(spawner: fake.spawner);
      expect(await provider.memoryUsageBytes(), 0);
      provider.close();
    });
  });

  group('WellenProvider — close releases the native handle', () {
    Map<String, dynamic> openReply(Map<String, dynamic> msg) => {
      'id': msg['id'],
      'ok': true,
      'rootScopes': <Object?>[],
      'endTime': 0,
      'timescale': null,
      'date': null,
      'version': null,
      'fileFormat': 'VCD',
      'totalTransitions': 0,
    };

    test('close waits for the worker to process close before killing it '
        '(#53)', () async {
      final fake = _FakeWorker()
        ..handler = (msg) => msg['op'] == 'open'
            ? openReply(msg)
            : {'id': msg['id'], 'ok': true};

      final provider = WellenProvider(spawner: fake.spawner);
      await provider.openFile('/tmp/x.vcd');
      final released = provider.closeAndRelease();

      // Detached synchronously: cached state is gone before the worker
      // has answered, and nothing has been killed yet.
      expect(provider.rootScopes, isEmpty);
      expect(provider.fileFormat, 'Unknown');
      expect(fake.killCount, 0);

      await released;
      // The worker saw close while it was still alive, then was killed.
      expect(fake.events, ['op:open', 'op:close', 'kill']);
    });

    test('close() (the WaveformDataSource path) also delivers close before '
        'the kill', () async {
      final fake = _FakeWorker()
        ..handler = (msg) {
          final op = msg['op'] as String;
          if (op == 'open') return openReply(msg);
          return {'id': msg['id'], 'ok': true};
        };

      final provider = WellenProvider(spawner: fake.spawner);
      await provider.openFile('/tmp/x.vcd');
      provider.close();
      expect(fake.killCount, 0);

      // Let the round trip complete.
      for (var i = 0; i < 20 && fake.killCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(fake.events, ['op:open', 'op:close', 'kill']);
    });

    test('a worker that never acknowledges close is killed anyway', () async {
      final fake = _FakeWorker()
        ..handler = (msg) =>
            msg['op'] == 'open' ? openReply(msg) : null; // close hangs
      final provider = WellenProvider(spawner: fake.spawner);
      await provider.openFile('/tmp/x.vcd');

      final sw = Stopwatch()..start();
      await provider.closeAndRelease();
      sw.stop();

      expect(fake.events, ['op:open', 'op:close', 'kill']);
      expect(
        sw.elapsed,
        greaterThanOrEqualTo(
          WellenIsolateOrchestrator.defaultShutdownTimeout -
              const Duration(milliseconds: 50),
        ),
      );
    });

    test('reopening after close spawns a fresh worker', () async {
      var spawns = 0;
      final fake = _FakeWorker()
        ..handler = (msg) => msg['op'] == 'open'
            ? openReply(msg)
            : {'id': msg['id'], 'ok': true};
      Future<IsolateHandle> countingSpawner(
        SendPort mp, {
        String? debugName,
      }) {
        spawns++;
        return fake.spawner(mp, debugName: debugName);
      }

      final provider = WellenProvider(spawner: countingSpawner);
      await provider.openFile('/tmp/x.vcd');
      provider.close();
      await provider.openFile('/tmp/y.vcd');
      expect(spawns, 2);
      expect(provider.fileFormat, 'VCD');
      await provider.closeAndRelease();
    });

    test('close before openFile is a no-op', () {
      final fake = _FakeWorker();
      // No orchestrator exists yet — close must not throw or kill anything.
      final provider = WellenProvider(spawner: fake.spawner)..close();
      expect(fake.killCount, 0);
      expect(provider.rootScopes, isEmpty);
    });
  });

  group('scaledOpenTimeout — size-aware open watchdog', () {
    test('empty file gets the 30 s base deadline', () {
      expect(
        WellenProvider.scaledOpenTimeout(0),
        WellenProvider.defaultOpenTimeout,
      );
    });

    test('adds one second per megabyte', () {
      // 18 MB (the gate-level netlist that a fixed 5 s deadline rejected).
      expect(
        WellenProvider.scaledOpenTimeout(18 * 1024 * 1024),
        const Duration(seconds: 48),
      );
    });

    test('sub-megabyte remainder does not count', () {
      expect(
        WellenProvider.scaledOpenTimeout(1024 * 1024 - 1),
        WellenProvider.defaultOpenTimeout,
      );
    });

    test('caps at maxOpenTimeout for very large files', () {
      // 4 GB would scale to ~68 min uncapped.
      expect(
        WellenProvider.scaledOpenTimeout(4 * 1024 * 1024 * 1024),
        WellenProvider.maxOpenTimeout,
      );
    });
  });
}
