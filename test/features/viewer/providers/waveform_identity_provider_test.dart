// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/waveform_identity_provider.dart';

void main() {
  group('WaveformIdentity', () {
    test('builds to null (no waveform loaded)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(waveformIdentityProvider), isNull);
    });

    test('set publishes a hash and notifies watchers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final seen = <String?>[];
      container.listen(
        waveformIdentityProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );

      container.read(waveformIdentityProvider.notifier).set('abc123');
      container.read(waveformIdentityProvider.notifier).set(null);

      expect(container.read(waveformIdentityProvider), isNull);
      expect(seen, [null, 'abc123', null]);
    });
  });
}
