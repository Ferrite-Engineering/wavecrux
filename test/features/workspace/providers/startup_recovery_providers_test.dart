// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/workspace/providers/startup_recovery_providers.dart';

void main() {
  group('startupRecoveryProvider', () {
    test('defaults to a normal launch (none, not suppressed)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(startupRecoveryProvider);
      expect(state.reason, StartupRecoveryReason.none);
      expect(state.suppressAutoLoad, isFalse);
    });

    test('configure records the recovery posture', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(startupRecoveryProvider.notifier)
          .configure(
            const StartupRecoveryState(
              reason: StartupRecoveryReason.interrupted,
              suppressAutoLoad: true,
            ),
          );
      final state = container.read(startupRecoveryProvider);
      expect(state.reason, StartupRecoveryReason.interrupted);
      expect(state.suppressAutoLoad, isTrue);
    });
  });

  group('startupRestoreResumeProvider', () {
    test('canResume is false until a handler is registered', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(startupRestoreResumeProvider), isFalse);
    });

    test('registerResume flips canResume to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(startupRestoreResumeProvider.notifier)
          .registerResume(() {});
      expect(container.read(startupRestoreResumeProvider), isTrue);
    });

    test('resume invokes the handler once and collapses the action', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var calls = 0;
      final notifier = container.read(startupRestoreResumeProvider.notifier)
        ..registerResume(() => calls++)
        ..resume();
      expect(calls, 1);
      expect(container.read(startupRestoreResumeProvider), isFalse);

      // Idempotent: a second resume does nothing (handler consumed).
      notifier.resume();
      expect(calls, 1);
    });
  });
}
