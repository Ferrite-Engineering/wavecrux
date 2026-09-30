// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

part 'active_tab_panel_layout_provider.g.dart';

/// Root-scope mirror of the **active tab's** [panelLayoutProvider].
///
/// Panel visibility is per-tab, stored in each tab's child `ProviderContainer`.
/// Screen chrome that lives OUTSIDE any tab's scope — specifically the single
/// screen-level toolbar, whose transaction-table / Stage indicator checkmarks
/// must mirror the active tab — cannot `ref.watch` a tab container's provider.
/// Doing so would require mounting a second [UncontrolledProviderScope] for
/// that container; but PaneHost already mounts one for the active tab's
/// content, and two scopes driving one container's scheduler race: while the
/// tab's providers churn (e.g. cursor scrubbing) the extra scope flushes the
/// scheduler mid-build and throws `markNeedsBuild() called during build`.
///
/// This provider bridges the gap from the root scope: it resolves the active
/// tab's container via [tabContainerManagerProvider] and imperatively `listen`s
/// to its [panelLayoutProvider], re-emitting on change. The toolbar watches
/// THIS (root-scope) provider normally, so it never has to enter a tab's scope.
///
/// Like `mobileMemoryGuardProvider` / `remoteControlProvider`, reads go through
/// the resolved `tabContainer`, not `ref`, so the per-tab scope-leak guard
/// (`test/static/per_tab_provider_scope_leak_test.dart`) does not flag it.
@riverpod
class ActiveTabPanelLayout extends _$ActiveTabPanelLayout {
  @override
  PanelLayoutState build() {
    final tabId = ref.watch(activeTabIdProvider);

    final ProviderContainer container;
    try {
      // `tabContainerManagerProvider` throws when it has not been overridden
      // (no root scope yet) — e.g. in unit tests that render a menu/toolbar
      // without a tab-container manager. Both that and a not-yet-hydrated tab
      // container fall back to the panel-layout defaults.
      final tcm = ref.watch(tabContainerManagerProvider);
      container = tcm.containerFor(tabId);
    } on Object {
      return const PanelLayoutState();
    }

    // Imperative subscription to the active tab's per-tab panel state. Panel
    // visibility only changes on user/event actions (chevron tap, toolbar
    // button, file load, X-Trace/FSM auto-show) — never during a frame's
    // build — so re-emitting here cannot mark a widget dirty mid-build.
    final sub = container.listen<PanelLayoutState>(
      panelLayoutProvider,
      (_, next) => state = next,
    );
    ref.onDispose(sub.close);

    return container.read(panelLayoutProvider);
  }
}
