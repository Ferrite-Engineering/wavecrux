// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/landscape_hint_provider.dart';

void main() {
  group('LandscapeHintNotifier', () {
    test('initial state allows the hint to show', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(landscapeHintProvider), isTrue);
      expect(
        container.read(landscapeHintProvider.notifier).shouldShow,
        isTrue,
      );
    });

    test('markShown suppresses the hint for the rest of the session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(landscapeHintProvider.notifier).markShown();

      expect(container.read(landscapeHintProvider), isFalse);
      expect(
        container.read(landscapeHintProvider.notifier).shouldShow,
        isFalse,
      );
    });

    test('dismiss suppresses the hint for the rest of the session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(landscapeHintProvider.notifier).dismiss();

      expect(
        container.read(landscapeHintProvider.notifier).shouldShow,
        isFalse,
      );
    });

    test('markShown is idempotent (multiple calls do not toggle back)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(landscapeHintProvider.notifier)
        ..markShown()
        ..markShown()
        ..markShown();

      expect(notifier.shouldShow, isFalse);
    });

    test('keepAlive: notifier survives across reads in same container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(landscapeHintProvider.notifier).markShown();
      // A subsequent read should observe the markShown effect because the
      // provider is kept alive.
      expect(container.read(landscapeHintProvider), isFalse);
    });

    test('dismiss after markShown stays suppressed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(landscapeHintProvider.notifier)
        ..markShown()
        ..dismiss();

      expect(notifier.shouldShow, isFalse);
    });
  });
}
