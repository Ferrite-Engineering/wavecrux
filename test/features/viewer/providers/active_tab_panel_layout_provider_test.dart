// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests for the root-scope bridge that mirrors the ACTIVE tab's per-tab
// panelLayoutProvider for chrome (the toolbar) that lives outside any tab's
// scope. Uses a REAL parent/child container pair from `TabContainerManager`
// so `panelLayoutProvider` is genuinely per-tab (overridden in
// `wavecruxTabOverrides`), exactly as in the running app.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

void main() {
  group('activeTabPanelLayoutProvider', () {
    late TabContainerManager tcm;
    late ProviderContainer root;

    setUp(() {
      tcm = TabContainerManager();
      root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
    });

    tearDown(() {
      tcm.dispose();
      root.dispose();
    });

    test('mirrors the active tab panel state and re-emits on change', () {
      // Keep the bridge alive so its imperative `container.listen` stays armed.
      final sub = root.listen(activeTabPanelLayoutProvider, (_, _) {});
      addTearDown(sub.close);

      final activeId = root.read(activeTabIdProvider);
      final activeTab = tcm.containerFor(activeId);

      // Starts at the per-tab defaults.
      expect(
        root.read(activeTabPanelLayoutProvider).transactionViewVisible,
        isFalse,
      );
      expect(
        root.read(activeTabPanelLayoutProvider).stageViewVisible,
        isFalse,
      );

      // Mutating the ACTIVE tab's per-tab provider re-emits through the bridge.
      activeTab.read(panelLayoutProvider.notifier)
        ..setTransactionViewVisible(visible: true)
        ..setStageViewVisible(visible: true);

      expect(
        root.read(activeTabPanelLayoutProvider).transactionViewVisible,
        isTrue,
      );
      expect(
        root.read(activeTabPanelLayoutProvider).stageViewVisible,
        isTrue,
      );
    });

    test('tracks only the active tab — a different tab does not bleed in', () {
      final sub = root.listen(activeTabPanelLayoutProvider, (_, _) {});
      addTearDown(sub.close);

      // A DIFFERENT (non-active) tab opens its panel.
      final otherTab = tcm.containerFor(TabId.generate());
      otherTab
          .read(panelLayoutProvider.notifier)
          .setTransactionViewVisible(visible: true);

      // The bridge mirrors the ACTIVE tab, which is untouched.
      expect(
        root.read(activeTabPanelLayoutProvider).transactionViewVisible,
        isFalse,
        reason:
            'the bridge must reflect the active tab only, never another '
            'tab in the workspace',
      );
    });
  });
}
