// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/features/diagnostics/providers/render_pipeline_stats_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_id_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';

part 'pane_container_manager.g.dart';

/// Creates, caches, and disposes a [ProviderContainer] for each visible pane
/// (split-pane).
///
/// Each pane container is a child of the root [ProviderContainer] and
/// overrides the WaveCrux-side `paneIdProvider` plus [paneRenderStatsProvider]
/// with fresh instances. This isolates per-pane data — pane identity,
/// paint-time sparkline history, future per-pane state — so the two panes in
/// a split layout never share buffers.
///
/// Global providers (settings, license tier, workspace, device class, theme,
/// tab list, active tab) and per-tab containers resolve from the root
/// container via Riverpod's parent lookup; per-tab `UncontrolledProviderScope`s
/// continue to wrap the per-tab subtree inside each pane scope.
///
/// This class is a thin wrapper around the package's generic
/// [`crux.PaneContainerManager`]: container creation and caching are
/// delegated, but the WaveCrux-specific per-pane resource lifecycle —
/// [RenderStatsCollector] allocation and the collector→notifier bridge
/// listener — remains here because those concerns are out of scope for the
/// package.
///
/// [PaneContainerManager] follows the same two-phase init pattern as
/// [TabContainerManager]: construct first so it can be injected as an
/// override value, then call [init] with the root container so child
/// containers can be parented to it.
class PaneContainerManager implements crux.WorkspaceScopeReconciler {
  PaneContainerManager({this.extraPaneOverrides = const []});

  /// Extra overrides appended to every per-pane container's override list.
  /// Intended for testing and for the Pro overlay's pane-scoped extension
  /// points. Leave empty for production use.
  final List<Override> extraPaneOverrides;

  crux.PaneContainerManager? _inner;
  // Per-pane resources released when the pane closes. Indexed by [PaneId].
  final Map<PaneId, RenderStatsCollector> _collectors = {};
  final Map<PaneId, VoidCallback> _collectorListeners = {};

  /// Called once, immediately after the root [ProviderContainer] is created.
  void init(ProviderContainer rootContainer) {
    _inner = crux.PaneContainerManager(
      rootContainer: rootContainer,
      overridesFactory: _composeOverrides,
    );
  }

  List<Override> _composeOverrides(crux.PaneId paneId) {
    // The per-pane RenderStatsCollector must be allocated BEFORE the
    // package's PCM invokes this factory; the factory captures the
    // collector by closure via `_collectors[paneId]`. [containerFor]
    // calls [_setupPaneResources] first to populate the map.
    final collector = _collectors[paneId]!;
    final defaults = <Override>[
      // WaveCrux-local `paneIdProvider` override — distinct from
      // `crux.paneIdProvider` which the package's PaneContainerManager
      // prepends automatically.
      paneIdProvider.overrideWithValue(paneId),
      // Render stats are per-pane: each pane keeps its own sparkline
      // buffer so switching the active pane swaps the visible history
      // without losing samples (ARCHITECTURE.md §8.8).
      paneRenderStatsProvider.overrideWith(PaneRenderStatsNotifier.new),
      // Per-pane RenderStatsCollector so the canvas painted into THIS
      // pane publishes only into THIS pane's notifier.
      renderStatsCollectorProvider.overrideWithValue(collector),
      // NOTE: panel visibility (signal tree, value column, bottom/transaction,
      // Stage, statistics strip) is NOT per-pane — it is **per-tab**, overridden
      // in `wavecruxTabOverrides`. A per-pane override here was dead anyway:
      // per-tab containers parent to root, not to the pane container, so the
      // StatusBar / IdeLayout (hosted in the tab container) never resolved it.
    ];

    if (extraPaneOverrides.isEmpty) return defaults;
    // Riverpod 3 forbids two overrides for the same provider in the same
    // container. Dedupe by `Override.origin` so caller-supplied
    // [extraPaneOverrides] win over the defaults (matching the
    // pre-Riverpod-3 last-wins semantic). `origin` is `@visibleForTesting`
    // but is the only public hook for identity; ignored deliberately on
    // both use sites below.
    final extraOrigins = extraPaneOverrides
        // Read `Override.origin` to dedupe — see surrounding comment.
        // ignore: invalid_use_of_visible_for_testing_member
        .map((o) => o.origin)
        .toSet();
    return [
      for (final o in defaults)
        // Read `Override.origin` to dedupe — see surrounding comment.
        // ignore: invalid_use_of_visible_for_testing_member
        if (!extraOrigins.contains(o.origin)) o,
      ...extraPaneOverrides,
    ];
  }

  /// Returns the [ProviderContainer] for [id], creating it on first access.
  ///
  /// All per-pane providers are overridden with fresh instances so each pane
  /// has fully independent state.
  ProviderContainer containerFor(PaneId id) {
    final inner = _inner;
    if (inner == null) {
      throw StateError(
        'PaneContainerManager.containerFor called before init(rootContainer).',
      );
    }
    if (inner.hasContainerFor(id)) return inner.containerFor(id);
    // Set up per-pane resources BEFORE the package's PCM constructs the
    // container so the override factory closure can capture the
    // freshly-created [RenderStatsCollector] by closure.
    _setupPaneResources(id);
    final container = inner.containerFor(id);
    _attachBridge(id, container);
    return container;
  }

  void _setupPaneResources(PaneId id) {
    // Issue 6 / Issue 7: each pane gets its own [RenderStatsCollector] so the
    // canvas painting into pane A publishes only to pane A's notifier (and
    // its sparkline buffer).
    _collectors[id] = RenderStatsCollector();
  }

  void _attachBridge(PaneId id, ProviderContainer container) {
    final collector = _collectors[id]!;
    // Bridge: collector → paneRenderStatsProvider. Each time the collector
    // publishes a new frame, push the snapshot into the pane's notifier
    // (which appends to its rolling sparkline buffer).
    //
    // `collector.notifyListeners` fires synchronously from inside
    // [WaveformCanvasRenderObject.paint] (via [RenderStatsCollector.endFrame])
    // — i.e. during a paint pass. Mutating a Riverpod provider in that phase
    // trips `_debugCanModifyProviders` ("Tried to modify a provider while the
    // widget tree was building"). Defer the mutation to a microtask so the
    // state update lands AFTER the current frame's paint pass completes.
    //
    // This is the ONLY collector→`paneRenderStatsProvider` bridge in the
    // codebase — the root-scope `renderStatsCollectorProvider` deliberately
    // does NOT register a similar listener so the root notifier stays
    // empty and per-pane sparkline isolation is preserved by construction
    // (Issue 31: VERIFICATION_GUIDE §22.9.11).
    void bridge() {
      final latest = collector.stats;
      if (latest == null) return;
      unawaited(
        Future.microtask(() {
          try {
            container.read(paneRenderStatsProvider.notifier).record(latest);
          } on Object {
            // Container may have been disposed (pane closed, hot restart).
            // Best-effort: drop the sample.
          }
        }),
      );
    }

    collector.addListener(bridge);
    _collectorListeners[id] = bridge;
  }

  /// Disposes the [ProviderContainer] for [id] and removes it from the cache.
  /// Call this when a pane is closed (split → unsplit) so its providers can
  /// clean up.
  void disposePane(PaneId id) {
    _releasePaneResources(id);
    _inner?.disposePane(id);
  }

  /// Disposes all pane containers. Called when the app shuts down.
  void dispose() {
    _collectors.keys.toList().forEach(_releasePaneResources);
    _inner?.dispose();
  }

  /// Structural scope eviction: releases every pane resource the workspace no
  /// longer declares alive.
  ///
  /// Registered with `WorkspaceNotifier.addScopeReconciler` at bootstrap.
  /// WaveCrux's panes own more than a `ProviderContainer` — a
  /// [RenderStatsCollector] and a collector listener — so this releases those
  /// first and then lets the package manager drop the containers. Without it
  /// a closed pane keeps its collector and bridge alive for the process
  /// lifetime.
  @override
  void reconcileScopes(crux.WorkspaceScopeSnapshot live) {
    for (final id in _collectors.keys.toList()) {
      if (!live.paneIds.contains(id)) _releasePaneResources(id);
    }
    _inner?.reconcileScopes(live);
  }

  /// Releases the per-pane collector and the ChangeNotifier listener owned
  /// by [containerFor]. Safe to call multiple times.
  void _releasePaneResources(PaneId id) {
    final collector = _collectors.remove(id);
    final listener = _collectorListeners.remove(id);
    if (collector != null && listener != null) {
      collector.removeListener(listener);
    }
    collector?.dispose();
  }
}

/// Root-scope provider for the [PaneContainerManager].
///
/// Has **no default** — must be overridden with the concrete manager
/// instance before [runApp]:
/// ```dart
/// paneContainerManagerProvider.overrideWithValue(pcm)
/// ```
/// Reading this provider before it is overridden is a programming error and
/// throws [UnimplementedError].
@Riverpod(keepAlive: true)
PaneContainerManager paneContainerManager(Ref ref) {
  throw UnimplementedError(
    'paneContainerManagerProvider must be overridden with a '
    'PaneContainerManager instance in the root ProviderScope before runApp '
    'is called.',
  );
}
