// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/annotations/providers/trace_annotation_persistence.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/services/tabs/wavecrux_tab_overrides.dart';

part 'tab_container_manager.g.dart';

/// Creates, caches, and disposes a [ProviderContainer] for each open tab.
///
/// Each tab container is a child of the root [ProviderContainer] and overrides
/// `tabIdProvider` plus all per-tab providers with fresh instances. This
/// isolates every tab's waveform state — cursor, zoom, signal groups, session,
/// Stage config, decoders, etc. — so that opening or modifying one tab never
/// bleeds into another.
///
/// Global providers (settings, license tier, device class, tab list, theme)
/// are not overridden here; they resolve from the root container via Riverpod's
/// parent lookup.
///
/// As of Session 5 of the `crux_workspace` migration this class is a thin
/// wrapper around the package's generic [`crux.TabContainerManager`]:
/// container creation, caching, and disposal are delegated; the
/// WaveCrux-specific per-tab overrides are supplied via the
/// [wavecruxTabOverrides] factory; and the [sessionAutoSaveProvider] eager
/// read (which arms the per-tab autosave `ref.listen` chain) is performed
/// in [containerFor] immediately after a fresh container is created.
///
/// [TabContainerManager] is constructed before the root container (so it can
/// be injected as an override value), then initialized via [init] once the
/// root container exists:
/// ```dart
/// final tcm = TabContainerManager();
/// final root = ProviderContainer(overrides: [
///   tabContainerManagerProvider.overrideWithValue(tcm),
///   ...extraOverrides,
/// ]);
/// tcm.init(root);
/// ```
class TabContainerManager implements crux.WorkspaceScopeReconciler {
  /// Extra overrides appended to every per-tab container's override list.
  ///
  /// Intended for testing (inject mock notifiers) and for the Pro overlay
  /// (inject Pro-specific per-tab providers). Leave empty for production use.
  TabContainerManager({this.extraTabOverrides = const []});

  final List<Override> extraTabOverrides;
  crux.TabContainerManager? _inner;

  /// Called once, immediately after the root [ProviderContainer] is created.
  void init(ProviderContainer rootContainer) {
    _inner = crux.TabContainerManager(
      rootContainer: rootContainer,
      overridesFactory: _composeOverrides,
    );
  }

  List<Override> _composeOverrides(crux.TabId tabId) {
    final defaults = wavecruxTabOverrides(tabId);
    if (extraTabOverrides.isEmpty) return defaults;
    // Riverpod 3 forbids registering two overrides for the same provider in
    // the same container. Earlier versions silently let the later override
    // win, which is the semantic [extraTabOverrides] relied on (tests inject
    // a custom notifier for a per-tab provider). Dedupe by `origin` so the
    // caller-supplied override wins without violating the runtime check.
    // `Override.origin` is `@visibleForTesting` but is the only public hook
    // for this — ignored deliberately on both use sites below.
    final extraOrigins = extraTabOverrides
        // Read `Override.origin` to dedupe — see surrounding comment.
        // ignore: invalid_use_of_visible_for_testing_member
        .map((o) => o.origin)
        .toSet();
    return [
      for (final o in defaults)
        // Read `Override.origin` to dedupe — see surrounding comment.
        // ignore: invalid_use_of_visible_for_testing_member
        if (!extraOrigins.contains(o.origin)) o,
      ...extraTabOverrides,
    ];
  }

  /// Returns the [ProviderContainer] for [id], creating it on first access.
  ///
  /// All per-tab providers are overridden with fresh instances so that each
  /// tab has fully independent waveform state.
  ProviderContainer containerFor(TabId id) {
    final inner = _inner;
    if (inner == null) {
      throw StateError(
        'TabContainerManager.containerFor called before init(rootContainer).',
      );
    }
    final isFirstAccess = !inner.hasContainerFor(id);
    final container = inner.containerFor(id);
    if (isFirstAccess) {
      // Eagerly read the autosave so its `ref.listen` chain is armed the
      // moment the tab opens. Without this read, [SessionAutoSaveNotifier]
      // lazily instantiates only when somebody else reads it — and nothing
      // else does, so per-tab state (cursors, signal groups, zoom, markers,
      // Stage workspace, translate filters, panel visibility) would never
      // make it to disk between explicit Save actions.
      container
        ..read(sessionAutoSaveProvider)
        // Same reasoning for the per-TRACE annotation store. It is a separate
        // notifier because it survives what the sidecar does not: closing a tab
        // deletes the sidecar, and the user's notes must not go with it.
        ..read(traceAnnotationPersistenceProvider);
    }
    return container;
  }

  /// Disposes the [ProviderContainer] for [id] and removes it from the cache.
  ///
  /// Call this when the tab is permanently closed so providers in that
  /// container can clean up.
  void disposeTab(TabId id) {
    _inner?.disposeTab(id);
  }

  /// Disposes all tab containers. Called when the app shuts down.
  void dispose() {
    _inner?.dispose();
  }

  /// Structural scope eviction: disposes the container of every tab the
  /// workspace no longer declares alive.
  ///
  /// Registered with `WorkspaceNotifier.addScopeReconciler` at bootstrap.
  /// This is what makes tab-container disposal a property of the workspace's
  /// shape instead of an opt-in [disposeTab] call a contributor has to
  /// remember — the seam that stops closed tabs leaking their providers and
  /// stops a revived `TabId` inheriting the dead tab's container on workspace
  /// reload. Delegated wholesale to the package manager, which owns the cache.
  @override
  void reconcileScopes(crux.WorkspaceScopeSnapshot live) {
    _inner?.reconcileScopes(live);
  }
}

/// Root-scope provider for the [TabContainerManager].
///
/// Has **no default** — must be overridden with the concrete
/// [TabContainerManager] instance before [runApp]:
/// ```dart
/// tabContainerManagerProvider.overrideWithValue(tcm)
/// ```
/// Reading this provider before it is overridden is a programming error and
/// throws [UnimplementedError].
@Riverpod(keepAlive: true)
TabContainerManager tabContainerManager(Ref ref) {
  throw UnimplementedError(
    'tabContainerManagerProvider must be overridden with a TabContainerManager '
    'instance in the root ProviderScope before runApp is called.',
  );
}
