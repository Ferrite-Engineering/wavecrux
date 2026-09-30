// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/sva_panel_toggler_provider.dart';

void main() {
  group('svaPanelTogglerProvider', () {
    test('open-core default is a no-op callable', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final toggler = container.read(svaPanelTogglerProvider);
      // Calling the no-op should not throw. We don't have a real
      // BuildContext here; the no-op never reads it, so passing a
      // throw-on-read context is sufficient to assert "no-op".
      expect(() => toggler(_NullContext()), returnsNormally);
    });

    test('overrides replace the default callable', () {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          svaPanelTogglerProvider.overrideWithValue((_) => calls++),
        ],
      );
      addTearDown(container.dispose);
      container.read(svaPanelTogglerProvider)(_NullContext());
      expect(calls, 1);
    });
  });
}

class _NullContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'BuildContext is unused by the open-core no-op '
    'svaPanelTogglerProvider; do not invoke any context method here.',
  );
}
