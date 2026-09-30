// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/plugins/bottom_dock_tab.dart';
import 'package:wavecrux/plugins/extra_bottom_dock_tabs_provider.dart';

final _visibility = Provider<bool>((_) => false);

void main() {
  group('extraBottomDockTabsProvider', () {
    test('open-core default returns an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(extraBottomDockTabsProvider), isEmpty);
    });

    test('overrides replace the default list', () {
      final tabs = [
        BottomDockTab(
          id: 'sva',
          labelResolver: (_) => 'SVA',
          icon: Icons.check,
          builder: (_) => const SizedBox.shrink(),
          visibilityProvider: _visibility,
          requiredTier: LicenseTier.pro,
        ),
      ];
      final container = ProviderContainer(
        overrides: [extraBottomDockTabsProvider.overrideWithValue(tabs)],
      );
      addTearDown(container.dispose);
      final result = container.read(extraBottomDockTabsProvider);
      expect(result.length, 1);
      expect(result.single.id, 'sva');
      expect(result.single.requiredTier, LicenseTier.pro);
    });
  });
}
