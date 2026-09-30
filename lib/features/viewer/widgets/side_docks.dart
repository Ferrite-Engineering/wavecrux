// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/comparison/widgets/diff_summary_panel.dart';
import 'package:wavecrux/features/rtl_source/widgets/rtl_source_panel.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/widgets/activity_heatmap_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/bottom_dock.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// WaveCrux's right dock: Values (pinned) · RTL Source (on-demand, desktop) ·
/// Cross-Probe (on-demand, desktop/tablet).
///
/// Replaces the right region's 3-deep priority chain (Cross-Probe > RTL
/// Source > Values), where toggling cross-probe silently *hid* the value
/// column instead of sitting one click away from it. On-demand tabs' `×`
/// deactivates the feature — the same flag their old close affordances
/// flipped.
///
/// Mounted per-tab inside `CruxIdeLayout`'s right region.
class WaveCruxRightDock extends ConsumerWidget {
  /// Creates the right dock. [onLoadStems] threads the screen's stems-file
  /// picker into the RTL panel.
  const WaveCruxRightDock({required this.onLoadStems, super.key});

  /// Opens the RTL stems file picker (the viewer screen owns the flow).
  final VoidCallback onLoadStems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final panelState = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);

    return CruxDock(
      entries: buildRightDockEntries(context, ref, onLoadStems: onLoadStems),
      activeId: panelState.effectiveRightDockTab,
      onSelect: notifier.setRightDockTab,
      onAutoReveal: notifier.revealRightDockTab,
      dockId: kDockRegionRight,
      onTabMovedIn: (id, _) => notifier.moveDockTab(id, kDockRegionRight),
      onCollapse: () => notifier.setValueColumnVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      collapseDirection: CruxDockCollapseDirection.right,
      semanticsLabel: l10n.accessibilityRightDockRegion,
    );
  }
}

/// Assembles the right dock's entry list — shared with the collapsed-region
/// restore bar so the two can never disagree about the region's tabs.
List<CruxDockEntry> buildRightDockEntries(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onLoadStems,
}) {
  final l10n = L10N.of(context);
  final panelState = ref.watch(panelLayoutProvider);
  final notifier = ref.read(panelLayoutProvider.notifier);
  final deviceClass = ref.watch(deviceClassProvider);
  final isDesktop = deviceClass == DeviceClass.desktop;
  final notPhone = !deviceClass.isPhoneClass;

  return <CruxDockEntry>[
    CruxDockEntry(
      id: kRightDockTabValues,
      icon: Icons.data_object,
      label: l10n.dockTabValues,
      builder: (_) => const ValueColumnPanel(),
    ),
    if (isDesktop && panelState.rtlSourceVisible)
      CruxDockEntry(
        id: kRightDockTabRtlSource,
        icon: Icons.code,
        label: l10n.dockTabRtlSource,
        // No panel-level onClose: the dock tab's × owns closing, and the
        // panel hides its own header × when none is supplied.
        builder: (_) => RtlSourcePanel(onLoadStems: onLoadStems),
        onClose: () => notifier.setRtlSourceVisible(visible: false),
      ),
    // Cross-Probe (native here) + any analyses dragged over from the
    // bottom dock — one shared assembler with the bottom dock, so an
    // entry can never render in two regions or vanish from both.
    if (notPhone) ...movableDockEntries(context, ref, region: kDockRegionRight),
  ];
}

/// WaveCrux's left dock: Signals (pinned) · Diff (on-demand while a waveform
/// diff is active).
///
/// The pinned entry keeps [ActivityHeatmapOverlay] as its builder — the
/// heatmap wraps the signal tree in place when a switching-activity analysis
/// is live, which is orthogonal to which *tab* is showing. With only the
/// pinned entry present, the dock's auto-hiding strip renders as a plain
/// "Signals" titled header — the agreed alternative to a VSCode activity
/// rail — and grows a tab strip the moment a diff activates.
class WaveCruxLeftDock extends ConsumerWidget {
  /// Creates the left dock.
  const WaveCruxLeftDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final panelState = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);
    final diffActive = ref.watch(diffProvider.select((s) => s.isActive));

    return CruxDock(
      entries: buildLeftDockEntries(context, ref),
      // In-memory selection; legacy behavior (diff active → diff shown)
      // comes from the dock's auto-reveal, not a persisted id.
      activeId:
          panelState.leftDockTab ??
          (diffActive ? kLeftDockTabDiff : kLeftDockTabSignals),
      onSelect: notifier.setLeftDockTab,
      onAutoReveal: notifier.revealLeftDockTab,
      onCollapse: () => notifier.setSignalTreeVisible(visible: false),
      collapseTooltip: l10n.dockCollapseTooltip,
      collapseDirection: CruxDockCollapseDirection.left,
      semanticsLabel: l10n.accessibilityLeftDockRegion,
    );
  }
}

/// Assembles the left dock's entry list — shared with the collapsed-region
/// restore bar.
List<CruxDockEntry> buildLeftDockEntries(BuildContext context, WidgetRef ref) {
  final l10n = L10N.of(context);
  final diffActive = ref.watch(diffProvider.select((s) => s.isActive));
  return <CruxDockEntry>[
    CruxDockEntry(
      id: kLeftDockTabSignals,
      icon: Icons.account_tree_outlined,
      label: l10n.dockTabSignals,
      builder: (_) => const ActivityHeatmapOverlay(),
    ),
    if (diffActive)
      CruxDockEntry(
        id: kLeftDockTabDiff,
        icon: Icons.compare_arrows,
        label: l10n.dockTabDiff,
        builder: (_) => const DiffSummaryPanel(),
        // Closing the tab clears the diff — the same thing the × in the
        // DiffToolbar does.
        onClose: () => ref.read(diffProvider.notifier).clearDiff(),
      ),
  ];
}
