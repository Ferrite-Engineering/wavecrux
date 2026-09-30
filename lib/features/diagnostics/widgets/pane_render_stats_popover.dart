// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/pane_render_stats.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';

/// Small popover that surfaces a single pane's [PaneRenderStats] snapshot
/// (see `docs/ARCHITECTURE.md` §8.8).
///
/// Each pane's [ViewerTabBar] renders an `i`-icon button whose `onPressed`
/// invokes [PaneRenderStatsPopover.showAnchoredTo]. The popover reads the
/// hosting pane's [paneRenderStatsProvider] from the matching
/// per-pane [ProviderContainer] supplied by [PaneContainerManager]; with
/// split-pane this means each pane has its own icon, its own popover, and
/// its own state — both popovers can be open simultaneously without
/// state mixing.
///
/// Contents: paint time breakdown (per phase), transitions per viewport,
/// line segments rendered, and the canvas size of the last painted frame.
class PaneRenderStatsPopover extends ConsumerWidget {
  const PaneRenderStatsPopover({
    required this.paneId,
    this.onClose,
    super.key,
  });

  /// Pane whose render stats are surfaced. The popover reads from this
  /// pane's [ProviderContainer]; the active pane is irrelevant to the
  /// content — opening the popover from pane "L" always shows pane L's
  /// data even if the user clicks while pane R is active.
  final PaneId paneId;

  /// Invoked when the popover's close (×) button is tapped. Only non-null
  /// when the popover is hosted inside [_PaneRenderStatsPopoverHost] (i.e.
  /// opened via [showAnchoredTo]); callers that embed [PaneRenderStatsPopover]
  /// directly (e.g. tests rendering the content body) may omit it and the
  /// close button is hidden.
  final VoidCallback? onClose;

  /// Opens the popover anchored below [anchorContext]'s render box.
  ///
  /// Issue 27: the original implementation used [showMenu], which pushes a
  /// modal route with a full-screen [ModalBarrier] beneath the menu. With
  /// split-pane and two popovers in play this had two user-visible
  /// failures:
  ///
  /// * Opening pane B's popover while pane A's was visible dismissed
  ///   A — the new menu's modal route popped A's route off the stack
  ///   instead of letting both coexist.
  /// * Clicking pane B's `i`-icon directly while A's popover was open
  ///   dismissed A but the click never reached B's `onPressed` — the
  ///   barrier consumed the tap as an outside-of-A dismissal.
  ///
  /// Replace [showMenu] with an [OverlayEntry] insertion: each popover
  /// lives in its own entry with no modal barrier, both can coexist on
  /// screen simultaneously, and clicks on other anchors fire normally.
  /// The popover now carries its own close (×) button (paired with an
  /// Escape-key shortcut on the host) since outside-tap dismissal is no
  /// longer possible without re-introducing a barrier.
  static Future<void> showAnchoredTo(
    BuildContext anchorContext, {
    required PaneId paneId,
  }) {
    // Re-entrancy guard keyed per pane: a repeated trigger on the same pane's
    // `i`-icon (or the anchor-less shortcut/menu path) must not stack popovers.
    return ModalGuard.run('paneRenderStats:${paneId.value}', () {
      final button = anchorContext.findRenderObject() as RenderBox?;
      final overlayState = Overlay.of(anchorContext, rootOverlay: true);
      final overlay = overlayState.context.findRenderObject() as RenderBox?;
      if (button == null || overlay == null) return Future<void>.value();

      final anchorTopLeft = button.localToGlobal(
        Offset.zero,
        ancestor: overlay,
      );
      final anchorSize = button.size;
      final overlaySize = overlay.size;
      final completer = Completer<void>();
      late OverlayEntry entry;
      void close() {
        if (entry.mounted) entry.remove();
        if (!completer.isCompleted) completer.complete();
      }

      entry = OverlayEntry(
        builder: (overlayContext) => _PaneRenderStatsPopoverHost(
          paneId: paneId,
          anchorTopLeft: anchorTopLeft,
          anchorSize: anchorSize,
          overlaySize: overlaySize,
          onClose: close,
        ),
      );
      overlayState.insert(entry);
      return completer.future;
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final pcm = ref.watch(paneContainerManagerProvider);
    final paneContainer = pcm.containerFor(paneId);

    // Subscribe to this pane's render-stats notifier so the popover updates
    // live while it's open. `ref.listen` from a ConsumerWidget would be
    // simpler but it isn't available outside the ProviderScope owning the
    // provider — instead we read from the pane container synchronously and
    // wrap in a Consumer that rebuilds on each notifier emission via
    // ProviderContainer.listen below.
    return _PaneRenderStatsContent(
      paneId: paneId,
      paneContainer: paneContainer,
      theme: theme,
      l10n: l10n,
      onClose: onClose,
    );
  }
}

/// Overlay-entry host for [PaneRenderStatsPopover].
///
/// Positions the popover beneath its anchor (the pane's tab-bar `i`-icon),
/// clamps it inside the overlay's bounds so it never paints off-screen at
/// the right edge under split-pane, paints a Material card behind the
/// content (the popover used to inherit this from the surrounding
/// PopupMenuItem), and registers an Escape-key shortcut + close (×)
/// button as the dismiss surface (since the overlay entry has no modal
/// barrier to absorb outside taps as a dismiss signal — see the comment
/// on [PaneRenderStatsPopover.showAnchoredTo] for the Issue 27 motivation).
class _PaneRenderStatsPopoverHost extends StatelessWidget {
  const _PaneRenderStatsPopoverHost({
    required this.paneId,
    required this.anchorTopLeft,
    required this.anchorSize,
    required this.overlaySize,
    required this.onClose,
  });

  final PaneId paneId;
  final Offset anchorTopLeft;
  final Size anchorSize;
  final Size overlaySize;
  final VoidCallback onClose;

  static const double _kPopoverWidth = 320;
  static const double _kEdgeInset = 8;

  @override
  Widget build(BuildContext context) {
    // Anchor the popover beneath the icon, right-aligned to the icon (since
    // the `i`-icon sits at the trailing end of the tab bar). Clamp inside
    // the overlay so split-pane on the right side never spills off-screen.
    final preferredLeft = anchorTopLeft.dx + anchorSize.width - _kPopoverWidth;
    final maxLeft = overlaySize.width - _kPopoverWidth - _kEdgeInset;
    final left = preferredLeft.clamp(
      _kEdgeInset,
      maxLeft.clamp(_kEdgeInset, double.infinity),
    );
    final top = anchorTopLeft.dy + anchorSize.height + 4;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    onClose();
                    return null;
                  },
                ),
              },
              child: FocusScope(
                autofocus: true,
                child: Material(
                  key: ValueKey('paneRenderStatsItem_${paneId.value}'),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: _kPopoverWidth,
                    child: PaneRenderStatsPopover(
                      paneId: paneId,
                      onClose: onClose,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Internal helper that rebuilds when the pane container emits a new
/// [PaneRenderStats] snapshot.
///
/// Implemented as a [StatefulWidget] because the data lives in a non-host
/// [ProviderContainer] — the standard `ref.watch` would not subscribe
/// across containers. The widget calls [ProviderContainer.listen] to wire
/// a state update.
class _PaneRenderStatsContent extends StatefulWidget {
  const _PaneRenderStatsContent({
    required this.paneId,
    required this.paneContainer,
    required this.theme,
    required this.l10n,
    this.onClose,
  });

  final PaneId paneId;
  final ProviderContainer paneContainer;
  final ThemeData theme;
  final L10N l10n;
  final VoidCallback? onClose;

  @override
  State<_PaneRenderStatsContent> createState() =>
      _PaneRenderStatsContentState();
}

class _PaneRenderStatsContentState extends State<_PaneRenderStatsContent> {
  late PaneRenderStats _stats;
  ProviderSubscription<PaneRenderStats>? _subscription;

  @override
  void initState() {
    super.initState();
    _stats = widget.paneContainer.read(paneRenderStatsProvider);
    _subscription = widget.paneContainer.listen<PaneRenderStats>(
      paneRenderStatsProvider,
      (_, next) {
        if (!mounted) return;
        setState(() => _stats = next);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = widget.theme;
    final latest = _stats.latest;

    final onClose = widget.onClose;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.paneRenderStatsTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              // (Issue 27 follow-up): the close-button construction below
              // intentionally uses the explicit padding/min-constraints so
              // the touch target meets §3.1.8.3 (44 dp on touch) without
              // pushing the popover header taller than its title row.
              if (onClose != null)
                // Issue 27: dedicated close button replaces the
                // outside-tap dismissal previously provided by `showMenu`'s
                // modal barrier. With multiple popovers open simultaneously
                // there is no longer a single "tap-outside" that should
                // dismiss any one of them, so the user dismisses each
                // explicitly via this button (or via the Escape shortcut
                // registered on the host).
                Tooltip(
                  message: l10n.paneRenderStatsCloseTooltip,
                  child: IconButton(
                    key: Key(
                      'paneRenderStatsCloseButton_${widget.paneId.value}',
                    ),
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: onClose,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (latest == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.paneRenderStatsNoData,
                key: const Key('paneRenderStatsNoData'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            _StatsTable(stats: latest, l10n: l10n, theme: theme),
        ],
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({
    required this.stats,
    required this.l10n,
    required this.theme,
  });

  final RenderPipelineStats stats;
  final L10N l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      (
        l10n.paneRenderStatsMetricPaintTime,
        '${_usToMs(stats.totalPaintTimeUs)} ms',
      ),
      (
        l10n.paneRenderStatsMetricLayout,
        '${_usToMs(stats.layoutTimeUs)} ms',
      ),
      (
        l10n.paneRenderStatsMetricScalar,
        '${_usToMs(stats.scalarPaintTimeUs)} ms',
      ),
      (
        l10n.paneRenderStatsMetricVector,
        '${_usToMs(stats.vectorPaintTimeUs)} ms',
      ),
      (
        l10n.paneRenderStatsMetricAnalog,
        '${_usToMs(stats.analogPaintTimeUs)} ms',
      ),
      (
        l10n.paneRenderStatsMetricCursor,
        '${_usToMs(stats.cursorPaintTimeUs)} ms',
      ),
      (
        l10n.paneRenderStatsMetricTransaction,
        '${_usToMs(stats.transactionPaintTimeUs)} ms',
      ),
      (
        l10n.paneRenderStatsMetricTransitions,
        '${stats.visibleTransitions}',
      ),
      (l10n.paneRenderStatsMetricSegments, '${stats.lineSegmentsDrawn}'),
      (
        l10n.paneRenderStatsMetricCanvasSize,
        '${stats.canvasWidth.round()}×${stats.canvasHeight.round()} px',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _usToMs(int us) => (us / 1000).toStringAsFixed(1);
}
