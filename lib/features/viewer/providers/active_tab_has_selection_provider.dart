// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

part 'active_tab_has_selection_provider.g.dart';

/// Root-scope mirror of whether the **active tab** has any selected signals.
///
/// Selection lives in each tab's child `ProviderContainer`
/// ([selectedVariablesProvider]). The root-scope action surfaces (menu bar,
/// overflow menu, command palette) build [ActionContext] outside any tab scope
/// and cannot `ref.watch` a tab container's provider, so this mirrors the
/// active tab's selection emptiness up to the root — exactly the pattern
/// `ActiveTabPanelLayout` uses for panel visibility (see its doc for why a
/// second `UncontrolledProviderScope` would race the scheduler).
///
/// Gates AI actions such as Explain Selection, which require a non-empty
/// selection. Reads go through the resolved `container`, not `ref`, so the
/// per-tab scope-leak guard does not flag it.
@riverpod
class ActiveTabHasSelection extends _$ActiveTabHasSelection {
  @override
  bool build() {
    final tabId = ref.watch(activeTabIdProvider);

    final ProviderContainer container;
    try {
      final tcm = ref.watch(tabContainerManagerProvider);
      container = tcm.containerFor(tabId);
    } on Object {
      return false;
    }

    final sub = container.listen<Set<String>>(
      selectedVariablesProvider,
      (_, next) => state = next.isNotEmpty,
    );
    ref.onDispose(sub.close);

    return container.read(selectedVariablesProvider).isNotEmpty;
  }
}
