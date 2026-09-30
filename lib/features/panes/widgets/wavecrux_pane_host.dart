// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/wavecrux_tab_payload.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/diagnostics/widgets/pane_render_stats_popover.dart';
import 'package:wavecrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:wavecrux/features/panes/providers/split_pane_allowed_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/tabs/wavecrux_viewer_tab_bar_strings.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/platform/reveal_tab_file.dart';
import 'package:wavecrux/shared/widgets/lazy_indexed_stack.dart';

/// WaveCrux adapter over the cross-suite [`crux.PaneHost`].
///
/// Wires the generic package pane host with WaveCrux's product-specific
/// behaviour via the package's additive seams:
/// - `stackBuilder` → [LazyIndexedStack] (one-at-a-time GPU surface init,
///   avoiding the Windows/Intel driver crash).
/// - `splitLayoutBuilder` → [_ResizablePaneRow] (drag-resizable splitter).
/// - `paneTrailingActionsBuilder` → the Pane Render Stats `i`-icon + the
///   split-pane-right button (preserving the `paneRenderStatsAnchor_<paneId>`
///   / `tabBarSplitPaneRightButton` keys).
/// - `contextMenuItems` → Duplicate Tab + Tab Diagnostics entries.
/// - `tabContainerFor` / `paneContainerFor` → WaveCrux's wrapper managers so
///   per-tab autosave arming and per-pane render-stats setup still run.
/// - sizing / leading-inset / chevron / device-gating seams.
class WaveCruxPaneHost extends ConsumerWidget {
  const WaveCruxPaneHost({required this.tabContentBuilder, super.key});

  /// Builds the per-tab content (toolbar + IdeLayout + status bar) for the
  /// supplied [`crux.WorkspaceTab`]. Invoked inside the per-tab
  /// [UncontrolledProviderScope] supplied by the package pane host.
  final Widget Function(
    BuildContext context,
    crux.WorkspaceTab<WaveCruxTabPayload> tab,
  )
  tabContentBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final l10n = L10N.of(context);
    final tcm = ref.read(tabContainerManagerProvider);
    final pcm = ref.read(paneContainerManagerProvider);

    final showTabBars =
        deviceClass != DeviceClass.phone &&
        deviceClass != DeviceClass.phoneLandscape;
    final enableSplitPane = _splitAllowed(context, deviceClass);

    return crux.PaneHost<WaveCruxTabPayload>(
      provider: workspaceProvider,
      tabContentBuilder: tabContentBuilder,
      tabContainerFor: tcm.containerFor,
      paneContainerFor: pcm.containerFor,
      // Never rendered: ViewerScreen branches on the empty workspace before
      // mounting the pane host, so the workspace here always has tabs.
      emptyCanvasContent: const SizedBox.shrink(),
      // No `defaultPayloadBuilder`: WaveCrux intentionally omits the tab-bar
      // "+" new-tab button. A blank tab is a dead-end — opening a file always
      // spawns a fresh tab rather than filling a
      // placeholder, and a blank tab exposes no in-tab affordance to load
      // anything. Streaming/duplicate flows still create placeholder tabs via
      // `WaveCruxWorkspaceNotifier.newTab` directly.
      strings: WaveCruxViewerTabBarStrings(l10n),
      sizing: crux.ViewerTabBarSizing(
        barHeight: metrics.toolbarHeight,
        iconSize: metrics.iconSize,
      ),
      tabBarLeadingInset: windowChromeLeftResizeEdge,
      autoHideScrollChevrons: true,
      showTabBars: showTabBars,
      enableSplitPane: enableSplitPane,
      // Browser-style whole-chip drag (no handle icon) + a leading insertion
      // drop slot, matching the pre-consolidation tab strip.
      useDragHandle: false,
      // Hover/long-press tooltip surfaces the full file path (the chip label
      // itself is the truncated display name).
      tabTooltipBuilder: (tab) => tab.payload.filePath ?? tab.displayName,
      // The active pane uses a full-strength primary border so the focused
      // pane is unmistakable; the inactive pane keeps a faint at-rest divider
      // rather than vanishing entirely. Two refinements:
      //
      // - Issue #46: when un-split (a single pane), there is no other pane to
      //   disambiguate, so the active-pane indicator communicates nothing and
      //   is suppressed entirely — a fully transparent border, matching VS Code
      //   and JetBrains. The 3 dp width is retained (transparent) so the
      //   content geometry is identical whether split or not: opening a second
      //   pane never shifts the canvas.
      //
      // - Issue #45: the border width is locked at 3 dp for BOTH the active and
      //   inactive states. `Border.all` paints inside the widget bounds, so the
      //   old 3↔1 width swap on focus change consumed 2 dp of content per side
      //   and visibly squeezed the waveform canvas and signal tree on every
      //   focus switch. Only the colour changes now; the content area is fixed.
      paneBorderBuilder: (context, {required isActive, required isSplit}) {
        final colorScheme = Theme.of(context).colorScheme;
        if (!isSplit) {
          return Border.all(color: Colors.transparent, width: 3);
        }
        return Border.all(
          color: isActive
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 3,
        );
      },
      stackBuilder: (index, children) =>
          LazyIndexedStack(index: index, children: children),
      splitLayoutBuilder: (context, panes) =>
          _ResizablePaneRow(children: panes),
      paneTrailingActionsBuilder: (context, paneId) =>
          _PaneTrailingActions(paneId: paneId, metrics: metrics),
      contextMenuBuilder: (menuContext, tab) =>
          _contextMenu(menuContext, ref, tab),
    );
  }

  /// Whether the current device class supports split-pane — the shared
  /// [isSplitPaneAllowed] rule, measured against this host's window width.
  static bool _splitAllowed(BuildContext context, DeviceClass deviceClass) =>
      isSplitPaneAllowed(deviceClass, MediaQuery.sizeOf(context).width);

  /// Fully composes the tab chip's context menu, reproducing the
  /// pre-consolidation order: a non-interactive monospace full-path header
  /// (per ARCHITECTURE.md §3.1.8.14), Duplicate, Move to New Window (disabled
  /// until Flutter multi-window is stable), Reveal in Finder/Explorer/Files,
  /// then — when diagnostics are available — Tab Diagnostics, then the close
  /// block.
  List<PopupMenuEntry<Object>> _contextMenu(
    BuildContext context,
    WidgetRef ref,
    crux.WorkspaceTab<WaveCruxTabPayload> tab,
  ) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final deviceClass = ref.read(deviceClassProvider);
    final tabDiagnosticsAvailable =
        deviceClass != DeviceClass.phone &&
        deviceClass != DeviceClass.phoneLandscape &&
        ref.read(diagnosticsEnabledProvider);
    final filePath = tab.payload.filePath;
    final workspace = ref.read(workspaceProvider).value;
    final paneTabs = workspace == null
        ? const <crux.WorkspaceTab<WaveCruxTabPayload>>[]
        : workspace.tabs.where((t) => t.paneId == tab.paneId).toList();
    final index = paneTabs.indexWhere((t) => t.id == tab.id);

    return [
      // Full path header (non-interactive, monospace) — ARCHITECTURE §3.1.8.14.
      if (filePath != null) ...[
        PopupMenuItem<Object>(
          enabled: false,
          height: 36,
          child: Text(
            filePath,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const PopupMenuDivider(),
      ],
      PopupMenuItem<Object>(
        onTap: () => unawaited(_duplicateTab(ref, tab)),
        child: Text(l10n.tabContextMenuDuplicateTab),
      ),
      // Always present but disabled until Flutter multi-window reaches stable.
      PopupMenuItem<Object>(
        enabled: crux.kMultiWindowAvailable,
        child: Tooltip(
          message: crux.kMultiWindowAvailable
              ? ''
              : l10n.viewerTabBarMultiWindowUnavailableTooltip,
          triggerMode: TooltipTriggerMode.manual,
          child: Text(l10n.tabContextMenuMoveToNewWindow),
        ),
      ),
      if (filePath != null)
        PopupMenuItem<Object>(
          onTap: () => _revealInFilesystem(filePath),
          child: Text(_revealLabel(l10n)),
        ),
      if (tabDiagnosticsAvailable) ...[
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          onTap: () {
            ref.read(activeTabIdProvider.notifier).activate(tab.id);
            unawaited(TabDiagnosticsDrawer.open(context));
          },
          child: Text(l10n.tabContextMenuTabDiagnostics),
        ),
      ],
      const PopupMenuDivider(),
      PopupMenuItem<Object>(
        onTap: () => unawaited(ref.wavecruxWorkspace.closeTab(tab.id)),
        child: Text(l10n.tabContextMenuCloseTab),
      ),
      if (paneTabs.length > 1)
        PopupMenuItem<Object>(
          onTap: () => unawaited(_closeOtherTabs(ref, tab, paneTabs)),
          child: Text(l10n.tabContextMenuCloseOtherTabs),
        ),
      if (index >= 0 && index < paneTabs.length - 1)
        PopupMenuItem<Object>(
          onTap: () => unawaited(_closeTabsToRight(ref, paneTabs, index)),
          child: Text(l10n.tabContextMenuCloseTabsToRight),
        ),
    ];
  }

  /// Platform-specific label for the "Reveal" menu item.
  String _revealLabel(L10N l10n) {
    if (kIsWeb) return l10n.tabContextMenuRevealInFinder;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return l10n.tabContextMenuRevealInExplorer;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return l10n.tabContextMenuRevealInFiles;
    }
    return l10n.tabContextMenuRevealInFinder;
  }

  /// Best-effort folder reveal via the shared `crux_io` helper (macOS
  /// `open -R`, Windows `explorer /select`, Linux FileManager1/xdg-open);
  /// the web build's shim no-ops. Replaced a silent no-op stub that made
  /// the menu item do nothing on every platform.
  void _revealInFilesystem(String filePath) => revealTabFile(filePath);

  Future<void> _closeOtherTabs(
    WidgetRef ref,
    crux.WorkspaceTab<WaveCruxTabPayload> keep,
    List<crux.WorkspaceTab<WaveCruxTabPayload>> paneTabs,
  ) async {
    final notifier = ref.wavecruxWorkspace;
    for (final t in [...paneTabs]) {
      if (t.id != keep.id) await notifier.closeTab(t.id);
    }
  }

  Future<void> _closeTabsToRight(
    WidgetRef ref,
    List<crux.WorkspaceTab<WaveCruxTabPayload>> paneTabs,
    int index,
  ) async {
    final notifier = ref.wavecruxWorkspace;
    for (var i = paneTabs.length - 1; i > index; i--) {
      await notifier.closeTab(paneTabs[i].id);
    }
  }

  /// Duplicates [tab]: a placeholder tab clones to a fresh placeholder; a
  /// file-backed tab re-opens the same file in a new tab and replays the
  /// source tab's session snapshot (signals, cursors, markers, zoom, panels).
  Future<void> _duplicateTab(
    WidgetRef ref,
    crux.WorkspaceTab<WaveCruxTabPayload> tab,
  ) async {
    final notifier = ref.wavecruxWorkspace;
    final filePath = tab.payload.filePath;
    if (filePath == null) {
      await notifier.newTab(displayName: tab.displayName, paneId: tab.paneId);
      return;
    }
    final tcm = ref.read(tabContainerManagerProvider);
    final sourceSession = tcm
        .containerFor(tab.id)
        .read(sessionProvider.notifier)
        .snapshot();
    final newTabId = await notifier.openFile(
      filePath,
      displayName: tab.displayName,
      paneId: tab.paneId,
    );
    await tcm
        .containerFor(newTabId)
        .read(sessionProvider.notifier)
        .restoreFromState(sourceSession);
  }
}

/// Per-pane trailing affordances rendered after the tab bar's "+" button:
/// the Pane Render Stats `i`-icon and the split-pane-right
/// button. Both preserve their original [ValueKey]s so existing widget /
/// integration tests keep finding them.
class _PaneTrailingActions extends ConsumerWidget {
  const _PaneTrailingActions({required this.paneId, required this.metrics});

  final PaneId paneId;
  final MobileMetrics metrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final tabDiagnosticsAvailable =
        deviceClass != DeviceClass.phone &&
        deviceClass != DeviceClass.phoneLandscape &&
        ref.watch(diagnosticsEnabledProvider);

    final workspace = ref.watch(workspaceProvider).value;
    final paneTabCount =
        workspace?.tabs.where((t) => t.paneId == paneId).length ?? 0;
    final canSplit =
        workspace != null &&
        workspace.panes.length == 1 &&
        WaveCruxPaneHost._splitAllowed(context, deviceClass) &&
        paneTabCount >= 2;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tabDiagnosticsAvailable)
          Builder(
            builder: (anchorContext) => SizedBox(
              width: metrics.toolbarButton,
              height: metrics.toolbarHeight,
              child: IconButton(
                key: ValueKey('paneRenderStatsAnchor_${paneId.value}'),
                padding: EdgeInsets.zero,
                iconSize: metrics.iconSize,
                tooltip: l10n.paneRenderStatsAnchorTooltip,
                onPressed: () => PaneRenderStatsPopover.showAnchoredTo(
                  anchorContext,
                  paneId: paneId,
                ),
                icon: const Icon(Icons.info_outline),
              ),
            ),
          ),
        if (canSplit)
          SizedBox(
            width: metrics.toolbarButton,
            height: metrics.toolbarHeight,
            child: IconButton(
              key: const ValueKey('tabBarSplitPaneRightButton'),
              padding: EdgeInsets.zero,
              iconSize: metrics.iconSize,
              tooltip: l10n.tabBarSplitPaneRightTooltip,
              onPressed: () => unawaited(_splitAndMoveRightmost(ref)),
              icon: const Icon(Icons.vertical_split),
            ),
          ),
      ],
    );
  }

  /// Creates a second pane and moves the rightmost tab of this pane into it,
  /// so the new pane is never empty. The destination pane becomes active and
  /// the moved tab is selected.
  Future<void> _splitAndMoveRightmost(WidgetRef ref) async {
    final notifier = ref.wavecruxWorkspace;
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null) return;
    final paneTabs = workspace.tabs.where((t) => t.paneId == paneId).toList();
    if (paneTabs.length < 2) return;
    final rightmost = paneTabs.last;
    final newPaneId = await notifier.splitPane();
    await notifier.moveTabToPane(rightmost.id, newPaneId);
    ref.read(activeTabIdProvider.notifier).activate(rightmost.id);
  }
}

/// Row that renders two panes with a drag-resizable splitter between them.
/// Holds the user's split fraction in local state; resets to 0.5 whenever the
/// [children] identity changes (e.g. unsplit → split). Moved verbatim from the
/// pre-consolidation local `PaneHost`.
class _ResizablePaneRow extends StatefulWidget {
  const _ResizablePaneRow({required this.children});

  final List<Widget> children;

  @override
  State<_ResizablePaneRow> createState() => _ResizablePaneRowState();
}

class _ResizablePaneRowState extends State<_ResizablePaneRow> {
  static const double _kSplitterWidth = 6;
  static const double _kHitWidth = 12;
  static const double _kMinPaneWidthDp = 240;

  double _leftFraction = 0.5;

  @override
  Widget build(BuildContext context) {
    if (widget.children.length != 2) {
      return Row(
        children: [
          for (final c in widget.children) Expanded(child: c),
        ],
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final usable = (totalWidth - _kHitWidth).clamp(0.0, double.infinity);
        final minFrac = usable > 0
            ? (_kMinPaneWidthDp / usable).clamp(0.0, 0.5)
            : 0.0;
        final maxFrac = 1.0 - minFrac;
        final clampedFrac = _leftFraction.clamp(minFrac, maxFrac);
        final leftWidth = usable * clampedFrac;
        final rightWidth = usable - leftWidth;

        return Row(
          children: [
            SizedBox(width: leftWidth, child: widget.children[0]),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  if (usable <= 0) return;
                  setState(() {
                    final next = (leftWidth + details.delta.dx) / usable;
                    _leftFraction = next.clamp(minFrac, maxFrac);
                  });
                },
                child: SizedBox(
                  width: _kHitWidth,
                  child: Center(
                    child: Container(
                      width: _kSplitterWidth,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: rightWidth, child: widget.children[1]),
          ],
        );
      },
    );
  }
}
