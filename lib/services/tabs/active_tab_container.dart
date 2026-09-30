// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Resolves the [ProviderContainer] holding the **active tab's** per-tab state,
/// or `null` when there is no real tab open (startup / empty-canvas, or a
/// non-tabbed test host).
///
/// Root-scoped, `keepAlive` services and bridges (the CXP / WCP servers, the
/// collaboration bridge, the mobile memory guard, …) live at the root
/// container, but the providers they query and mutate — `waveformSourceProvider`,
/// `cursorStateProvider`, `markerStateProvider`, `signalGroupsProvider`,
/// `panelLayoutProvider`, … — are **per-tab** (overridden in
/// `wavecruxTabOverrides`). Reading those off the root [Ref] hits the dead
/// root-scope instances the UI never updates (the issue #44 scope-leak class).
/// Such a service must route per-tab access through this container, and (for
/// long-lived `listen` subscriptions) re-bind whenever `activeTabIdProvider`
/// changes.
///
/// Returning `null` rather than a phantom container is deliberate: at
/// startup/empty-canvas `activeTabIdProvider` yields a freshly-generated id with
/// no backing tab, and `containerFor` would otherwise spin up a per-tab
/// container (with its own autosave timer) for a tab that never opens. Callers
/// fall back to the root [Ref] in that case — which both keeps flat-container
/// unit tests working and yields the correct "no waveform loaded" behavior in
/// production. Mirrors `defaultActiveTabContainerResolver` in the collaboration
/// bridge and `RemoteControlNotifier._activeTab`.
ProviderContainer? activeTabContainer(Ref ref) {
  try {
    final tabId = ref.read(activeTabIdProvider);
    final tabs = ref.read(tabListProvider);
    if (!tabs.any((tab) => tab.id == tabId)) return null;
    return ref.read(tabContainerManagerProvider).containerFor(tabId);
  } on Object {
    return null;
  }
}

/// Reads [provider] through the **active tab's** container, falling back to the
/// root [ref] when there is no real tab.
///
/// The one-line companion to [activeTabContainer], and the form every
/// root-scoped service actually wants: reading a per-tab provider off the root
/// [Ref] hits the dead root-scope instance the UI never updates (the issue #44
/// scope-leak class), and the fallback is what keeps flat-container unit tests
/// and the empty-canvas state working. Shared by the CXP inbound handlers and
/// the editor-host bridge — the two front doors that mutate per-tab state on
/// behalf of something outside the app — so the fallback rule is written once.
T readActive<T>(Ref ref, ProviderListenable<T> provider) {
  final tab = activeTabContainer(ref);
  return tab != null ? tab.read(provider) : ref.read(provider);
}
