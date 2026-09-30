// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_tier_label.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_streaming_provider.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// WaveCrux's binding of the shared [CruxToolbar] to its own action catalog.
///
/// Everything structural — geometry, the `[common] │ [specific]` split, the
/// overflow slot and its edge fade, live-binding tooltips, per-action keys and
/// the semantics region — lives in `crux_toolbar`.
///
/// ## What the migration changed
///
/// - **One strip, one overflow strategy.** The separate phone and full
///   layouts are gone: the item list is the same everywhere, the metrics
///   switch to [CruxToolbarMetrics.touch] on touch device classes, and the
///   shared overflow appears when the strip cannot fit. The phone layout used
///   to hard-code its own four-button subset.
/// - **Enablement comes from the descriptor table only.** Most buttons used to
///   hard-code `isLoaded ? cb : null`, a hand-copy of `requires:
///   [fileLoaded]` that was correct but free to drift.
/// - **Every button dispatches a real [ShortcutAction].** The "Developer
///   Tools" button called `AppDiagnosticsDialog.open` through its own
///   callback while [ShortcutAction.openAppDiagnostics] already existed and
///   did exactly that — so the same dialog had two entry points, one of them
///   invisible to the palette, the menu, and the keymap editor.
/// - **Accelerators are no longer baked into tooltips.** Five ARB keys spelled
///   the chord into the label ("Zoom In (W)") across five locales; WaveCrux
///   shortcuts are rebindable, so those strings were wrong by construction.
///   [cruxToolbarTooltip] resolves the user's live binding instead.
/// - **Save Session As left the strip.** A Save-As button one pixel from Save
///   is the most mis-clickable pair on a toolbar; it keeps its menu item and
///   its chord.
/// - **Stop Streaming is a real action.** It used to be a bare callback with no
///   [ShortcutAction] — mouse-reachable only, invisible to the menu bar, the
///   command palette and the keymap editor. [ActionContext.streamingActive] now
///   gates it (structurally, so it costs nothing when nothing is streaming) and
///   it dispatches through the one handler like every other button.
/// - **The LIVE badge reads the active tab.** Streaming state is per-tab, but
///   the toolbar sits at the root scope beside `PaneHost`, so its
///   `ref.watch(streamingSourceProvider)` resolved the root container — an
///   instance nothing writes to. It watches
///   [activeTabStreamingProvider] instead.
class ViewerToolbar extends ConsumerWidget {
  /// Creates the viewer toolbar.
  const ViewerToolbar({
    required this.onShortcutAction,
    required this.isTransactionTableVisible,
    required this.isStagePanelVisible,
    super.key,
  });

  /// Dispatches a selected action through the screen's shortcut handler — the
  /// same path the keyboard, menu bar and palette use.
  final void Function(ShortcutAction) onShortcutAction;

  /// Whether the bottom transaction panel is open, for the toggle's glyph.
  final bool isTransactionTableVisible;

  /// Whether the Stage panel is open, for the toggle's glyph.
  final bool isStagePanelVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final ctx = ref.watch(actionContextProvider);
    final bindings = ref.watch(shortcutBindingsProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    // The active tab's streaming state, mirrored to the root scope — the
    // toolbar is a sibling of PaneHost and cannot reach the tab's container.
    final streamingState = ref.watch(activeTabStreamingProvider);
    final elapsed = streamingState is StreamingViewerActive
        ? streamingState.elapsed
        : Duration.zero;

    final metrics =
        deviceClass.isPhoneClass || deviceClass == DeviceClass.tablet
        ? CruxToolbarMetrics.touch
        : CruxToolbarMetrics.desktop;

    String labelOf(ShortcutAction action) =>
        action.label(l10n) +
        tierLabelSuffix(descriptorFor(action).requiredTier, l10n);

    CruxToolbarButtonItem<ShortcutAction> button(
      ShortcutAction action,
      IconData icon, {
      IconData? selectedIcon,
      bool isSelected = false,
      int badgeCount = 0,
      String? tooltip,
    }) => CruxToolbarButtonItem(
      action: action,
      icon: icon,
      selectedIcon: selectedIcon,
      isSelected: isSelected,
      badgeCount: badgeCount,
      tooltip: tooltip ?? labelOf(action),
    );

    return CruxToolbar<ShortcutAction>(
      common: [
        button(ShortcutAction.openFile, Icons.folder_open_outlined),
        button(ShortcutAction.saveSession, Icons.save_outlined),
        button(ShortcutAction.closeFile, Icons.close),
        const CruxToolbarSeparatorItem(),
        button(ShortcutAction.openSearch, Icons.search),
        // The peer badge is the suite's one place for "how many peers am I
        // connected to" — NetCrux, LintCrux and SimCrux all carry it here, and
        // WaveCrux was the only product where the count was invisible until
        // you opened the panel. Deliberately not duplicated into the status
        // bar: one fact, one home.
        button(
          ShortcutAction.openCrossProbePanel,
          Icons.sensors_outlined,
          selectedIcon: Icons.sensors,
          isSelected: ctx.crossProbeVisible,
          badgeCount: ref.watch(cxpPeersProvider).length,
          tooltip: l10n.toolbarToggleCrossProbe,
        ),
        button(ShortcutAction.openSettings, Icons.settings_outlined),
      ],
      specific: [
        button(ShortcutAction.exportWaveform, Icons.file_upload_outlined),
        const CruxToolbarSeparatorItem(),
        button(ShortcutAction.zoomIn, Icons.zoom_in),
        button(ShortcutAction.zoomOut, Icons.zoom_out),
        button(ShortcutAction.fitAll, Icons.fit_screen_outlined),
        // `crop_free` rather than `crop_square`: the filled square reads as a
        // stop glyph next to the zoom cluster.
        button(ShortcutAction.zoomToSelection, Icons.crop_free),
        const CruxToolbarSeparatorItem(),
        button(ShortcutAction.prevTransition, Icons.skip_previous),
        button(ShortcutAction.nextTransition, Icons.skip_next),
        const CruxToolbarSeparatorItem(),
        button(ShortcutAction.addDecoder, Icons.developer_board),
        button(
          ShortcutAction.toggleTransactionTable,
          Icons.table_chart_outlined,
          selectedIcon: Icons.table_chart,
          isSelected: isTransactionTableVisible,
        ),
        button(
          ShortcutAction.toggleStagePanel,
          Icons.dashboard_customize_outlined,
          selectedIcon: Icons.dashboard_customize,
          isSelected: isStagePanelVisible,
        ),
        if (kDebugMode) ...[
          const CruxToolbarSeparatorItem(),
          button(ShortcutAction.openAppDiagnostics, Icons.bug_report_outlined),
        ],
        // Streaming chrome. The badge stays a widget item — it animates and
        // renders a live timer, neither of which an action models. Stop is now
        // an ordinary action button; the `if` mirrors its descriptor's
        // `isVisible: streamingActive`, which is what hides it from the menu
        // and the palette at the same time.
        if (ctx.streamingActive) ...[
          const CruxToolbarSeparatorItem(),
          CruxToolbarWidgetItem(
            id: 'live-badge',
            child: _LiveBadge(
              elapsed: elapsed,
              tooltip: l10n.streamingBadgeTooltip(_formatElapsed(elapsed)),
            ),
          ),
          button(ShortcutAction.stopStreaming, Icons.stop),
        ],
      ],
      isEnabled: (action) => isActionEnabled(action, ctx),
      onAction: onShortcutAction,
      shortcutOf: (action) => bindings[action],
      semanticsLabel: l10n.accessibilityToolbarRegion,
      metrics: metrics,
      overflow: CruxToolbarOverflowMenu<ShortcutAction>(
        groups: [
          for (final entry in groupedActionsFor(
            ActionSurface.overflow,
            ctx,
          ).entries)
            if (entry.key != ActionCategory.app)
              CruxOverflowGroup<ShortcutAction>(
                label: entry.key.label(l10n),
                actions: entry.value,
              ),
        ],
        labelOf: labelOf,
        isEnabled: (action) => isActionEnabled(action, ctx),
        shortcutOf: (action) => bindings[action],
        onAction: onShortcutAction,
        tooltip: l10n.toolbarOverflowActions,
        metrics: metrics,
        presentation: deviceClass.isPhoneClass
            ? CruxOverflowPresentation.sheet
            : CruxOverflowPresentation.menu,
      ),
    );
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2, '0')}:$m:$s';
    return '$m:$s';
  }
}

// ── LIVE badge ────────────────────────────────────────────────────────────────

/// Animated LIVE badge shown in the toolbar during a streaming session.
///
/// Displays a pulsing red dot, the "LIVE" label, and the formatted elapsed
/// time since streaming started.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.elapsed, required this.tooltip});

  final Duration elapsed;
  final String tooltip;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final elapsed = ViewerToolbar._formatElapsed(widget.elapsed);

    return Semantics(
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _pulse,
                child: const Icon(Icons.circle, size: 8, color: Colors.red),
              ),
              const SizedBox(width: 4),
              Text(
                l10n.streamingLiveLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                elapsed,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
