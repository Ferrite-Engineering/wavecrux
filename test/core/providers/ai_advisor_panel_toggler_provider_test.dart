// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/ai_advisor_panel_toggler_provider.dart';

void main() {
  group('aiAdvisorPanelTogglerProvider', () {
    test('open-core default is a no-op callable', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final toggler = container.read(aiAdvisorPanelTogglerProvider);
      // The no-op never reads its context; a throw-on-read context proves it.
      expect(() => toggler(_NullContext()), returnsNormally);
    });

    test('overrides replace the default callable', () {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          aiAdvisorPanelTogglerProvider.overrideWithValue((_) => calls++),
        ],
      );
      addTearDown(container.dispose);
      container.read(aiAdvisorPanelTogglerProvider)(_NullContext());
      expect(calls, 1);
    });
  });
}

class _NullContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'BuildContext is unused by the open-core no-op '
    'aiAdvisorPanelTogglerProvider; do not invoke any context method here.',
  );
}
