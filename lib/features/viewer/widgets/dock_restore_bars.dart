// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/widgets/bottom_dock.dart';
import 'package:wavecrux/features/viewer/widgets/side_docks.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Wraps the IDE layout with the JetBrains-style collapsed-region restore
/// bars: whenever a dock region is hidden, a slim strip along that window
/// edge shows the region's tab icons and a click reopens the region with
/// that tab active — replacing "drag the resize bar" as the only reopen
/// path.
///
/// The strips reuse the SAME entry assemblers as the docks themselves
/// ([buildBottomDockEntries], [buildRightDockEntries],
/// [buildLeftDockEntries]) so a bar can never disagree with its dock about
/// the region's tabs.
class WaveCruxDockRestoreBars extends ConsumerWidget {
  /// Creates the wrapper. [child] is the `CruxIdeLayout`. [onLoadStems]
  /// threads the screen's stems-file picker into the right-dock assembler.
  const WaveCruxDockRestoreBars({
    required this.child,
    required this.onLoadStems,
    super.key,
  });

  /// The IDE layout being wrapped.
  final Widget child;

  /// Opens the RTL stems file picker (the viewer screen owns the flow).
  final VoidCallback onLoadStems;

  List<CruxDockRestoreEntry> _restoreEntries(
    List<CruxDockEntry> entries,
    void Function(String id) reveal,
  ) => [
    for (final entry in entries)
      CruxDockRestoreEntry(
        id: entry.id,
        icon: entry.icon,
        label: entry.label,
        onRestore: () => reveal(entry.id),
      ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final layout = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);

    final showLeftBar = !layout.signalTreeVisible;
    final showRightBar = !layout.valueColumnVisible;
    final showBottomBar = !layout.transactionViewVisible;

    // One tree shape whatever is collapsed. Choosing the wrapper by state
    // (the bare child, a Column, a Row, a Row around a Column) changed the
    // widget type above the IDE layout every time a region collapsed or
    // reopened, and Flutter then discarded the whole layout and built it
    // again: every dock, the pane scope, the controller's show/hide
    // animation. The canvas survived only because its RepaintBoundary
    // carries a GlobalKey, which moves that one element between the two
    // trees inside a frame, and a GlobalKey move under a freshly built
    // semantics boundary is what `flushSemantics` asserts on while a screen
    // reader is attached (`identical(childRenderObject, parentRenderObject)`).
    // The bars are keyed so one appearing or vanishing is matched by identity
    // and touches nothing but itself.
    return Row(
      children: [
        if (showLeftBar)
          CruxDockRestoreBar(
            key: const ValueKey('dockRestoreBar.left'),
            edge: CruxDockCollapseDirection.left,
            entries: _restoreEntries(
              buildLeftDockEntries(context, ref),
              notifier.revealLeftDockTab,
            ),
            semanticsLabel: l10n.accessibilityLeftDockRegion,
          ),
        Expanded(
          key: const ValueKey('dockRestoreBars.center'),
          child: Column(
            children: [
              Expanded(child: child),
              if (showBottomBar)
                CruxDockRestoreBar(
                  key: const ValueKey('dockRestoreBar.bottom'),
                  edge: CruxDockCollapseDirection.down,
                  entries: _restoreEntries(
                    buildBottomDockEntries(context, ref),
                    notifier.revealBottomDockTab,
                  ),
                  semanticsLabel: l10n.accessibilityBottomDockRegion,
                ),
            ],
          ),
        ),
        if (showRightBar)
          CruxDockRestoreBar(
            key: const ValueKey('dockRestoreBar.right'),
            edge: CruxDockCollapseDirection.right,
            entries: _restoreEntries(
              buildRightDockEntries(context, ref, onLoadStems: onLoadStems),
              notifier.revealRightDockTab,
            ),
            semanticsLabel: l10n.accessibilityRightDockRegion,
          ),
      ],
    );
  }
}
