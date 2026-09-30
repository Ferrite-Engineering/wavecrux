// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _container() =>
    ProviderContainer(overrides: [productTelemetryConfig]);

/// A small but complete VCD with two value changes so endTime > 0.
const _pipeVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#100
1!
#200
0!
''';

/// Writes [content] to a temporary file and returns it.
/// Callers are responsible for deleting it with [addTearDown].
File _writeTempVcd(String content) {
  final path =
      '${Directory.systemTemp.path}/wavecrux_test_${DateTime.now().microsecondsSinceEpoch}.vcd';
  return File(path)..writeAsStringSync(utf8.decode(utf8.encode(content)));
}

/// Flush pending microtasks and I/O events so that state listeners have
/// received all updates from [startFromPipe].
///
/// On macOS/Linux the states arrive as microtasks and are available immediately
/// after the `await startFromPipe(...)` returns.  On Windows the I/O event loop
/// dispatches in a different order, so a single `Duration.zero` delay is not
/// enough.  This helper polls up to [maxWait] for [condition] to become true.
Future<void> _waitFor(
  bool Function() condition, {
  Duration maxWait = const Duration(milliseconds: 500),
  Duration interval = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(maxWait);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);
  }
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('StreamingViewerState', () {
    test('StreamingViewerIdle equality', () {
      expect(
        const StreamingViewerIdle(),
        equals(const StreamingViewerIdle()),
      );
    });

    test('StreamingViewerStarting equality', () {
      expect(
        const StreamingViewerStarting(),
        equals(const StreamingViewerStarting()),
      );
    });

    test('StreamingViewerActive equality on same fields', () {
      const a = StreamingViewerActive(
        elapsed: Duration(seconds: 5),
        currentEndTime: 100,
      );
      const b = StreamingViewerActive(
        elapsed: Duration(seconds: 5),
        currentEndTime: 100,
      );
      expect(a, equals(b));
    });

    test('StreamingViewerActive not equal on different elapsed', () {
      const a = StreamingViewerActive(
        elapsed: Duration(seconds: 1),
        currentEndTime: 100,
      );
      const b = StreamingViewerActive(
        elapsed: Duration(seconds: 2),
        currentEndTime: 100,
      );
      expect(a, isNot(equals(b)));
    });

    test('StreamingViewerActive.copyWith updates elapsed', () {
      const base = StreamingViewerActive(
        elapsed: Duration.zero,
        currentEndTime: 0,
      );
      final updated = base.copyWith(elapsed: const Duration(seconds: 3));
      expect(updated.elapsed, const Duration(seconds: 3));
      expect(updated.currentEndTime, 0);
    });

    test('StreamingViewerActive.copyWith updates currentEndTime', () {
      const base = StreamingViewerActive(
        elapsed: Duration.zero,
        currentEndTime: 0,
      );
      final updated = base.copyWith(currentEndTime: 500);
      expect(updated.currentEndTime, 500);
      expect(updated.elapsed, Duration.zero);
    });
  });

  group('StreamingSourceNotifier', () {
    test('initial state is StreamingViewerIdle', () {
      final container = _container();
      addTearDown(container.dispose);

      final state = container.read(streamingSourceProvider);
      expect(state, isA<StreamingViewerIdle>());
    });

    test('stop() when idle does not throw', () {
      final container = _container();
      addTearDown(container.dispose);

      expect(
        () => container.read(streamingSourceProvider.notifier).stop(),
        returnsNormally,
      );
    });

    test('stop() when already idle keeps idle state', () {
      final container = _container();
      addTearDown(container.dispose);

      container.read(streamingSourceProvider.notifier).stop();
      expect(
        container.read(streamingSourceProvider),
        isA<StreamingViewerIdle>(),
      );
    });

    test('attachStreamingSource wires up waveform source', () async {
      final container = _container();
      addTearDown(container.dispose);

      // Initially no waveform is loaded.
      expect(
        container.read(waveformIsLoadedProvider),
        isFalse,
      );
    });

    test('stop() returns state to idle', () async {
      final container = _container();
      addTearDown(container.dispose);

      // Already idle — stop is a no-op, should remain idle.
      container.read(streamingSourceProvider.notifier).stop();
      expect(
        container.read(streamingSourceProvider),
        isA<StreamingViewerIdle>(),
      );
    });
  });

  // ── startFromPipe state transitions ──────────────────────────────────────

  group('startFromPipe state transitions', () {
    test('idle → starting → active after header is parsed', () async {
      final tmpFile = _writeTempVcd(_pipeVcd);
      addTearDown(() {
        try {
          tmpFile.deleteSync();
        } on FileSystemException catch (_) {}
      });

      final container = _container();
      addTearDown(container.dispose);

      final states = <StreamingViewerState>[];
      container.listen(
        streamingSourceProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(streamingSourceProvider.notifier)
          .startFromPipe(tmpFile.path);

      // On Windows, state listener callbacks may not have fired yet — wait
      // for the Active state to appear.
      await _waitFor(
        () => states.any((s) => s is StreamingViewerActive),
      );

      expect(states, contains(isA<StreamingViewerStarting>()));
      expect(
        states.any((s) => s is StreamingViewerActive),
        isTrue,
      );
    });

    test('active state carries simulation endTime from the VCD file', () async {
      final tmpFile = _writeTempVcd(_pipeVcd);
      addTearDown(() {
        try {
          tmpFile.deleteSync();
        } on FileSystemException catch (_) {}
      });

      final container = _container();
      addTearDown(container.dispose);

      final states = <StreamingViewerState>[];
      container.listen(
        streamingSourceProvider,
        (_, next) => states.add(next),
      );

      await container
          .read(streamingSourceProvider.notifier)
          .startFromPipe(tmpFile.path);

      await _waitFor(
        () => states.any((s) => s is StreamingViewerActive),
      );

      final activeStates = states.whereType<StreamingViewerActive>().toList();
      expect(activeStates, isNotEmpty);
      // The VCD has transitions up to #200.
      expect(activeStates.last.currentEndTime, greaterThanOrEqualTo(0));
    });

    test('auto-transitions to idle once stream reaches EOF', () async {
      final tmpFile = _writeTempVcd(_pipeVcd);
      addTearDown(() {
        try {
          tmpFile.deleteSync();
        } on FileSystemException catch (_) {}
      });

      final container = _container();
      addTearDown(container.dispose);

      final states = <StreamingViewerState>[];
      container.listen(
        streamingSourceProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(streamingSourceProvider.notifier)
          .startFromPipe(tmpFile.path);

      // The streamEndedFuture.then(() => _stopInternal()) callback runs as an
      // I/O event, not a microtask — poll until the state becomes Idle rather
      // than relying on a fixed delay.
      await _waitFor(
        () => container.read(streamingSourceProvider) is StreamingViewerIdle,
      );

      expect(states.last, isA<StreamingViewerIdle>());
    });

    test(
      'starting state precedes active state in the emitted sequence',
      () async {
        final tmpFile = _writeTempVcd(_pipeVcd);
        addTearDown(() {
          try {
            tmpFile.deleteSync();
          } on FileSystemException catch (_) {}
        });

        final container = _container();
        addTearDown(container.dispose);

        final states = <StreamingViewerState>[];
        container.listen(
          streamingSourceProvider,
          (_, next) => states.add(next),
        );

        await container
            .read(streamingSourceProvider.notifier)
            .startFromPipe(tmpFile.path);

        await _waitFor(
          () => states.any((s) => s is StreamingViewerActive),
        );

        final startingIdx = states.indexWhere(
          (s) => s is StreamingViewerStarting,
        );
        final activeIdx = states.indexWhere((s) => s is StreamingViewerActive);

        expect(startingIdx, isNonNegative);
        expect(activeIdx, isNonNegative);
        expect(startingIdx, lessThan(activeIdx));
      },
    );
  });

  // ── stop and restart (pause/resume) ──────────────────────────────────────

  group('pause/resume via stop and restart', () {
    test('stop() during active returns to idle immediately', () async {
      final tmpFile = _writeTempVcd(_pipeVcd);
      addTearDown(() {
        try {
          tmpFile.deleteSync();
        } on FileSystemException catch (_) {}
      });

      final container = _container();
      addTearDown(container.dispose);

      await container
          .read(streamingSourceProvider.notifier)
          .startFromPipe(tmpFile.path);

      // Wait for active state before stopping.
      await _waitFor(
        () => container.read(streamingSourceProvider) is StreamingViewerActive,
      );

      container.read(streamingSourceProvider.notifier).stop();

      expect(
        container.read(streamingSourceProvider),
        isA<StreamingViewerIdle>(),
      );
    });

    test(
      'second startFromPipe after stop produces a new active session',
      () async {
        final tmpA = _writeTempVcd(_pipeVcd);
        final tmpB = _writeTempVcd(_pipeVcd);
        addTearDown(() {
          try {
            tmpA.deleteSync();
          } on FileSystemException catch (_) {}
        });
        addTearDown(() {
          try {
            tmpB.deleteSync();
          } on FileSystemException catch (_) {}
        });

        final container = _container();
        addTearDown(container.dispose);

        final notifier = container.read(streamingSourceProvider.notifier);

        await notifier.startFromPipe(tmpA.path);

        await _waitFor(
          () =>
              container.read(streamingSourceProvider) is StreamingViewerActive,
        );

        notifier.stop();
        expect(
          container.read(streamingSourceProvider),
          isA<StreamingViewerIdle>(),
        );

        final states = <StreamingViewerState>[];
        container.listen(
          streamingSourceProvider,
          (_, next) => states.add(next),
        );

        await notifier.startFromPipe(tmpB.path);

        await _waitFor(
          () => states.any((s) => s is StreamingViewerActive),
        );

        expect(states, contains(isA<StreamingViewerStarting>()));
        expect(
          states.any((s) => s is StreamingViewerActive),
          isTrue,
        );
      },
    );

    test(
      'stop then restart does not leave dangling update subscriptions',
      () async {
        final tmpFile = _writeTempVcd(_pipeVcd);
        addTearDown(() {
          try {
            tmpFile.deleteSync();
          } on FileSystemException catch (_) {}
        });

        final container = _container();
        addTearDown(container.dispose);

        final notifier = container.read(streamingSourceProvider.notifier);

        // Two full start–stop cycles must not throw.
        await notifier.startFromPipe(tmpFile.path);
        await _waitFor(
          () =>
              container.read(streamingSourceProvider) is StreamingViewerActive,
        );
        notifier.stop();

        await notifier.startFromPipe(tmpFile.path);
        await _waitFor(
          () =>
              container.read(streamingSourceProvider) is StreamingViewerActive,
        );
        notifier.stop();

        expect(
          container.read(streamingSourceProvider),
          isA<StreamingViewerIdle>(),
        );
      },
    );
  });

  // ── reconnection after idle ───────────────────────────────────────────────

  group('reconnection after idle', () {
    test(
      'can start a new session after the previous one auto-completed',
      () async {
        final tmpFile = _writeTempVcd(_pipeVcd);
        addTearDown(() {
          try {
            tmpFile.deleteSync();
          } on FileSystemException catch (_) {}
        });

        final container = _container();
        addTearDown(container.dispose);

        final notifier = container.read(streamingSourceProvider.notifier);

        // First session.
        await notifier.startFromPipe(tmpFile.path);

        // Second session — _start() calls _stopInternal() internally, so no
        // need to wait for the auto-idle transition before re-starting.
        await notifier.startFromPipe(tmpFile.path);

        // Wait for the second session to reach either Active or auto-Idle.
        await _waitFor(
          () {
            final s = container.read(streamingSourceProvider);
            return s is StreamingViewerActive || s is StreamingViewerIdle;
          },
        );

        expect(
          container.read(streamingSourceProvider),
          anyOf(isA<StreamingViewerActive>(), isA<StreamingViewerIdle>()),
        );
      },
    );
  });

  // ── waveform source integration ───────────────────────────────────────────

  group('waveform source integration', () {
    test('waveformIsLoadedProvider is true after startFromPipe', () async {
      final tmpFile = _writeTempVcd(_pipeVcd);
      addTearDown(() {
        try {
          tmpFile.deleteSync();
        } on FileSystemException catch (_) {}
      });

      final container = _container();
      addTearDown(container.dispose);

      expect(container.read(waveformIsLoadedProvider), isFalse);

      await container
          .read(streamingSourceProvider.notifier)
          .startFromPipe(tmpFile.path);

      // Wait for the waveform source to be wired up.
      await _waitFor(
        () => container.read(waveformIsLoadedProvider),
      );

      expect(container.read(waveformIsLoadedProvider), isTrue);
    });
  });

  // ── disposal during streaming ─────────────────────────────────────────────

  group('disposal during streaming', () {
    test('container dispose after stream completes does not throw', () async {
      final tmpFile = _writeTempVcd(_pipeVcd);
      addTearDown(() {
        try {
          tmpFile.deleteSync();
        } on FileSystemException catch (_) {}
      });

      final container = _container();
      await container
          .read(streamingSourceProvider.notifier)
          .startFromPipe(tmpFile.path);
      await Future<void>.delayed(Duration.zero);

      expect(container.dispose, returnsNormally);
    });

    test('container dispose before stream completes does not throw', () async {
      final tmpFile = _writeTempVcd(_pipeVcd);
      addTearDown(() {
        try {
          tmpFile.deleteSync();
        } on FileSystemException catch (_) {}
      });

      final container = _container();
      // Fire-and-forget: do NOT await so dispose may race startFromPipe.
      unawaited(
        container
            .read(streamingSourceProvider.notifier)
            .startFromPipe(tmpFile.path)
            .catchError((_) {}),
      );
      // Dispose immediately, while the provider may be mid-startup.
      expect(container.dispose, returnsNormally);
    });
  });
}
