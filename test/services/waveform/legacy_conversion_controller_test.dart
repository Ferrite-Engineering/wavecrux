// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/services/waveform/legacy_conversion_controller.dart';
import 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

void main() {
  group('LegacyConversionState', () {
    test('idle constant is the no-conversion baseline', () {
      const s = LegacyConversionState.idle;
      expect(s.inProgress, isFalse);
      expect(s.sourcePath, isNull);
      expect(s.origin, isNull);
      expect(s.progress, isNull);
      expect(s.startedAt, isNull);
    });

    test('copyWith updates only the requested fields', () {
      const base = LegacyConversionState.idle;
      final updated = base.copyWith(
        inProgress: true,
        sourcePath: '/tmp/a.lxt2',
        origin: WaveformFormat.lxt2,
      );
      expect(updated.inProgress, isTrue);
      expect(updated.sourcePath, '/tmp/a.lxt2');
      expect(updated.origin, WaveformFormat.lxt2);
      // Untouched fields preserve the prior value.
      expect(updated.progress, isNull);
    });

    test('equality is value-based', () {
      final a = LegacyConversionState(
        inProgress: true,
        sourcePath: '/x.lxt',
        origin: WaveformFormat.lxt,
        progress: const ConversionProgress(done: 1, total: 2),
        startedAt: DateTime.utc(2026),
      );
      final b = LegacyConversionState(
        inProgress: true,
        sourcePath: '/x.lxt',
        origin: WaveformFormat.lxt,
        progress: const ConversionProgress(done: 1, total: 2),
        startedAt: DateTime.utc(2026),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('LegacyConversionController', () {
    test('begin → updateProgress → completeSuccess walks state to idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(
        legacyConversionControllerProvider.notifier,
      );
      expect(
        container.read(legacyConversionControllerProvider),
        LegacyConversionState.idle,
      );

      notifier.begin(
        sourcePath: '/tmp/example.lxt2',
        origin: WaveformFormat.lxt2,
        now: DateTime.utc(2026, 5, 29, 12),
      );

      var state = container.read(legacyConversionControllerProvider);
      expect(state.inProgress, isTrue);
      expect(state.sourcePath, '/tmp/example.lxt2');
      expect(state.origin, WaveformFormat.lxt2);
      expect(state.startedAt, DateTime.utc(2026, 5, 29, 12));
      expect(state.progress, isNull);

      notifier.updateProgress(const ConversionProgress(done: 50, total: 100));
      state = container.read(legacyConversionControllerProvider);
      expect(state.progress?.done, 50);
      expect(state.progress?.total, 100);
      expect(state.progress?.fraction, closeTo(0.5, 1e-9));

      notifier.completeSuccess();
      expect(
        container.read(legacyConversionControllerProvider),
        LegacyConversionState.idle,
      );
    });

    test('updateProgress is a no-op when idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(legacyConversionControllerProvider.notifier)
          .updateProgress(const ConversionProgress(done: 1, total: 1));
      expect(
        container.read(legacyConversionControllerProvider),
        LegacyConversionState.idle,
      );
    });

    test('completeWithError walks state back to idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(legacyConversionControllerProvider.notifier)..begin(
            sourcePath: '/x.lxt',
            origin: WaveformFormat.lxt,
          );
      expect(
        container.read(legacyConversionControllerProvider).inProgress,
        isTrue,
      );

      notifier.completeWithError();
      expect(
        container.read(legacyConversionControllerProvider),
        LegacyConversionState.idle,
      );
    });

    test('cancel() invokes the installed hook and clears state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var hookCalled = 0;
      void hook() {
        hookCalled++;
      }

      final notifier =
          container.read(legacyConversionControllerProvider.notifier)
            ..begin(
              sourcePath: '/x.lxt2',
              origin: WaveformFormat.lxt2,
            )
            ..cancelHook = hook
            ..cancel();
      expect(hookCalled, 1);
      expect(
        container.read(legacyConversionControllerProvider),
        LegacyConversionState.idle,
      );

      // A second cancel after the hook has been cleared is a safe no-op.
      notifier.cancel();
      expect(hookCalled, 1);
    });
  });

  group('LegacyConversionEventSink', () {
    test('emit publishes monotonically increasing sequence numbers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sink = container.read(legacyConversionEventProvider.notifier);
      expect(container.read(legacyConversionEventProvider), isNull);

      sink.emit(
        origin: WaveformFormat.lxt2,
        fstPath: '/tmp/a.fst',
        completedAt: DateTime.utc(2026, 5, 29, 12),
      );
      final e1 = container.read(legacyConversionEventProvider)!;
      expect(e1.origin, WaveformFormat.lxt2);
      expect(e1.fstPath, '/tmp/a.fst');
      expect(e1.sequence, 1);

      sink.emit(
        origin: WaveformFormat.lxt,
        fstPath: '/tmp/b.fst',
      );
      final e2 = container.read(legacyConversionEventProvider)!;
      expect(e2.sequence, 2);
      expect(e2.origin, WaveformFormat.lxt);

      sink.clear();
      expect(container.read(legacyConversionEventProvider), isNull);
    });
  });
}
