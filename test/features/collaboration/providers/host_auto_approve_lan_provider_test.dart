// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/collaboration/providers/host_auto_approve_lan_provider.dart';

void main() {
  group('hostAutoApproveLanProvider', () {
    test('defaults to OFF — every joiner waits for a decision', () {
      // The fail-safe direction for an admission control, and the reason this
      // seam is in-memory only: a fresh container is a fresh app start, and a
      // host who relaxed the policy three weeks ago on a lab bench should not
      // still be relaxing it on a hotel network.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(hostAutoApproveLanProvider), isFalse);
    });

    test('set(true) enables auto-admit, set(false) restores the prompt', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(hostAutoApproveLanProvider.notifier)
        ..set(true);
      expect(container.read(hostAutoApproveLanProvider), isTrue);

      notifier.set(false);
      expect(container.read(hostAutoApproveLanProvider), isFalse);
    });

    test('toggle() flips the policy', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(hostAutoApproveLanProvider.notifier)
        ..toggle();
      expect(container.read(hostAutoApproveLanProvider), isTrue);

      notifier.toggle();
      expect(container.read(hostAutoApproveLanProvider), isFalse);
    });
  });
}
