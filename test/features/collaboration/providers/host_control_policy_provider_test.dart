// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/collaboration/providers/host_control_policy_provider.dart';

void main() {
  group('hostControlPolicyProvider', () {
    test('defaults to allowing participants to request control', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(hostControlPolicyProvider), isTrue);
    });

    test('set(false) disables request-control, set(true) re-enables', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(hostControlPolicyProvider.notifier)
        ..set(false);
      expect(container.read(hostControlPolicyProvider), isFalse);

      notifier.set(true);
      expect(container.read(hostControlPolicyProvider), isTrue);
    });

    test('toggle() flips the policy', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(hostControlPolicyProvider.notifier)
        ..toggle();
      expect(container.read(hostControlPolicyProvider), isFalse);

      notifier.toggle();
      expect(container.read(hostControlPolicyProvider), isTrue);
    });
  });
}
