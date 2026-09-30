// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/collaboration/providers/follow_detached_provider.dart';

void main() {
  group('followDetachedProvider', () {
    test('defaults to attached (following)', () {
      final container = ProviderContainer(
        overrides: [followDetachIdleTimeoutProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      expect(container.read(followDetachedProvider), isFalse);
    });

    test('detach() sets, resume() clears', () {
      final container = ProviderContainer(
        overrides: [followDetachIdleTimeoutProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(followDetachedProvider.notifier)
        ..detach();
      expect(container.read(followDetachedProvider), isTrue);

      notifier.resume();
      expect(container.read(followDetachedProvider), isFalse);
    });

    test('detach() is idempotent for the boolean state', () {
      final container = ProviderContainer(
        overrides: [followDetachIdleTimeoutProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      container.read(followDetachedProvider.notifier)
        ..detach()
        ..detach();
      expect(container.read(followDetachedProvider), isTrue);
    });

    test('idle timeout auto-resumes after the configured window', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            followDetachIdleTimeoutProvider.overrideWithValue(
              const Duration(seconds: 2),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(followDetachedProvider.notifier).detach();
        expect(container.read(followDetachedProvider), isTrue);

        // Still detached just before the window elapses …
        async.elapse(const Duration(milliseconds: 1500));
        expect(container.read(followDetachedProvider), isTrue);

        // … auto-resumes once the idle window passes.
        async.elapse(const Duration(milliseconds: 600));
        expect(container.read(followDetachedProvider), isFalse);
      });
    });

    test(
      'continued navigation restarts the idle timer (no premature resume)',
      () {
        fakeAsync((async) {
          final container = ProviderContainer(
            overrides: [
              followDetachIdleTimeoutProvider.overrideWithValue(
                const Duration(seconds: 2),
              ),
            ],
          );
          addTearDown(container.dispose);
          final notifier = container.read(followDetachedProvider.notifier)
            ..detach();
          async.elapse(const Duration(milliseconds: 1800));
          // A fresh gesture before the window elapses restarts the timer.
          notifier.detach();
          async.elapse(const Duration(milliseconds: 1800));
          // 3.6 s total elapsed, but only 1.8 s since the last detach → still
          // detached.
          expect(container.read(followDetachedProvider), isTrue);

          async.elapse(const Duration(milliseconds: 400));
          expect(container.read(followDetachedProvider), isFalse);
        });
      },
    );

    test('a null timeout disables auto-resume entirely', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [followDetachIdleTimeoutProvider.overrideWithValue(null)],
        );
        addTearDown(container.dispose);

        container.read(followDetachedProvider.notifier).detach();
        async.elapse(const Duration(minutes: 5));
        expect(container.read(followDetachedProvider), isTrue);
      });
    });
  });
}
