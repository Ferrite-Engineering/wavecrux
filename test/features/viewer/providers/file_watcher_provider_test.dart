// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/file_watcher_provider.dart';

// ── State class tests ─────────────────────────────────────────────────────────

void main() {
  group('FileWatchIdle', () {
    test('equality: two instances are equal', () {
      expect(const FileWatchIdle(), const FileWatchIdle());
    });

    test('equality: not equal to FileWatchChanged', () {
      expect(const FileWatchIdle(), isNot(const FileWatchChanged()));
    });

    test('equality: not equal to FileWatchDeleted', () {
      expect(const FileWatchIdle(), isNot(const FileWatchDeleted()));
    });

    test('hashCode is consistent', () {
      expect(const FileWatchIdle().hashCode, const FileWatchIdle().hashCode);
    });

    test('hashCode differs from FileWatchChanged', () {
      expect(
        const FileWatchIdle().hashCode,
        isNot(const FileWatchChanged().hashCode),
      );
    });
  });

  group('FileWatchChanged', () {
    test('equality: two instances are equal', () {
      expect(const FileWatchChanged(), const FileWatchChanged());
    });

    test('equality: not equal to FileWatchIdle', () {
      expect(const FileWatchChanged(), isNot(const FileWatchIdle()));
    });

    test('equality: not equal to FileWatchDeleted', () {
      expect(const FileWatchChanged(), isNot(const FileWatchDeleted()));
    });

    test('hashCode is consistent', () {
      expect(
        const FileWatchChanged().hashCode,
        const FileWatchChanged().hashCode,
      );
    });
  });

  group('FileWatchDeleted', () {
    test('equality: two instances are equal', () {
      expect(const FileWatchDeleted(), const FileWatchDeleted());
    });

    test('equality: not equal to FileWatchIdle', () {
      expect(const FileWatchDeleted(), isNot(const FileWatchIdle()));
    });

    test('equality: not equal to FileWatchChanged', () {
      expect(const FileWatchDeleted(), isNot(const FileWatchChanged()));
    });

    test('hashCode is consistent', () {
      expect(
        const FileWatchDeleted().hashCode,
        const FileWatchDeleted().hashCode,
      );
    });
  });

  group('FileWatcherNotifier', () {
    test('initial state is FileWatchIdle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(fileWatcherProvider);
      expect(state, isA<FileWatchIdle>());
    });

    test('dismiss() sets state to FileWatchIdle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Read to initialize the notifier.
      container.read(fileWatcherProvider);
      container.read(fileWatcherProvider.notifier).dismiss();

      expect(container.read(fileWatcherProvider), isA<FileWatchIdle>());
    });

    test('dismiss() is idempotent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(fileWatcherProvider);
      container.read(fileWatcherProvider.notifier)
        ..dismiss()
        ..dismiss();

      expect(container.read(fileWatcherProvider), isA<FileWatchIdle>());
    });

    test('state is sealed — exhaustive switch compiles', () {
      const FileWatchState state = FileWatchIdle();
      final label = switch (state) {
        FileWatchIdle() => 'idle',
        FileWatchChanged() => 'changed',
        FileWatchDeleted() => 'deleted',
      };
      expect(label, 'idle');
    });
  });
}
