// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/collaboration/providers/composition_detached_provider.dart';

void main() {
  group('compositionDetachedProvider', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('defaults to following (false)', () {
      expect(container.read(compositionDetachedProvider), isFalse);
    });

    test('detach sets true, resume sets false', () {
      final notifier = container.read(compositionDetachedProvider.notifier)
        ..detach();
      expect(container.read(compositionDetachedProvider), isTrue);
      notifier.resume();
      expect(container.read(compositionDetachedProvider), isFalse);
    });

    test('detach and resume are idempotent', () {
      final notifier = container.read(compositionDetachedProvider.notifier)
        ..resume();
      expect(container.read(compositionDetachedProvider), isFalse);
      notifier
        ..detach()
        ..detach();
      expect(container.read(compositionDetachedProvider), isTrue);
    });
  });
}
