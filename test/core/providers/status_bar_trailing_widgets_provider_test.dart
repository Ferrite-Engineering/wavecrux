// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/status_bar_trailing_widgets_provider.dart';

void main() {
  group('statusBarTrailingWidgetsProvider', () {
    test('defaults to an empty list (open-core injects nothing)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(statusBarTrailingWidgetsProvider), isEmpty);
    });

    test('can be overridden to inject trailing widgets (Pro overlay seam)', () {
      const injected = [SizedBox(key: Key('collab-chip'))];
      final container = ProviderContainer(
        overrides: [
          statusBarTrailingWidgetsProvider.overrideWithValue(injected),
        ],
      );
      addTearDown(container.dispose);

      final widgets = container.read(statusBarTrailingWidgetsProvider);
      expect(widgets, hasLength(1));
      expect(widgets.first.key, const Key('collab-chip'));
    });
  });
}
