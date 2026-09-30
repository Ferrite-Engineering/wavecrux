// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_dock/crux_dock.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/ai/providers/explain_selection_provider.dart';
import 'package:wavecrux/features/ai/widgets/explain_selection_result_panel.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/widgets/annotations_panel.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_log_panel.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/rename_stage_panel_dialog.dart';
import 'package:wavecrux/features/stage/widgets/stage_panel.dart';
import 'package:wavecrux/features/stage/widgets/stage_playback_actions.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_picker_dialog.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/widgets/activity_report_panel.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_panel.dart';
import 'package:wavecrux/features/viewer/widgets/x_trace_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/extra_bottom_dock_tabs_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// WaveCrux's bottom dock — the VSCode-style tab strip over every surface
/// that can occupy the bottom region.
///
/// Replaces the retired 8-deep priority chain (Stage > FSM > X-Trace >
/// Activity > Explain > Cocotb > Pro extras > Transactions), where eight
/// visibility flags fought over one widget slot and "first true wins" hid
/// everything behind the winner. Every candidate is now a [CruxDockEntry]:
///
/// - **Transactions** is the one pinned tab — always listed, never closable.
/// - **Stage** contributes one *dynamic* tab per Stage panel (the user's
///   confirmed model: top-level tabs, not VSCode's inner terminal list),
///   labeled with the panel's user-given name. Turning the feature on seeds
///   a default panel (no create-first interstitial); a stage tab's `×`
///   removes that panel, and closing the last one turns the feature off.
/// - **FSM / X-Trace / Activity / Explain** are on-demand: present while
///   their analysis is active, and their `×` *clears the analysis* — closing
///   the tab and deactivating the feature are the same thing.
/// - **Cocotb** is present while its panel flag is on (loading a log
///   auto-flips it, which auto-reveals the tab).
/// - **Pro extras** ([extraBottomDockTabsProvider]) map straight onto
///   entries — the `BottomDockTab` seam carried an icon and a label resolver
///   "for any future tab-strip presentation" since it shipped; this is that
///   presentation. They are not closable: the seam exposes visibility as a
///   read-only listenable, and the Pro side owns hiding.
///
/// Mounted per-tab inside `CruxIdeLayout`'s bottom region, so every read
/// resolves this tab's providers, and each workspace tab keeps its own dock
/// arrangement.
class WaveCruxBottomDock extends ConsumerWidget {
  /// Creates the bottom dock.
  const WaveCruxBottomDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final panelState = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);
    final stageWs = ref.watch(stageWorkspaceProvider);

    return CruxDock(
      entries: buildBottomDockEntries(context, ref),
      activeId: resolveBottomDockActiveId(panelState, stageWs),
      onSelect: (id) => selectBottomDockTab(ref, id),
      onAutoReveal: notifier.revealBottomDockTab,
      dockId: kDockRegionBottom,
      onTabMovedIn: (id, _) => notifier.moveDockTab(id, kDockRegionBottom),
      onCollapse: () => notifier.setTransactionViewVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      onMaximize: notifier.toggleBottomDockMaximized,
      isMaximized: panelState.bottomDockMaximized,
      maximizeTooltip: l10n.dockMaximizeTooltip,
      restoreTooltip: l10n.dockRestoreTooltip,
      semanticsLabel: l10n.accessibilityBottomDockRegion,
    );
  }
}

/// The phone presentation of the bottom dock: the same entries, the same
/// select-and-persist wiring, hosted inside the modal bottom sheet the
/// status bar's phone chevron opens. One entry list, two presentations —
/// the retired priority chain no longer survives anywhere.
///
/// Collapse maps to dismissing the sheet; maximize and pop-out are
/// desktop-region concerns and are omitted.
class WaveCruxBottomDockSheet extends ConsumerWidget {
  /// Creates the sheet-hosted dock.
  const WaveCruxBottomDockSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final panelState = ref.watch(panelLayoutProvider);
    final stageWs = ref.watch(stageWorkspaceProvider);
    return CruxDock(
      entries: buildBottomDockEntries(context, ref),
      activeId: resolveBottomDockActiveId(panelState, stageWs),
      onSelect: (id) => selectBottomDockTab(ref, id),
      onCollapse: () => Navigator.of(context).pop(),
      collapseTooltip: l10n.dockCollapseTooltip,
      semanticsLabel: l10n.accessibilityBottomDockRegion,
    );
  }
}

/// Assembles the bottom dock's entry list — shared by the desktop region
/// dock and the phone sheet, so presence semantics can never fork between
/// the two presentations.
List<CruxDockEntry> buildBottomDockEntries(
  BuildContext context,
  WidgetRef ref,
) {
  final l10n = L10N.of(context);
  final panelState = ref.watch(panelLayoutProvider);
  final notifier = ref.read(panelLayoutProvider.notifier);
  final stageWs = ref.watch(stageWorkspaceProvider);

  return <CruxDockEntry>[
    CruxDockEntry(
      id: kBottomDockTabTransactions,
      icon: Icons.table_chart_outlined,
      label: l10n.dockTabTransactions,
      builder: (_) => const TransactionTablePanel(),
    ),
    // Stage — dynamic per-panel tabs (top-level, per the confirmed model).
    // No empty-workspace tab: turning the feature on seeds a default panel
    // (see `ShortcutAction.toggleStagePanel`), and closing the last panel's
    // tab turns the feature off.
    if (panelState.stageViewVisible)
      for (final panel in stageWs.panels)
        CruxDockEntry(
          id: '$kBottomDockStagePrefix${panel.id}',
          icon: Icons.dashboard_customize_outlined,
          label: panel.name,
          builder: (_) => const StagePanel(),
          actions: [
            // The Stage Playback transport (play/pause · speed · loop ·
            // follow) — the one playback surface, replacing both the
            // panel-bottom transport row and the main toolbar's glyph.
            ...stagePlaybackDockActions(context, ref),
            _dockAction(
              icon: Icons.drive_file_rename_outline,
              tooltip: l10n.stageTabRenameTooltip,
              onPressed: () => unawaited(
                _renamePanel(context, ref, panel.id, panel.name),
              ),
            ),
            _dockAction(
              icon: Icons.add_circle_outline,
              tooltip: l10n.stagePanelAddPanelTooltip,
              onPressed: () => unawaited(_createPanel(context, ref)),
            ),
            _dockAction(
              icon: Icons.add,
              tooltip: l10n.stagePanelAddWidgetTooltip,
              onPressed: () => StageWidgetPickerDialog.show(
                context,
                tabContainer: ProviderScope.containerOf(
                  context,
                  listen: false,
                ),
              ),
            ),
          ],
          // Closing the last panel's tab turns the Stage feature off —
          // there is no empty-workspace state to fall back to.
          onClose: () {
            final ws = ref.read(stageWorkspaceProvider);
            ref.read(stageWorkspaceProvider.notifier).removePanel(panel.id);
            if (ws.panels.length <= 1) {
              notifier.setStageViewVisible(visible: false);
            }
          },
        ),
    // On-demand analyses + Cross-Probe currently homed here — movable by
    // drag to the right dock (and back).
    ...movableDockEntries(context, ref, region: kDockRegionBottom),
    // Pro-contributed tabs (AI Advisor, SVA summary).
    ..._proEntries(context, ref),
  ];
}

/// The movable on-demand entries currently placed in [region] — the analyses
/// + Cocotb (native to the bottom dock) and Cross-Probe (native to the right
/// dock), each honouring a drag override in
/// [PanelLayoutState.dockPlacements]. Consumed by BOTH docks, so an entry can
/// never render in two regions or vanish from both.
List<CruxDockEntry> movableDockEntries(
  BuildContext context,
  WidgetRef ref, {
  required String region,
}) {
  final l10n = L10N.of(context);
  final panelState = ref.watch(panelLayoutProvider);
  final notifier = ref.read(panelLayoutProvider.notifier);

  bool placedHere(String id, String nativeRegion) =>
      panelState.dockRegionOf(id, nativeRegion) == region;

  return <CruxDockEntry>[
    if (placedHere(kBottomDockTabFsm, kDockRegionBottom) &&
        ref.watch(fsmProvider.select((s) => s.isActive)))
      CruxDockEntry(
        id: kBottomDockTabFsm,
        icon: Icons.account_tree_outlined,
        label: l10n.dockTabFsm,
        movable: true,
        builder: (_) => const FsmPanel(),
        onClose: () => ref.read(fsmProvider.notifier).clearFsm(),
      ),
    if (placedHere(kBottomDockTabXTrace, kDockRegionBottom) &&
        ref.watch(xTraceProvider.select((s) => s.isActive)))
      CruxDockEntry(
        id: kBottomDockTabXTrace,
        icon: Icons.timeline,
        label: l10n.xTracePanelTitle,
        movable: true,
        builder: (_) => const XTracePanel(),
        onClose: () => ref.read(xTraceProvider.notifier).clearTrace(),
      ),
    // Present when the tab has annotations, OR when the user opened the panel
    // deliberately — see `PanelLayoutState.annotationsPanelVisible` for why
    // that is a tri-state. Unlike the analysis panels this is not the result of
    // a run: it lists the user's own notes, its orphan groups only mean
    // anything if it is reachable, and **its empty state is where the
    // authoring gesture is explained**. Deriving presence from
    // `annotations.isNotEmpty` alone made that explanation unreachable — it
    // rendered only for users who already knew how to create one.
    if (placedHere(kBottomDockTabAnnotations, kDockRegionBottom) &&
        (panelState.annotationsPanelVisible ??
            ref.watch(annotationsProvider).isNotEmpty))
      CruxDockEntry(
        id: kBottomDockTabAnnotations,
        icon: Icons.sticky_note_2_outlined,
        label: l10n.annotationsPanelTitle,
        movable: true,
        builder: (_) => const AnnotationsPanel(),
        // Closes the panel, never the notes. Every other closable panel here
        // clears the thing it displays; this one must not, because the thing
        // it displays is the user's writing.
        onClose: () => notifier.setAnnotationsPanelVisible(visible: false),
      ),
    if (placedHere(kBottomDockTabActivity, kDockRegionBottom) &&
        ref.watch(switchingActivityProvider.select((s) => s.isActive)))
      CruxDockEntry(
        id: kBottomDockTabActivity,
        icon: Icons.bar_chart,
        label: l10n.dockTabActivity,
        movable: true,
        builder: (_) => const ActivityReportPanel(),
        onClose: () => ref.read(switchingActivityProvider.notifier).clear(),
      ),
    if (placedHere(kBottomDockTabExplain, kDockRegionBottom) &&
        ref.watch(explainSelectionProvider.select((s) => s.isActive)))
      CruxDockEntry(
        id: kBottomDockTabExplain,
        icon: Icons.psychology_outlined,
        label: l10n.explainSelectionPanelTitle,
        movable: true,
        builder: (_) => const ExplainSelectionResultPanel(),
        onClose: () => ref.read(explainSelectionProvider.notifier).close(),
      ),
    if (placedHere(kBottomDockTabCocotb, kDockRegionBottom) &&
        panelState.cocotbLogPanelVisible)
      CruxDockEntry(
        id: kBottomDockTabCocotb,
        icon: Icons.article_outlined,
        label: l10n.cocotbLogPanelTitle,
        movable: true,
        builder: (_) => const CocotbLogPanel(),
        onClose: () => notifier.setCocotbLogPanelVisible(visible: false),
      ),
    if (placedHere(kRightDockTabCrossProbe, kDockRegionRight) &&
        !ref.watch(deviceClassProvider).isPhoneClass &&
        panelState.crossProbeVisible)
      CruxDockEntry(
        id: kRightDockTabCrossProbe,
        icon: Icons.sensors_outlined,
        label: l10n.dockTabCrossProbe,
        movable: true,
        builder: (_) => const WaveCruxCrossProbePanel(),
        onClose: () => notifier.setCrossProbeVisible(visible: false),
      ),
  ];
}

/// The dock's active id, resolving the bare stage prefix (empty workspace /
/// legacy sessions) to the active stage panel's tab when panels exist.
String resolveBottomDockActiveId(
  PanelLayoutState panelState,
  StageWorkspaceState stageWs,
) {
  final effective = panelState.effectiveBottomDockTab;
  if (effective == kBottomDockStagePrefix && stageWs.panels.isNotEmpty) {
    final active = stageWs.activePanel ?? stageWs.panels.first;
    return '$kBottomDockStagePrefix${active.id}';
  }
  return effective;
}

/// Persists [id] as the active tab and, for stage tabs, drives the Stage
/// workspace's own active panel so the canvas, bindings pane and playback
/// transport follow.
void selectBottomDockTab(WidgetRef ref, String id) {
  ref.read(panelLayoutProvider.notifier).setBottomDockTab(id);
  if (id.startsWith(kBottomDockStagePrefix) &&
      id.length > kBottomDockStagePrefix.length) {
    ref
        .read(stageWorkspaceProvider.notifier)
        .selectPanel(id.substring(kBottomDockStagePrefix.length));
  }
}

List<CruxDockEntry> _proEntries(BuildContext context, WidgetRef ref) {
  final extraTabs = ref.watch(extraBottomDockTabsProvider);
  if (extraTabs.isEmpty) return const [];
  final currentTier = ref.watch(licenseTierProvider);
  return [
    for (final tab in extraTabs)
      if (FeatureGate.isAvailable(tab.requiredTier, currentTier) &&
          ref.watch(tab.visibilityProvider))
        CruxDockEntry(
          id: tab.id,
          icon: tab.icon,
          label: tab.labelResolver(context),
          builder: tab.builder,
        ),
  ];
}

Future<void> _createPanel(BuildContext context, WidgetRef ref) async {
  final l10n = L10N.of(context);
  final name = await RenameStagePanelDialog.show(
    context,
    initialName: l10n.stagePanelDefaultName,
    titleText: l10n.stageCreatePanelDialogTitle,
  );
  if (name == null) return;
  ref.read(stageWorkspaceProvider.notifier).addPanel(name);
}

Future<void> _renamePanel(
  BuildContext context,
  WidgetRef ref,
  String panelId,
  String currentName,
) async {
  final l10n = L10N.of(context);
  final name = await RenameStagePanelDialog.show(
    context,
    initialName: currentName,
    titleText: l10n.stageRenamePanelDialogTitle,
  );
  if (name == null) return;
  ref.read(stageWorkspaceProvider.notifier).renamePanel(panelId, name);
}

Widget _dockAction({
  required IconData icon,
  required String tooltip,
  required VoidCallback onPressed,
}) => IconButton(
  icon: Icon(icon, size: kCruxDockIconSize),
  tooltip: tooltip,
  onPressed: onPressed,
  visualDensity: VisualDensity.compact,
  padding: EdgeInsets.zero,
  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
);
