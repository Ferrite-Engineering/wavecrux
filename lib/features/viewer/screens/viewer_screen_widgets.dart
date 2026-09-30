// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The viewer screen's private collaborators: the two IdePanelLayout adapters
// and the four widgets the screen composes its chrome from.
//
// These are not part of `_ViewerScreenState` at all — they are separate
// top-level classes that happened to live below it because that is where you
// write a private widget in Dart. Moving them costs nothing and takes 350
// lines out of the file somebody opens to read the screen.
//
//   * `_WaveCruxIdePanelLayout` / `_WaveCruxIdePanelLayoutSink` — the read and
//     write halves of the `crux_ide_layout` adapter pair, projecting the
//     screen's panel providers onto the shared IDE shell.
//   * `_PaneScopedCanvas` — wraps the waveform canvas in its pane's
//     `UncontrolledProviderScope`, which is what makes split-pane per-pane
//     state work at all.
//   * `_ScreenContent`, `_ActivePaneToolbar`, `_BaseToolbar` — the chrome
//     composition.
//   * `_RemoveMarkerDialog` — the letter-picker for marker removal.
//   * `_FocusableWaveformPane`, `_TabBottomChrome` — the tab's focusable,
//     named center pane and its bottom-chrome keyboard region.
//
// A part file rather than a new library because they are private to
// `viewer_screen.dart` by design: `_PaneScopedCanvas` and `_ScreenContent`
// take the screen's own callbacks, and making them public to move them would
// widen the screen's API for a file split, which is the opposite of the point.

part of 'viewer_screen.dart';

/// Read-side adapter: a tab's [PanelLayoutState] → [IdePanelLayout]
/// (signalTree→left, valueColumn→right, transactionView→bottom), folding in the
/// phone-width force-hide (ARCHITECTURE §3.1.7) so a phone-class window hides
/// every side / bottom pane while the user's preferences are preserved. Sizes
/// are fixed pixel values — WaveCrux does not persist drag-resize sizes; the
/// 120dp center floor is supplied separately to [CruxIdeLayout].
class _WaveCruxIdePanelLayout implements IdePanelLayout {
  const _WaveCruxIdePanelLayout(
    this._state, {
    required this.isPhone,
    this.defaultLeft = 280,
    this.defaultRight = 220,
  });

  final PanelLayoutState _state;
  final bool isPhone;

  /// Default left/right pane widths (logical px) when the user has not dragged
  /// a splitter. Widened on ultrawide viewports and narrowed below 800 dp —
  /// see [paneDefaultsForViewport].
  final double defaultLeft;
  final double defaultRight;

  @override
  bool get leftVisible => !isPhone && _state.signalTreeVisible;

  @override
  PaneSize? get leftSize => PaneSize.pixel(_state.leftPaneSize ?? defaultLeft);

  @override
  bool get rightVisible => !isPhone && _state.valueColumnVisible;

  @override
  PaneSize? get rightSize =>
      PaneSize.pixel(_state.rightPaneSize ?? defaultRight);

  @override
  bool get bottomVisible => !isPhone && _state.transactionViewVisible;

  @override
  PaneSize? get bottomSize => _state.bottomDockMaximized
      // Maximize: report an effectively-infinite height and let the
      // CruxIdeLayout fit clamp cap it at the window minus the center floor.
      // The user's real size stays in bottomPaneSize, so restoring is just
      // clearing the flag.
      ? PaneSize.pixel(100000)
      : PaneSize.pixel(_state.bottomPaneSize ?? kDefaultBottomPaneSize);
}

/// Write-side adapter: drag-to-collapse and drag-to-resize → this tab's
/// [PanelLayoutNotifier]. Both visibility and pane sizes are persisted in the
/// session sidecar so a relaunch restores the user's pane geometry.
class _WaveCruxIdePanelLayoutSink implements IdePanelLayoutSink {
  const _WaveCruxIdePanelLayoutSink(this._notifier);

  final PanelLayoutNotifier _notifier;

  @override
  void setLeftVisible({required bool visible}) =>
      _notifier.setSignalTreeVisible(visible: visible);

  @override
  void setRightVisible({required bool visible}) =>
      _notifier.setValueColumnVisible(visible: visible);

  @override
  void setBottomVisible({required bool visible}) =>
      _notifier.setTransactionViewVisible(visible: visible);

  @override
  void setLeftSize(double pixels) => _notifier.setLeftPaneSize(pixels);

  @override
  void setRightSize(double pixels) => _notifier.setRightPaneSize(pixels);

  @override
  void setBottomSize(double pixels) => _notifier.setBottomPaneSize(pixels);
}

/// Wraps the WaveformViewCenter (and every widget inside it that reads
/// `renderStatsCollectorProvider`) in a per-pane [ProviderScope] override so
/// canvas paint events land on THIS pane's [RenderStatsCollector] instance
/// instead of the root singleton.
///
/// Why this is necessary: per-tab ProviderContainers are parented to root,
/// not to the hosting pane's container, so reading `renderStatsCollectorProvider`
/// from a Consumer inside the per-tab scope resolves to the root default —
/// silently bypassing the per-pane override [PaneContainerManager] installs in
/// each pane container. The canvas's paint events therefore all landed on
/// the root collector, leaving every per-pane bridge listening to a collector
/// that never fired. A nested [ProviderScope] here installs the per-pane
/// collector as the nearest scope for the canvas subtree, so paint events
/// land on the right instance, the per-pane bridge fires, and the per-pane
/// notifier (read by [LiveStatisticsStrip] and [PaneRenderStatsPopover]) is
/// populated with real data.
class _PaneScopedCanvas extends ConsumerWidget {
  const _PaneScopedCanvas({
    required this.paneId,
    required this.repaintKey,
    required this.child,
  });

  final PaneId paneId;
  final GlobalKey repaintKey;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve the pane's collector instance once. The instance is stable for
    // the lifetime of the pane (PaneContainerManager creates it on first
    // containerFor() and tears it down only when the pane closes).
    final paneCollector = ref
        .read(paneContainerManagerProvider)
        .containerFor(paneId)
        .read(renderStatsCollectorProvider);

    return ProviderScope(
      overrides: [
        renderStatsCollectorProvider.overrideWithValue(paneCollector),
      ],
      child: RepaintBoundary(
        key: repaintKey,
        child: child,
      ),
    );
  }
}

/// Screen-level chrome built ONCE (Issue 3): a single ViewerToolbar above the
/// body (empty-canvas or PaneHost). The toolbar's visibility flags and toggle
/// targets follow the active pane via [_ActivePaneScope]. Statistics strip and
/// status bar are NOT rendered here — they live inside per-pane content so
/// each pane keeps its own chrome below its IdeLayout (the strip and status
/// bar carry per-pane state and the chevrons must target the pane they're in).
class _ScreenContent extends ConsumerWidget {
  const _ScreenContent({
    required this.tabs,
    required this.activeTabId,
    required this.tcm,
    required this.paneMetrics,
    required this.colorScheme,
    required this.isPhoneWidth,
    required this.onOpenFile,
    required this.onCloseFile,
    required this.onSaveSession,
    required this.onSaveSessionAs,
    required this.onExport,
    required this.onSearch,
    required this.onAddDecoder,
    required this.onOpenWorkspace,
    required this.onOpenSample,
    required this.onOpenRecentFile,
    required this.onOpenRecentWorkspace,
    required this.onOpenOtherTab,
    required this.onOpenFromBytes,
    required this.onShortcutAction,
    required this.onShowBottomPanelSheet,
    required this.buildTabContent,
  });

  final List<WavecruxTab> tabs;
  final TabId activeTabId;
  final TabContainerManager tcm;
  final MobileMetrics paneMetrics;
  final ColorScheme colorScheme;
  final bool isPhoneWidth;
  final VoidCallback onOpenFile;
  final VoidCallback onCloseFile;
  final VoidCallback onSaveSession;
  final VoidCallback onSaveSessionAs;
  final VoidCallback onExport;
  final VoidCallback onSearch;
  final VoidCallback onAddDecoder;
  final VoidCallback onOpenWorkspace;
  final VoidCallback onOpenSample;
  final Future<void> Function(String filePath) onOpenRecentFile;
  final Future<void> Function(String workspacePath)? onOpenRecentWorkspace;
  final Future<void> Function(WorkspaceTab tab)? onOpenOtherTab;
  final void Function(Uint8List bytes, String name)? onOpenFromBytes;
  final void Function(ShortcutAction) onShortcutAction;
  final VoidCallback? onShowBottomPanelSheet;
  final Widget Function(BuildContext context, WorkspaceTab tab) buildTabContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The toolbar's indicators read the **ambient** per-tab
    // panelLayoutProvider; the caller scopes it to the active tab. Resolve the
    // active tab's container once for the PaneHost branch (the empty-canvas
    // branch already wraps its whole column in that scope, so the toolbar there
    // is scoped by the outer UncontrolledProviderScope — wrapping again would
    // nest two scopes for the same container and crash on dispose).
    final toolbar = _ActivePaneToolbar(onShortcutAction: onShortcutAction);

    if (tabs.isEmpty) {
      return UncontrolledProviderScope(
        // Namespaced so it never collides with a tab chip's `ValueKey(tab.id)`
        // (see tab_drag_reorder regression).
        key: ValueKey('tabScope.empty:${activeTabId.value}'),
        container: tcm.containerFor(activeTabId),
        child: Column(
          children: [
            CruxFocusRegion(child: toolbar),
            Expanded(
              // The start screen is where lost focus goes back to.
              child: CruxFocusRegion(
                primary: true,
                child: WaveCruxEmptyCanvas(
                  onOpenFile: onOpenFile,
                  onOpenSample: onOpenSample,
                  onOpenWorkspace: onOpenWorkspace,
                  onOpenRecentFile: onOpenRecentFile,
                  onOpenRecentWorkspace: onOpenRecentWorkspace,
                  onOpenOtherTab: onOpenOtherTab,
                  onOpenFromBytes: onOpenFromBytes,
                ),
              ),
            ),
            CruxFocusRegion(
              child: Column(
                children: [
                  if (ref.watch(deviceClassProvider) == DeviceClass.desktop)
                    // The strip reads its own disclosure state from the
                    // active tab's scope — it is mounted inside the
                    // surrounding UncontrolledProviderScope, so it sees the
                    // same per-tab panelLayoutProvider the toolbar does.
                    const AnimatedSize(
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: LiveStatisticsStrip(),
                    ),
                  StatusBar(onShowBottomPanelSheet: onShowBottomPanelSheet),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // PaneHost branch: the toolbar is a sibling of PaneHost (outside any tab's
    // scope). It reads the active tab's panel state via the root-scope
    // [activeTabPanelLayoutProvider] bridge, so it needs no tab scope of its
    // own — mounting a second UncontrolledProviderScope for the active tab's
    // container would race PaneHost's scope and crash mid-build.
    return Column(
      children: [
        CruxFocusRegion(child: toolbar),
        Expanded(
          child: WaveCruxPaneHost(tabContentBuilder: buildTabContent),
        ),
      ],
    );
  }
}

/// Toolbar that reads its panel-state-driven indicators (transaction table
/// visible? Stage panel visible?) from the root-scope [activeTabPanelLayoutProvider]
/// — a bridge that mirrors the active tab's per-tab `panelLayoutProvider`. The
/// toolbar lives outside any tab's scope, so it must NOT enter a tab container
/// (a second [UncontrolledProviderScope] over the active tab's container races
/// PaneHost's scope and throws "markNeedsBuild during build" while the tab's
/// providers churn). Watching the root bridge avoids that entirely.
/// Action handlers route through [onShortcutAction] so keyboard / menu /
/// toolbar paths all hit the same dispatcher, and the dispatcher's
/// `_togglePanelOnActiveTab` is the single point of tab targeting.
class _ActivePaneToolbar extends ConsumerWidget {
  const _ActivePaneToolbar({required this.onShortcutAction});

  final void Function(ShortcutAction) onShortcutAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeTabPanelLayoutProvider);
    return _BaseToolbar(
      // Dock-aware glyphs: "visible" means that tab is the one on screen,
      // not merely that its feature flag is on behind another tab.
      isTransactionTableVisible: state.bottomDockShowsTransactions,
      isStagePanelVisible: state.bottomDockShowsStage,
      onShortcutAction: onShortcutAction,
    );
  }
}

class _BaseToolbar extends StatelessWidget {
  const _BaseToolbar({
    required this.isTransactionTableVisible,
    required this.isStagePanelVisible,
    required this.onShortcutAction,
  });

  final bool isTransactionTableVisible;
  final bool isStagePanelVisible;
  final void Function(ShortcutAction) onShortcutAction;

  @override
  Widget build(BuildContext context) {
    // Every button dispatches a ShortcutAction through the one handler, so the
    // per-button callback bag is gone: the screen's `_handleShortcut` already
    // knows how to open a file, save a session, stop streaming, open Settings
    // and open App Diagnostics.
    return ViewerToolbar(
      onShortcutAction: onShortcutAction,
      isTransactionTableVisible: isTransactionTableVisible,
      isStagePanelVisible: isStagePanelVisible,
    );
  }
}

// ── Remove-marker dialog ──────────────────────────────────────────────────────

/// A dialog that lists the currently-set marker letters so the user can delete
/// one. Returns the selected letter, or null if cancelled.
///
/// Setting and jumping to markers use the `M` / `⇧M` keyboard chords (no
/// dialog); only removal needs a picker, and it shows just the markers that
/// actually exist.
class _RemoveMarkerDialog extends StatelessWidget {
  const _RemoveMarkerDialog({required this.letters});

  /// Currently-set marker letters (a–z), already sorted.
  final List<String> letters;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.markerRemoveTitle),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final letter in letters)
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => Navigator.of(context).pop(letter),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.markerDialogCancel),
        ),
      ],
    );
  }
}

/// The center pane of a tab: a Tab stop that takes focus when the tab
/// appears.
///
/// Focus here gives keyboard shortcuts a focused widget inside the screen's
/// `Actions` to fire from, and gives a screen reader the pane's own summary
/// ("2 signals, cursor at …", or the load error) to announce. The semantics
/// container keeps that summary on this pane: without it the canvas label
/// floated up to a node enclosing every dock, and each dock control was
/// announced inside "Waveform viewer".
class _FocusableWaveformPane extends StatelessWidget {
  const _FocusableWaveformPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Focus(autofocus: true, debugLabel: 'Waveform pane', child: child),
  );
}

/// A tab's bottom chrome — the live statistics strip and the status bar —
/// as one keyboard region (an F6 stop).
class _TabBottomChrome extends StatelessWidget {
  const _TabBottomChrome({
    required this.paneId,
    required this.showStatisticsStrip,
    required this.onShowBottomPanelSheet,
  });

  final PaneId paneId;
  final bool showStatisticsStrip;
  final VoidCallback? onShowBottomPanelSheet;

  @override
  Widget build(BuildContext context) => CruxFocusRegion(
    child: Column(
      children: [
        if (showStatisticsStrip)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            // The strip is always mounted on desktop and owns its own
            // disclosure row (suite-wide behaviour); expanding and collapsing
            // changes its height, which is what AnimatedSize is here for. Its
            // *content* is per-pane — it receives `paneId` so its segments
            // (paint time, render time, FPS, sparkline) source from THIS
            // pane's render-stats notifier.
            child: LiveStatisticsStrip(paneId: paneId),
          ),
        // The StatusBar reads/writes this tab's own [panelLayoutProvider] (it
        // is rendered inside the tab's container), so the chevrons toggle
        // THIS tab's panels. On phone widths the IdeLayout bottom pane is
        // force-hidden; the chevron tap routes through a modal bottom sheet
        // so the user can still inspect the active bottom-panel content
        // (transactions, Stage, FSM, x-trace, activity, cocotb).
        StatusBar(onShowBottomPanelSheet: onShowBottomPanelSheet),
      ],
    ),
  );
}
