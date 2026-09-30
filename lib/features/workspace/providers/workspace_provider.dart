// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/wavecrux_tab_payload.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import 'package:wavecrux/services/workspace/window_bounds_store.dart';

part 'workspace_provider.g.dart';

/// Default debounce window for auto-saves triggered by workspace mutations.
const Duration kWorkspaceAutoSaveDebounce = crux.kWorkspaceAutoSaveDebounce;

/// WaveCrux-flavored alias for the package's generic workspace service.
typedef WorkspaceService = crux.WorkspaceService<WaveCruxTabPayload>;

/// Singleton [WorkspaceService] used by [WaveCruxWorkspaceNotifier]. Tests
/// override this with a service that points at a temp directory or captures
/// saves.
@Riverpod(keepAlive: true)
WorkspaceService workspaceService(Ref ref) =>
    WorkspaceService(codec: const WaveCruxWorkspaceCodec());

/// Root-scope provider holding the workspace document.
///
/// The provider's notifier type is [WaveCruxWorkspaceNotifier] — the WaveCrux
/// subclass of [crux.WorkspaceNotifier]<[WaveCruxTabPayload]> — so callers
/// reading `workspaceProvider.notifier` see the WaveCrux-named wrapper
/// methods (`addTab`, `removeTab`, `reorderTabs`, `splitPane`, `closePane`,
/// `moveTabToPane`, `reset`, `replaceFromNamed`) alongside the package's
/// inherited mutation surface.
///
/// Each mutation updates the in-memory state immediately and schedules a
/// debounced save via [WorkspaceService.save]; lifecycle handlers call
/// [crux.WorkspaceNotifier.flushPendingSave] to force a synchronous final
/// write on app pause / detach.
/// The notifier is typed at the **package supertype**
/// [crux.WorkspaceNotifier]<[WaveCruxTabPayload]> (not the WaveCrux subclass)
/// so the provider feeds the `crux_workspace` widgets (`PaneHost`,
/// `ViewerTabBar`) directly — those require an
/// `AsyncNotifierProvider<crux.WorkspaceNotifier<P>, crux.Workspace<P>>` and
/// Dart's invariant generics reject the subclass-typed provider. The runtime
/// instance is always a [WaveCruxWorkspaceNotifier]; call sites that need the
/// WaveCrux-named convenience methods reach it via [WidgetRef.wavecruxWorkspace]
/// / [Ref.wavecruxWorkspace] (a checked downcast, never a second provider).
final AsyncNotifierProvider<
  crux.WorkspaceNotifier<WaveCruxTabPayload>,
  Workspace
>
workspaceProvider =
    AsyncNotifierProvider<
      crux.WorkspaceNotifier<WaveCruxTabPayload>,
      Workspace
    >(
      WaveCruxWorkspaceNotifier.new,
    );

/// Downcasts the running [workspaceProvider] notifier to the concrete
/// [WaveCruxWorkspaceNotifier] so WaveCrux-named methods (`openFile`,
/// `openSession`, `newTab`, `updateTab`, `markDetached`, `addTab`,
/// `splitPane`, `reset`, `replaceFromNamed`, `current`) are reachable even
/// though the provider is declared at the package supertype. The cast always
/// succeeds — the provider factory is [WaveCruxWorkspaceNotifier.new].
extension WaveCruxWorkspaceWidgetRefX on WidgetRef {
  /// The concrete WaveCrux workspace notifier behind [workspaceProvider].
  WaveCruxWorkspaceNotifier get wavecruxWorkspace =>
      read(workspaceProvider.notifier) as WaveCruxWorkspaceNotifier;
}

/// Non-widget ([Ref]) counterpart of [WaveCruxWorkspaceWidgetRefX].
extension WaveCruxWorkspaceRefX on Ref {
  /// The concrete WaveCrux workspace notifier behind [workspaceProvider].
  WaveCruxWorkspaceNotifier get wavecruxWorkspace =>
      read(workspaceProvider.notifier) as WaveCruxWorkspaceNotifier;
}

/// [ProviderContainer] counterpart of [WaveCruxWorkspaceWidgetRefX], for
/// command helpers and tests that hold a container directly.
extension WaveCruxWorkspaceContainerX on ProviderContainer {
  /// The concrete WaveCrux workspace notifier behind [workspaceProvider].
  WaveCruxWorkspaceNotifier get wavecruxWorkspace =>
      read(workspaceProvider.notifier) as WaveCruxWorkspaceNotifier;
}

/// WaveCrux subclass of [crux.WorkspaceNotifier] adding:
///
/// * Telemetry emission on workspace lifecycle and mutation events
///   (`workspace.restored`, `tab.opened`, `pane.split`, `pane.closed`,
///   `tab.dragged_to_pane`, `workspace.reset`, `workspace.named.opened`).
/// * WaveCrux-named instance methods that preserve every pre-migration
///   consumer call site: `addTab(WorkspaceTab)`, `removeTab(TabId)`,
///   `reorderTabs(TabId, int)`, `splitPane()`, `reset()`,
///   `replaceFromNamed(Workspace)`. The other WaveCrux-named methods
///   (`setActiveTab`, `setActivePane`, `closePane`, `moveTabToPane`,
///   `flushPendingSave`) match the package's method names exactly and are
///   inherited unchanged.
/// * Late service binding: the package's [crux.WorkspaceService] is set at
///   construction, but WaveCrux resolves the service from
///   [workspaceServiceProvider] which is itself a Riverpod provider —
///   readable only after the notifier is mounted. The notifier passes a
///   [_LateBoundWorkspaceService] delegating shim to super at construction
///   and binds the real service inside [build].
class WaveCruxWorkspaceNotifier
    extends crux.WorkspaceNotifier<WaveCruxTabPayload> {
  /// Creates a workspace notifier. The service is bound lazily inside
  /// [build] via `ref.read(workspaceServiceProvider)`; the placeholder
  /// passed to super delegates every call through to the bound service.
  ///
  /// [autoSaveDebounce] forwards to the package base; tests override
  /// [workspaceProvider] with `Duration.zero` so mutations save eagerly and
  /// leave no pending debounce `Timer` to trip the widget-test pending-timer
  /// check.
  // A super-parameter can't be combined with the explicit `super(service:)`
  // initializer this constructor needs (it builds the late-bound shim), so
  // forward [autoSaveDebounce] manually.
  // ignore: use_super_parameters
  WaveCruxWorkspaceNotifier({
    Duration autoSaveDebounce = kWorkspaceAutoSaveDebounce,
  }) : super(
         service: _LateBoundWorkspaceService(),
         autoSaveDebounce: autoSaveDebounce,
       ) {
    // The delegating shim needs a reference to itself for binding; cast
    // here once so the override site doesn't have to repeat it.
    _shim = service as _LateBoundWorkspaceService;
  }

  late final _LateBoundWorkspaceService _shim;

  bool _emittedRestored = false;

  /// Records through the seam **resolved now**, never through one captured at
  /// [build].
  ///
  /// `telemetryServiceProvider` is not constant for the life of a session. The
  /// consent store publishes `unset` synchronously and reads the persisted
  /// value back asynchronously, so at the moment this notifier builds — a cold
  /// start — the gate has not seen the user's stored answer yet and resolves
  /// the no-op. A field assigned there froze the *first frame's* verdict for
  /// the whole session: an installation that had consented recorded nothing,
  /// and no amount of consenting later changed it. The read is a map lookup.
  void _emit(String name, [Map<String, Object?>? properties]) {
    if (!ref.mounted) return;
    ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent(name, properties: properties));
  }

  /// Read-only access to the current workspace. Throws if [build] has not
  /// yet completed; mirrors the pre-migration `current` getter that
  /// existing call sites rely on.
  Workspace get current => state.requireValue;

  @override
  Future<Workspace> build() async {
    final realService = ref.read(workspaceServiceProvider);
    _shim.attach(realService);
    final loaded = await super.build();
    final sanitized = _stripEmptySiblingPanes(loaded);
    if (!_emittedRestored) {
      _emittedRestored = true;
      _emit(
        'workspace.restored',
        {'tabs': sanitized.tabs.length, 'panes': sanitized.panes.length},
      );
    }
    return sanitized;
  }

  /// Drops panes that hold no tabs when at least one other pane *does* hold
  /// tabs. Workspaces with no tabs at all (the canonical empty-canvas state)
  /// keep exactly one pane — preferring the previously-active one when it
  /// still exists. Used at load time so a workspace.json that was persisted
  /// with a stranded empty pane (legacy flush race, or a previous bug) self-
  /// heals on next launch instead of presenting the user with a phantom pane
  /// that has no UI affordance to close.
  static Workspace _stripEmptySiblingPanes(Workspace ws) {
    final populatedIds = <crux.PaneId>{for (final t in ws.tabs) t.paneId};
    if (populatedIds.isEmpty) {
      if (ws.panes.length <= 1) return ws;
      final keepId = ws.panes.any((p) => p.id == ws.activePaneId)
          ? ws.activePaneId
          : ws.panes.first.id;
      final kept = ws.panes.firstWhere((p) => p.id == keepId);
      return ws.copyWith(
        panes: [crux.WorkspacePane(id: kept.id)],
        activePaneId: kept.id,
      );
    }
    if (ws.panes.every((p) => populatedIds.contains(p.id))) return ws;
    final kept = ws.panes
        .where((p) => populatedIds.contains(p.id))
        .toList(growable: false);
    final activeId = kept.any((p) => p.id == ws.activePaneId)
        ? ws.activePaneId
        : kept.first.id;
    return ws.copyWith(panes: kept, activePaneId: activeId);
  }

  // ---------------------------------------------------------------------------
  // WaveCrux-named wrappers (backward compat for existing call sites)
  // ---------------------------------------------------------------------------

  /// Appends [tab] to its hosting pane and activates it.
  ///
  /// Unlike the package's [crux.WorkspaceNotifier.openTab] which generates a
  /// fresh [crux.TabId], this wrapper preserves the input [WorkspaceTab.id]
  /// — WaveCrux's [TabListNotifier] generates the id up front and mirrors
  /// the tab into the workspace document with the same id.
  Future<void> addTab(WorkspaceTab tab) async {
    final ws = await future;
    if (ws.tabs.any((t) => t.id == tab.id)) return;
    if (!ws.panes.any((p) => p.id == tab.paneId)) return;
    final tabs = [...ws.tabs, tab];
    final panes = [
      for (final p in ws.panes)
        if (p.id == tab.paneId) p.copyWith(activeTabId: tab.id) else p,
    ];
    // [crux.WorkspaceNotifier.mutate], NOT `replaceWith`: adding a tab is an
    // incremental edit, and `replaceWith` evicts every per-tab and per-pane
    // ProviderContainer before installing the document — including the
    // containers of the tabs that are already open and on screen.
    await mutate(
      (_) => ws.copyWith(tabs: tabs, panes: panes, activePaneId: tab.paneId),
    );
    // Emitted only on an actual add — the two early returns above (duplicate
    // id, missing pane) skip emission so no-op calls do not record an event.
    _emit('tab.opened', {'tabs': tabs.length, 'panes': panes.length});
  }

  /// Records the top-level application window geometry into the workspace
  /// `extras` (under [kWindowBoundsExtrasKey]) so the next cold start restores
  /// the window where the user left it. Called from the quit-time flush **and**
  /// from the live (debounced) window-geometry persister on every resize /
  /// move / maximize. The mutation schedules the usual debounced save; the
  /// quit flush forces it to land synchronously via
  /// [crux.WorkspaceNotifier.flushPendingSave].
  ///
  /// No-op safe under all states — it only rewrites one extras entry and never
  /// touches tabs/panes, so it cannot violate a workspace invariant.
  ///
  /// **Must go through [crux.WorkspaceNotifier.mutate], never `replaceWith`.**
  /// `replaceWith` is a wholesale document replacement: it evicts every
  /// per-tab and per-pane `ProviderContainer` first. Because this method runs
  /// on every window resize, using it here disposed the containers of tabs
  /// that were still on screen; `PaneHost` then rebuilt its per-tab
  /// `UncontrolledProviderScope` with a fresh container under a keyed subtree
  /// whose elements survived, and the nested `ProviderScope` in
  /// `_PaneScopedCanvas` threw "ProviderScope was rebuilt with a different
  /// ProviderScope ancestor" mid-layout — plus the tab silently lost all of
  /// its per-tab state. Regression: `window_bounds_scope_preservation_test`.
  Future<void> setWindowBounds(WindowBounds bounds) async {
    await mutate(
      (ws) => ws.copyWith(extras: extrasWithWindowBounds(ws.extras, bounds)),
    );
  }

  /// Removes the tab identified by [id]. Delegates to the inherited
  /// [crux.WorkspaceNotifier.closeTab] which handles pane-collapse and
  /// active-tab pointer invariants.
  Future<void> removeTab(crux.TabId id) => closeTab(id);

  /// Moves the tab with [id] to [newIndex]. Delegates to the inherited
  /// [crux.WorkspaceNotifier.reorderTab].
  Future<void> reorderTabs(crux.TabId id, int newIndex) =>
      reorderTab(id, newIndex);

  /// Adds a second pane (split). No-op when already split.
  /// Returns the id of the newly-created pane (or the existing sibling
  /// pane when already split).
  ///
  /// Preserves the pre-migration "always empty new pane" semantic — the
  /// active tab does NOT move into the new pane. The package's
  /// [crux.WorkspaceNotifier.splitPaneRight] moves the active tab when the
  /// source pane has more than one tab; WaveCrux's pre-migration callers
  /// rely on the empty-new-pane behavior (see
  /// `_splitPaneRight` in viewer_screen.dart which subsequently issues an
  /// explicit `moveTabToPane` call). Keeping the wrapper semantic verbatim
  /// avoids regressing that flow.
  Future<crux.PaneId> splitPane() async {
    final ws = await future;
    if (ws.panes.length >= 2) {
      return ws.panes.firstWhere((p) => p.id != ws.activePaneId).id;
    }
    final newPane = crux.WorkspacePane(id: crux.PaneId.generate());
    // Incremental edit → [crux.WorkspaceNotifier.mutate]. Splitting must not
    // disturb the existing pane's container (or any open tab's), which is
    // exactly what `replaceWith`'s unconditional scope eviction did.
    await mutate(
      (_) => ws.copyWith(
        panes: [...ws.panes, newPane],
        activePaneId: newPane.id,
      ),
    );
    _emit('pane.split');
    return newPane.id;
  }

  /// Replaces the workspace with [Workspace.empty] and emits the
  /// `workspace.reset` telemetry event. Delegates to the inherited
  /// [crux.WorkspaceNotifier.resetWorkspace].
  Future<void> reset() async {
    await resetWorkspace();
    _emit('workspace.reset');
  }

  /// Replaces the current workspace with [next] (used by "Open Workspace…").
  /// Delegates to the inherited [crux.WorkspaceNotifier.replaceWith].
  Future<void> replaceFromNamed(Workspace next) async {
    await replaceWith(next);
    _emit(
      'workspace.named.opened',
      {'tabs': next.tabs.length, 'panes': next.panes.length},
    );
  }

  // ---------------------------------------------------------------------------
  // Tab-mutation convenience surface (formerly TabListNotifier)
  //
  // The live tab list is now derived from this workspace document
  // ([tabListProvider]), so every tab mutation flows through here. Each method
  // builds the appropriate [WaveCruxTabPayload] and delegates to the package's
  // [crux.WorkspaceNotifier.openTab] (which generates the id, appends the tab,
  // and activates it). The returned [crux.TabId] is the canonical handle the
  // caller uses to reach the new tab's per-tab [ProviderContainer].
  // ---------------------------------------------------------------------------

  /// Opens [filePath] in a new tab and activates it. [displayName] defaults to
  /// the file basename; [paneId] defaults to the active pane. Returns the new
  /// tab's id.
  Future<crux.TabId> openFile(
    String filePath, {
    String? displayName,
    crux.PaneId? paneId,
  }) async {
    final id = await openTab(
      displayName: displayName ?? p.basename(filePath),
      payload: WaveCruxTabPayload(filePath: filePath),
      paneId: paneId,
    );
    _emitTabOpened();
    return id;
  }

  /// Opens a session from [sessionFilePath] in a new tab and activates it.
  /// Returns the new tab's id.
  Future<crux.TabId> openSession(
    String sessionFilePath, {
    String? filePath,
    String? displayName,
    crux.PaneId? paneId,
  }) async {
    final name =
        displayName ??
        (filePath != null
            ? p.basename(filePath)
            : p.basenameWithoutExtension(sessionFilePath));
    final id = await openTab(
      displayName: name,
      payload: WaveCruxTabPayload(
        filePath: filePath,
        sessionFilePath: sessionFilePath,
      ),
      paneId: paneId,
    );
    _emitTabOpened();
    return id;
  }

  /// Adds a new empty placeholder tab (the toolbar `+` / `Cmd+T` flow) and
  /// activates it. [displayName] is the localized placeholder label supplied
  /// by the caller (the notifier has no `BuildContext`). Returns the new id.
  Future<crux.TabId> newTab({
    required String displayName,
    crux.PaneId? paneId,
  }) async {
    final id = await openTab(
      displayName: displayName,
      payload: const WaveCruxTabPayload(),
      paneId: paneId,
    );
    _emitTabOpened();
    return id;
  }

  /// Updates display metadata for the tab with [id] after a file or session
  /// loads. Only non-null arguments are applied; unset payload fields are
  /// preserved.
  Future<void> updateTab(
    crux.TabId id, {
    String? displayName,
    String? filePath,
    String? sessionFilePath,
    String? sessionExportPath,
  }) async {
    if (displayName != null) {
      await updateTabDisplayName(id, displayName);
    }
    if (filePath != null ||
        sessionFilePath != null ||
        sessionExportPath != null) {
      await updateTabPayload(
        id,
        (payload) => payload.copyWith(
          filePath: filePath,
          sessionFilePath: sessionFilePath,
          sessionExportPath: sessionExportPath,
        ),
      );
    }
  }

  /// Marks the tab with [id] as detached (secondary window) or
  /// re-attached. Constructs the payload directly because `copyWith` cannot
  /// clear a `false` flag.
  Future<void> markDetached(crux.TabId id, {required bool detached}) =>
      updateTabPayload(
        id,
        (payload) => WaveCruxTabPayload(
          filePath: payload.filePath,
          sessionFilePath: payload.sessionFilePath,
          sessionExportPath: payload.sessionExportPath,
          isDetached: detached,
        ),
      );

  void _emitTabOpened() {
    final ws = state.value;
    if (ws == null) return;
    _emit('tab.opened', {'tabs': ws.tabs.length, 'panes': ws.panes.length});
  }

  // ---------------------------------------------------------------------------
  // Telemetry-bearing overrides of package methods
  // ---------------------------------------------------------------------------

  @override
  Future<void> closeTab(crux.TabId id) async {
    final before = state.value;
    final existed = before?.tabs.any((t) => t.id == id) ?? false;
    await super.closeTab(id);
    if (existed) {
      // Delete the per-tab session sidecar so closed-tab state does not
      // accumulate under `{appSupportDir}/sessions/`. Best-effort: failures
      // are silent (the sidecar may already be gone, or the support directory
      // unavailable in tests).
      try {
        await ref.read(workspaceServiceProvider).deleteSidecar(id.value);
      } on Object {
        // Swallow — sidecar cleanup is non-fatal.
      }
    }
  }

  @override
  Future<void> closePane(crux.PaneId paneId) async {
    final before = await future;
    final willClose =
        before.panes.length >= 2 && before.panes.any((p) => p.id == paneId);
    await super.closePane(paneId);
    if (willClose) _emit('pane.closed');
  }

  @override
  Future<void> moveTabToPane(crux.TabId tabId, crux.PaneId targetPane) async {
    final before = await future;
    final willMove =
        before.panes.any((p) => p.id == targetPane) &&
        before.tabs.any((t) => t.id == tabId && t.paneId != targetPane);
    await super.moveTabToPane(tabId, targetPane);
    if (willMove) _emit('tab.dragged_to_pane');
  }
}

/// Delegating [crux.WorkspaceService] used as the placeholder passed to
/// [crux.WorkspaceNotifier]'s super constructor.
///
/// The package's notifier holds its service as a `final` field set at
/// construction time, but WaveCrux's real service is resolved through
/// [workspaceServiceProvider] which can only be read after the notifier is
/// mounted (`build` time). The shim bridges those two lifetimes: super's
/// constructor sees a fully-typed [crux.WorkspaceService] instance
/// immediately; every call routes through [_delegate] which the subclass
/// binds inside [build] via [bind].
///
/// All methods used by the package's notifier surface ([load], [save],
/// [saveToPath], [loadFromPath], [clear], [sidecarPathFor], [deleteSidecar])
/// are overridden to delegate. The unbound state never reaches a real call
/// site because [build] binds before any mutation can fire.
class _LateBoundWorkspaceService
    extends crux.WorkspaceService<WaveCruxTabPayload> {
  _LateBoundWorkspaceService() : super(codec: const WaveCruxWorkspaceCodec());

  crux.WorkspaceService<WaveCruxTabPayload>? _delegate;

  /// Binds the real service. Called once from
  /// [WaveCruxWorkspaceNotifier.build].
  // ignore: use_setters_to_change_properties
  void attach(crux.WorkspaceService<WaveCruxTabPayload> delegate) {
    _delegate = delegate;
  }

  crux.WorkspaceService<WaveCruxTabPayload> get _live {
    final d = _delegate;
    if (d == null) {
      throw StateError(
        '_LateBoundWorkspaceService: bind() not yet called. '
        'WaveCruxWorkspaceNotifier.build() should bind the real service '
        'before any other method is invoked.',
      );
    }
    return d;
  }

  @override
  Future<Workspace> load() => _live.load();

  @override
  Future<void> save(Workspace workspace) => _live.save(workspace);

  @override
  Future<void> saveToPath(String path, Workspace workspace) =>
      _live.saveToPath(path, workspace);

  @override
  Future<Workspace> loadFromPath(String path) => _live.loadFromPath(path);

  @override
  Future<void> clear() => _live.clear();

  @override
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.wavecrux',
  }) => _live.sidecarPathFor(tabId, extension: extension);

  @override
  Future<void> deleteSidecar(
    String tabId, {
    String extension = '.wavecrux',
  }) => _live.deleteSidecar(tabId, extension: extension);
}
