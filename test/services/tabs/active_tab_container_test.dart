// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/tabs/active_tab_container.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../helpers/in_memory_workspace_service.dart';
import '../../helpers/product_telemetry_config.dart';

/// Exposes a container's [Ref] so the helper can be called with a real root ref.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('activeTabContainer', () {
    test(
      'returns null when no real tab is open (empty canvas / flat host)',
      () {
        final tcm = TabContainerManager();
        final root = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            ...testWorkspaceOverrides(),
            tabContainerManagerProvider.overrideWithValue(tcm),
          ],
        );
        tcm.init(root);
        addTearDown(() {
          tcm.dispose();
          root.dispose();
        });

        // No tab seeded → activeTabIdProvider yields a synthetic id absent from
        // tabListProvider → resolver returns null (no phantom container).
        expect(activeTabContainer(root.read(_refProvider)), isNull);
      },
    );

    test('returns the ACTIVE tab container once a tab is seeded', () async {
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          ...testWorkspaceOverrides(),
          tabContainerManagerProvider.overrideWithValue(tcm),
        ],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });

      final tabId = await root.wavecruxWorkspace.newTab(displayName: 'Tab');
      await root.wavecruxWorkspace.flushPendingSave();
      expect(root.read(activeTabIdProvider), tabId);

      final resolved = activeTabContainer(root.read(_refProvider));
      expect(resolved, isNotNull);
      expect(identical(resolved, tcm.containerFor(tabId)), isTrue);

      // The resolved container is genuinely the per-tab one: a write through it
      // is observable via the tab's own container, not the root scope.
      resolved!.read(panelLayoutProvider.notifier).toggleRtlSource();
      expect(
        tcm.containerFor(tabId).read(panelLayoutProvider).rtlSourceVisible,
        isTrue,
      );
      expect(root.read(panelLayoutProvider).rtlSourceVisible, isFalse);
    });
  });
}
