// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/startup_reconcile_provider.dart';

void main() {
  group('startupReconcileProvider', () {
    test('exposes a fresh, incomplete completer', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final completer = container.read(startupReconcileProvider);
      expect(completer.isCompleted, isFalse);
    });

    test('returns the same completer instance across reads (keepAlive)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(startupReconcileProvider);
      final second = container.read(startupReconcileProvider);
      expect(identical(first, second), isTrue);

      // Completing through one read is observable through the other — the
      // barrier the CLI-file open awaits is the one the reconcile completes.
      first.complete();
      expect(second.isCompleted, isTrue);
    });

    test('separate containers get independent completers (per launch)', () {
      final a = ProviderContainer();
      final b = ProviderContainer();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      a.read(startupReconcileProvider).complete();
      expect(a.read(startupReconcileProvider).isCompleted, isTrue);
      expect(b.read(startupReconcileProvider).isCompleted, isFalse);
    });
  });
}
