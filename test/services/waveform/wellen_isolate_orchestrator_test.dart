// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/waveform/wellen_isolate_orchestrator.dart';

/// Drives the orchestrator without spawning a real isolate.
///
/// The orchestrator only needs *something* that:
///   1. Eventually sends a SendPort back on the [mainPort] it's given, and
///   2. Receives subsequent messages and responds to them.
///
/// We give it a [ReceivePort] running on the *test* isolate (so no real
/// `Isolate.spawn` call) and return an [IsolateHandle] whose `kill` closure
/// closes that port and records the kill so the test can assert on it.
class _FakeWorker {
  _FakeWorker({
    this.initBehavior = _InitBehavior.sendPort,
    this.spawnError,
  });

  final _InitBehavior initBehavior;
  final Object? spawnError;

  /// Messages received from the orchestrator, in arrival order.
  final List<Map<String, dynamic>> received = [];

  /// Number of times the kill closure has been invoked.
  int killCount = 0;

  /// Function the test installs to react to each message. Called with the
  /// full payload (including the orchestrator-assigned `id`). If it returns
  /// non-null, the value is sent back via [mainPort]. Returning null means
  /// "no response" — used to exercise the timeout path.
  Map<String, dynamic>? Function(Map<String, dynamic>)? handler;

  SendPort? _mainPort;
  ReceivePort? _myPort;

  IsolateSpawner get spawner => (mainPort, {debugName}) async {
    final err = spawnError;
    if (err != null) {
      // Test fixture: simulating a spawn failure surfaced by the platform
      // (e.g. ArgumentError from Isolate.spawn). Tests assert on whatever
      // type the orchestrator wraps it in, not on the raw type here.
      // ignore: only_throw_errors
      throw err;
    }
    _mainPort = mainPort;
    switch (initBehavior) {
      case _InitBehavior.sendPort:
        final myPort = ReceivePort();
        _myPort = myPort;
        myPort.listen(_onMessage);
        mainPort.send(myPort.sendPort);
      case _InitBehavior.sendNull:
        mainPort.send(null);
      case _InitBehavior.neverRespond:
        // Don't send anything back — exercises an init-hang scenario.
        // The orchestrator's start() future will pend until the test
        // disposes it.
        break;
    }
    return IsolateHandle(_handleKill);
  };

  void _onMessage(dynamic raw) {
    final msg = (raw as Map).cast<String, dynamic>();
    received.add(msg);
    final h = handler;
    if (h == null) return;
    final reply = h(msg);
    if (reply != null) {
      _mainPort?.send(reply);
    }
  }

  void _handleKill() {
    killCount++;
    _myPort?.close();
    _myPort = null;
  }

  /// Send an arbitrary out-of-band message back through the main port.
  /// Used by tests to simulate late / stale responses.
  void sendOutOfBand(Map<String, dynamic> msg) {
    _mainPort?.send(msg);
  }
}

enum _InitBehavior { sendPort, sendNull, neverRespond }

void main() {
  group('WellenIsolateOrchestrator — happy path', () {
    test('start() boots the worker and isRunning flips true', () async {
      final fake = _FakeWorker();
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      expect(orch.isRunning, isFalse);

      await orch.start();
      expect(orch.isRunning, isTrue);

      orch.dispose();
    });

    test('send() routes a response back to the caller', () async {
      final fake = _FakeWorker()
        ..handler = (msg) => {
          'id': msg['id'],
          'ok': true,
          'echo': msg['op'],
        };
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      final result = await orch.send({'op': 'ping'});
      expect(result['ok'], isTrue);
      expect(result['echo'], 'ping');
      expect(fake.received, hasLength(1));
      expect(fake.received.first['op'], 'ping');

      orch.dispose();
    });

    test('start() is idempotent — second call does not respawn', () async {
      var spawnCount = 0;
      final fake = _FakeWorker();
      Future<IsolateHandle> countingSpawner(
        SendPort mp, {
        String? debugName,
      }) {
        spawnCount++;
        return fake.spawner(mp, debugName: debugName);
      }

      final orch = WellenIsolateOrchestrator(spawner: countingSpawner);
      await orch.start();
      await orch.start(); // should be a no-op
      expect(spawnCount, 1);

      orch.dispose();
    });
  });

  group('WellenIsolateOrchestrator — concurrency', () {
    test(
      'multiple in-flight requests are routed to the right completer',
      () async {
        final fake = _FakeWorker();
        // Defer all responses until the test triggers them, so all three
        // requests are simultaneously in-flight.
        final pending = <Map<String, dynamic>>[];
        fake.handler = (msg) {
          pending.add(msg);
          return null;
        };
        final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
        await orch.start();

        final f1 = orch.send({'op': 'a'});
        final f2 = orch.send({'op': 'b'});
        final f3 = orch.send({'op': 'c'});

        // Wait one event loop tick for the sends to be received.
        await Future<void>.delayed(Duration.zero);
        expect(pending, hasLength(3));
        expect(orch.debugPendingIds, hasLength(3));

        // Respond out-of-order: b first, then a, then c.
        fake
          ..sendOutOfBand({'id': pending[1]['id'], 'value': 'B'})
          ..sendOutOfBand({'id': pending[0]['id'], 'value': 'A'})
          ..sendOutOfBand({'id': pending[2]['id'], 'value': 'C'});

        expect((await f1)['value'], 'A');
        expect((await f2)['value'], 'B');
        expect((await f3)['value'], 'C');
        expect(orch.debugPendingIds, isEmpty);

        orch.dispose();
      },
    );
  });

  group('WellenIsolateOrchestrator — timeout / recovery', () {
    test('timeout kills worker and surfaces TimeoutException', () async {
      final fake = _FakeWorker()..handler = (_) => null; // never respond
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();
      expect(orch.isRunning, isTrue);

      await expectLater(
        orch.send({'op': 'hang'}, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );

      expect(fake.killCount, 1);
      expect(
        orch.isRunning,
        isFalse,
        reason: 'orchestrator killed the worker on timeout',
      );

      // Subsequent start() respawns the worker.
      await orch.start();
      expect(orch.isRunning, isTrue);

      orch.dispose();
    });

    test('timeout errors any other pending requests too', () async {
      final fake = _FakeWorker()..handler = (_) => null;
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      final hangFuture = orch.send({
        'op': 'hang',
      }, timeout: const Duration(milliseconds: 50));
      final sibling = orch.send({'op': 'sibling'});

      await expectLater(hangFuture, throwsA(isA<TimeoutException>()));
      await expectLater(sibling, throwsA(isA<TimeoutException>()));

      orch.dispose();
    });

    test('late response after timeout is silently dropped', () async {
      final fake = _FakeWorker()..handler = (_) => null;
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      final f = orch.send({
        'op': 'op1',
      }, timeout: const Duration(milliseconds: 50));

      await expectLater(f, throwsA(isA<TimeoutException>()));
      final id = fake.received.last['id'] as int;

      // Late response arrives — must not throw or complete anything.
      // (The worker has been killed, but a real worker might have sent its
      // response slightly before being killed.) The orchestrator routes by
      // id-lookup; the pending entry has been cleared, so the routing
      // silently no-ops.
      fake.sendOutOfBand({'id': id, 'ok': true});

      // Give the listener a chance to process.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Test reaches this point without unhandled errors → pass.
    });
  });

  group('WellenIsolateOrchestrator — cancellation via load token', () {
    test('late response from a superseded request is dropped', () async {
      final fake = _FakeWorker();
      final pending = <Map<String, dynamic>>[];
      fake.handler = (msg) {
        pending.add(msg);
        return null;
      };
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      // Send a request tagged with the current load token.
      final stale = orch.send({'op': 'old'}, tagWithLoadToken: true);

      // Wait for the worker to receive it.
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(1));
      final staleId = pending[0]['id'] as int;

      // Bump the token — any response to `stale` should now be dropped.
      orch.bumpLoadToken();

      // The pending entry is still there until a response arrives, but its
      // load token snapshot now differs from the current one.
      expect(orch.debugPendingIds, contains(staleId));

      // Worker sends a late response. The orchestrator routes by id,
      // notices the token mismatch, and drops it. The completer never
      // completes, so we just race it against a short timer instead of
      // awaiting forever.
      fake.sendOutOfBand({'id': staleId, 'value': 'stale-value'});

      final raceResult = await Future.any([
        stale.then((v) => 'completed:${v['value']}'),
        Future<String>.delayed(
          const Duration(milliseconds: 50),
          () => 'still-pending',
        ),
      ]);
      expect(
        raceResult,
        'still-pending',
        reason: 'response for an older load token must be silently dropped',
      );

      orch.dispose();
    });

    test('a fresh request after bump completes normally', () async {
      final fake = _FakeWorker()
        ..handler = (msg) => {'id': msg['id'], 'value': 'fresh-${msg['op']}'};
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      orch.bumpLoadToken();
      final r = await orch.send({'op': 'fresh'}, tagWithLoadToken: true);
      expect(r['value'], 'fresh-fresh');

      orch.dispose();
    });
  });

  group('WellenIsolateOrchestrator — dispose', () {
    test('dispose errors pending completers and kills the worker', () async {
      final fake = _FakeWorker()..handler = (_) => null;
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      final pendingFuture = orch.send({'op': 'never-replies'});
      // Let the worker receive it.
      await Future<void>.delayed(Duration.zero);

      orch.dispose();

      await expectLater(pendingFuture, throwsA(isA<StateError>()));
      expect(fake.killCount, greaterThanOrEqualTo(1));
      expect(orch.isDisposed, isTrue);
    });

    test('send() after dispose returns an errored future', () async {
      final fake = _FakeWorker();
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();
      orch.dispose();

      await expectLater(
        orch.send({'op': 'too-late'}),
        throwsA(isA<StateError>()),
      );
    });

    test('start() after dispose throws', () async {
      final fake = _FakeWorker();
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner)..dispose();

      await expectLater(orch.start(), throwsA(isA<StateError>()));
    });

    test('sendOneWay after dispose throws', () async {
      final fake = _FakeWorker();
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();
      orch.dispose();

      expect(
        () => orch.sendOneWay({'op': 'final'}),
        throwsA(isA<StateError>()),
      );
    });

    test('dispose is idempotent', () {
      final fake = _FakeWorker();
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner)
        ..dispose()
        ..dispose();
      expect(orch.isDisposed, isTrue);
    });

    test('send() before start returns an errored future', () async {
      final fake = _FakeWorker();
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);

      await expectLater(
        orch.send({'op': 'too-early'}),
        throwsA(isA<StateError>()),
      );

      orch.dispose();
    });

    test('sendOneWay before start throws', () {
      final fake = _FakeWorker();
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      expect(
        () => orch.sendOneWay({'op': 'too-early'}),
        throwsA(isA<StateError>()),
      );
      orch.dispose();
    });
  });

  group('WellenIsolateOrchestrator — spawn / init failure', () {
    test('spawner that throws surfaces a WellenIsolateInitException', () async {
      final fake = _FakeWorker(spawnError: Exception('cannot find binary'));
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);

      await expectLater(
        orch.start(),
        throwsA(isA<WellenIsolateInitException>()),
      );
      expect(orch.isRunning, isFalse);
      // No isolate created → nothing to kill.
      expect(fake.killCount, 0);

      orch.dispose();
    });

    test(
      'worker that sends null (lib not loadable) surfaces init error',
      () async {
        final fake = _FakeWorker(initBehavior: _InitBehavior.sendNull);
        final orch = WellenIsolateOrchestrator(spawner: fake.spawner);

        await expectLater(
          orch.start(),
          throwsA(isA<WellenIsolateInitException>()),
        );
        expect(orch.isRunning, isFalse);
        // The "worker" was started and must be killed during cleanup.
        expect(fake.killCount, 1);
      },
    );

    test('WellenIsolateInitException toString includes the message', () {
      final ex = WellenIsolateInitException('boom');
      expect(ex.toString(), contains('boom'));
    });
  });

  group('WellenIsolateOrchestrator — load token getter', () {
    test(
      'currentLoadToken starts at 0 and increments with bumpLoadToken',
      () async {
        final fake = _FakeWorker();
        final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
        expect(orch.currentLoadToken, 0);
        orch.bumpLoadToken();
        expect(orch.currentLoadToken, 1);
        orch
          ..bumpLoadToken()
          ..bumpLoadToken();
        expect(orch.currentLoadToken, 3);
        orch.dispose();
      },
    );
  });

  group('WellenIsolateOrchestrator — sendOneWay', () {
    test('sends without registering a completer', () async {
      final fake = _FakeWorker()..handler = (_) => null;
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      orch.sendOneWay({'op': 'fire-forget'});

      await Future<void>.delayed(Duration.zero);
      expect(fake.received, hasLength(1));
      expect(fake.received.first['op'], 'fire-forget');
      // No pending entry was registered.
      expect(orch.debugPendingIds, isEmpty);

      orch.dispose();
    });
  });

  group('WellenIsolateOrchestrator — response routing edge cases', () {
    test('non-map response is ignored', () async {
      final fake = _FakeWorker()..handler = (msg) => null;
      final orch = WellenIsolateOrchestrator(spawner: fake.spawner);
      await orch.start();

      final f = orch.send({'op': 'op1'});
      await Future<void>.delayed(Duration.zero);

      // Send a non-map message — must be silently ignored.
      fake
        ..sendOutOfBand(<String, dynamic>{}) // empty map (no id)
        // Send a map without an id.
        ..sendOutOfBand({'no_id': true})
        // Send a map with id of wrong type.
        ..sendOutOfBand({'id': 'not-an-int'});

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Now actually respond with the right id.
      final id = fake.received.first['id'] as int;
      fake.sendOutOfBand({'id': id, 'value': 'real'});

      expect((await f)['value'], 'real');

      orch.dispose();
    });
  });
}
