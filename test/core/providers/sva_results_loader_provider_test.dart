// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/sva_results_loader_provider.dart';

void main() {
  group('svaResultsLoaderProvider', () {
    test('open-core default is a no-op callable', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final loader = container.read(svaResultsLoaderProvider);
      // The no-op never reads the context, so a throw-on-read context is
      // sufficient to assert "no-op".
      expect(() => loader(_NullContext()), returnsNormally);
    });

    test('overrides replace the default callable', () {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          svaResultsLoaderProvider.overrideWithValue((_) => calls++),
        ],
      );
      addTearDown(container.dispose);
      container.read(svaResultsLoaderProvider)(_NullContext());
      expect(calls, 1);
    });
  });

  group('svaResultsClearerProvider', () {
    test('open-core default is a no-op callable', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final clearer = container.read(svaResultsClearerProvider);
      expect(() => clearer(_NullContext()), returnsNormally);
    });

    test('overrides replace the default callable', () {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          svaResultsClearerProvider.overrideWithValue((_) => calls++),
        ],
      );
      addTearDown(container.dispose);
      container.read(svaResultsClearerProvider)(_NullContext());
      expect(calls, 1);
    });
  });
}

class _NullContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'BuildContext is unused by the open-core no-op SVA results-loader '
    'seams; do not invoke any context method here.',
  );
}
