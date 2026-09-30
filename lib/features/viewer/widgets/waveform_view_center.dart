// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/comparison/widgets/diff_toolbar.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/pattern_search_toolbar.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_horizontal_scrollbar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/timeline_overlay_layer.dart';
import 'package:wavecrux/plugins/timeline_overlay_layers_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Container widget for the waveform viewer's center pane.
///
/// Renders [SignalListPanel] and [WaveformCanvas] side-by-side and keeps
/// their vertical scroll positions in sync via two linked [ScrollController]s.
///
/// The signal-list column width is device-class aware: 180 dp on desktop,
/// 260 dp on touch (phone, tablet, and any iOS/Android host). Touch metrics
/// — drag handle 44 dp + color swatch 44 dp + remove button 44 dp = 132 dp
/// of fixed chrome — leave only ~48 dp for the signal name inside a 180 dp
/// column, which truncates names like `p2_wdata` to 3 monospace characters.
/// The wider 260 dp on touch leaves ~120 dp for the name (≈9–11 chars), and
/// the [LayoutBuilder] clamp below caps the column at `(width − 100)` so it
/// never overflows on narrow split-screen / phone widths.
///
/// Handles loading and error states from [WaveformSourceNotifier] at the
/// pane level so that the time ruler is hidden and the full center area is
/// used for progress / error feedback.
class WaveformViewCenter extends ConsumerStatefulWidget {
  const WaveformViewCenter({required this.onCompareWith, super.key});

  /// Called when the user taps "Compare with…" in the [DiffToolbar].
  final VoidCallback onCompareWith;

  @override
  ConsumerState<WaveformViewCenter> createState() => _WaveformViewCenterState();
}

class _WaveformViewCenterState extends ConsumerState<WaveformViewCenter> {
  final ScrollController _signalListScroll = ScrollController();
  final ScrollController _canvasScroll = ScrollController();
  bool _syncing = false;
  // The persisted scroll offset that we still owe the scroll controllers.
  // [SessionNotifier._restore] writes it to [waveformScrollProvider]
  // before the scrollable child has attached its position. We watch the
  // provider in build and, on each frame, try to jumpTo this value once
  // the controllers have clients AND non-zero maxScrollExtent. Cleared
  // once applied so user-driven scrolls aren't fought.
  double? _pendingRestoreOffset;

  /// Signal-list column width on desktop. Touch device classes use
  /// [_signalListWidthTouch] instead — see class doc comment.
  static const double _signalListWidthDesktop = 180;

  /// Signal-list column width on touch (phone / tablet / iOS / Android).
  /// Sized to leave ≈120 dp for the signal name after the three 44 dp
  /// chrome elements (drag handle, color swatch, remove button).
  static const double _signalListWidthTouch = 260;

  @override
  void initState() {
    super.initState();
    _signalListScroll.addListener(_syncFromSignalList);
    _canvasScroll.addListener(_syncFromCanvas);
    // Seed _pendingRestoreOffset from the provider's current value (set by
    // [SessionNotifier._restore] before this widget mounted). If it is
    // non-zero, the post-frame callback in build() will apply it once the
    // ScrollControllers attach.
    final persisted = ref.read(waveformScrollProvider);
    if (persisted != 0) {
      _pendingRestoreOffset = persisted;
    }
  }

  @override
  void dispose() {
    _signalListScroll.removeListener(_syncFromSignalList);
    _canvasScroll.removeListener(_syncFromCanvas);
    _signalListScroll.dispose();
    _canvasScroll.dispose();
    super.dispose();
  }

  void _syncFromSignalList() {
    if (_syncing || !_canvasScroll.hasClients) return;
    _syncing = true;
    try {
      final offset = _signalListScroll.offset;
      _canvasScroll.jumpTo(offset);
      ref.read(waveformScrollProvider.notifier).setOffset(offset);
    } finally {
      _syncing = false;
    }
  }

  /// Applies [_pendingRestoreOffset] to both scroll controllers once they
  /// have clients with a non-zero maxScrollExtent (i.e. content has laid out
  /// enough to be scrollable). Clears the pending value on success.
  void _applyPendingRestoreOffset() {
    final pending = _pendingRestoreOffset;
    if (pending == null) return;
    if (!_signalListScroll.hasClients || !_canvasScroll.hasClients) return;
    final maxList = _signalListScroll.position.maxScrollExtent;
    final maxCanvas = _canvasScroll.position.maxScrollExtent;
    // Both scroll positions must be ready for non-zero scrolling, otherwise
    // jumpTo(pending) clamps to 0 and the restore silently fails. Wait for
    // a subsequent frame.
    if (maxList <= 0 && maxCanvas <= 0) return;
    final listTarget = math.min(math.max(pending, 0), maxList).toDouble();
    final canvasTarget = math.min(math.max(pending, 0), maxCanvas).toDouble();
    _syncing = true;
    try {
      _signalListScroll.jumpTo(listTarget);
      _canvasScroll.jumpTo(canvasTarget);
      ref
          .read(waveformScrollProvider.notifier)
          .setOffset(math.max(listTarget, canvasTarget));
    } finally {
      _syncing = false;
    }
    _pendingRestoreOffset = null;
  }

  void _syncFromCanvas() {
    if (_syncing || !_signalListScroll.hasClients) return;
    _syncing = true;
    try {
      final offset = _canvasScroll.offset;
      _signalListScroll.jumpTo(offset);
      ref.read(waveformScrollProvider.notifier).setOffset(offset);
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Publish the canvas's vertical scroll viewport height so the value column
    // (a full-height right pane) can size its own scroll region to the
    // bottom-shortened center pane and keep one shared maxScrollExtent. See
    // [canvasViewportHeightProvider]. Done in a post-frame callback because the
    // viewport dimension is only known after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_canvasScroll.hasClients) return;
      ref
          .read(canvasViewportHeightProvider.notifier)
          .setHeight(_canvasScroll.position.viewportDimension);
    });
    // Listen for externally-driven scroll offset updates (e.g. session
    // restore writes through [waveformScrollProvider] before the
    // ScrollControllers have attached). When the value diverges from our
    // controllers' current offsets, queue a post-frame jumpTo. The
    // _applyPendingRestoreOffset call itself in the post-frame waits for
    // maxScrollExtent > 0 so a value that arrives before the canvas has
    // laid out its lanes still lands when content is ready.
    ref.listen<double>(waveformScrollProvider, (prev, next) {
      if (_syncing) return;
      final currentList = _signalListScroll.hasClients
          ? _signalListScroll.offset
          : 0.0;
      final currentCanvas = _canvasScroll.hasClients
          ? _canvasScroll.offset
          : 0.0;
      // Skip our own writes (sync code already updated controllers).
      if ((next - currentList).abs() < 0.5 &&
          (next - currentCanvas).abs() < 0.5) {
        return;
      }
      _pendingRestoreOffset = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPendingRestoreOffset();
      });
    });
    // Drain any seeded pending offset (from initState) on every build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyPendingRestoreOffset();
    });

    final sourceAsync = ref.watch(waveformSourceProvider);

    // ── loading state ────────────────────────────────────────────────────────
    if (sourceAsync is AsyncLoading) {
      // Web opens (openFromBytes) never set currentFilePath — only
      // lastAttemptedPath carries the picked file's name there. Falling back
      // keeps the overlay saying "Loading <filename>..." instead of a bare
      // "Loading …" during the multi-second parse of a large trace.
      final notifier = ref.read(waveformSourceProvider.notifier);
      final filePath = notifier.currentFilePath ?? notifier.lastAttemptedPath;
      final filename = filePath != null ? _basename(filePath) : '';
      return _buildCenteredOverlay(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              filename.isNotEmpty
                  ? L10N.of(context).waveformCenterLoadingFile(filename)
                  : L10N.of(context).waveformCenterLoadingFile('…'),
              style: const TextStyle(
                color: WavecruxColors.timeRulerMajorTick,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () =>
                  ref.read(waveformSourceProvider.notifier).cancelLoad(),
              child: Text(L10N.of(context).waveformCenterCancelLoad),
            ),
          ],
        ),
      );
    }

    // ── error state ──────────────────────────────────────────────────────────
    if (sourceAsync is AsyncError) {
      final l10n = L10N.of(context);
      final isWasmRequired = sourceAsync.error is WebAssemblyRequiredError;
      final title = isWasmRequired
          ? l10n.waveformCenterWebAssemblyRequiredTitle
          : l10n.waveformCenterLoadError;
      final errorMessage = isWasmRequired
          ? l10n.waveformCenterWebAssemblyRequiredMessage
          : sourceAsync.error.toString();
      // No retry affordance: with one parser per platform any load failure
      // is deterministic, so re-running the same call produces the same
      // result. Users re-open the file via File → Open if they need to
      // try again after fixing the underlying cause (e.g. rebuilding the
      // app so libwellen_ffi.dylib is bundled, or picking a different file).
      return _buildCenteredOverlay(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWasmRequired
                  ? Icons.warning_amber_rounded
                  : Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                errorMessage,
                style: const TextStyle(
                  color: WavecruxColors.timeRulerMajorTick,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // ── normal / no-file states ──────────────────────────────────────────────
    final hasSignals = ref.watch(signalGroupsProvider).entries.isNotEmpty;
    final diffActive = ref.watch(
      diffProvider.select((s) => s.isActive),
    );

    final diffToolbar = DiffToolbar(onCompareWith: widget.onCompareWith);

    // Every timeline overlay layer — open-core (cocotb) and Pro-tier
    // (SVA, future coverage) — comes through the unified
    // `timelineOverlayLayersProvider`, sorted by ascending priority so
    // larger-priority layers paint closer to the canvas.
    final overlayLayers = ref.watch(timelineOverlayLayersProvider);

    if (!hasSignals) {
      return Column(
        children: [
          if (diffActive) diffToolbar,
          const PatternSearchToolbar(),
          const TimeRulerWidget(),
          for (final layer in overlayLayers) layer.build(context),
          Expanded(
            child: WaveformCanvas(externalScrollController: _canvasScroll),
          ),
          const WaveformHorizontalScrollbar(),
        ],
      );
    }

    // Left column: action header (same height as time ruler) + signal list.
    // Right column: DiffToolbar (when active) + TimeRulerWidget + WaveformCanvas.
    return Column(
      children: [
        if (diffActive) diffToolbar,
        const PatternSearchToolbar(),
        Expanded(
          // LayoutBuilder caps the signal-list column width to a fraction of
          // the available pane width so it can't overflow at narrow window /
          // split-screen sizes. Without the cap, the fixed-width SizedBox
          // forces the inner Row past the parent's width and produces
          // `RenderFlex overflowed by N pixels` errors. The 100-dp floor for
          // the waveform leaves at least a usable canvas at any width.
          //
          // The target width is device-class aware: 180 dp on desktop,
          // 260 dp on touch — see the class doc comment for the rationale.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final deviceClass = ref.watch(deviceClassProvider);
              final metrics = MobileMetrics.of(context, deviceClass);
              final targetWidth = metrics.isTouch
                  ? _signalListWidthTouch
                  : _signalListWidthDesktop;
              final maxList = (constraints.maxWidth - 100).clamp(
                0.0,
                targetWidth,
              );
              // Scrollbar band height — must match
              // [WaveformHorizontalScrollbar]'s internal bandHeight so the
              // signal list and canvas viewports stay vertically aligned at
              // the bottom edge. Without the matching spacer on the signal
              // list side, the canvas column's Expanded is 16/24 dp shorter
              // than the signal list's Expanded → maxScrollExtents diverge
              // → scrolling to the bottom bumps back a few pixels because
              // the bidirectional sync clamps one side and the other
              // jumpTo's back.
              final scrollbarBandHeight = metrics.isTouch ? 24.0 : 16.0;
              return Row(
                children: [
                  SizedBox(
                    width: maxList,
                    // The signal-list column has a fixed-height [_SignalListHeader]
                    // (36 dp = `timeRulerHeight`). When the user shrinks the app
                    // window vertically below the IdeLayout's intrinsic minimum,
                    // the panes package lets each pane overshoot its container
                    // rather than enforce minSize, so this column can be given
                    // a maxHeight smaller than 36 dp. Without this guard, the
                    // header overflows the column with a yellow/black RenderFlex
                    // bar. The threshold check drops the header when there is
                    // not enough room and lets the [SignalListPanel] take whatever
                    // sliver remains — visually degraded but no overflow.
                    child: LayoutBuilder(
                      builder: (context, c) {
                        // Issue 30: on phone and phone-landscape the
                        // "+ New Group" affordance crowds the already-tight
                        // chrome (a touch-target-sized icon button immediately
                        // below the toolbar) and reads as a stray popover
                        // floating in the tab-bar region. Group creation is
                        // still reachable via the signal-row context menu and
                        // the command palette; hide the inline header on
                        // touch-class phones so the signal list aligns with
                        // the canvas time ruler instead.
                        final isPhoneClass =
                            deviceClass == DeviceClass.phone ||
                            deviceClass == DeviceClass.phoneLandscape;
                        final showHeader =
                            !isPhoneClass && c.maxHeight >= timeRulerHeight;
                        // Mirror the canvas-side `showScrollbar` decision so the
                        // SignalListPanel's Expanded gets the same effective
                        // viewport height as the WaveformCanvas's Expanded.
                        // Identical-extent viewports keep
                        // maxScrollExtent equal, which is what the bidirectional
                        // scroll sync requires.
                        final listVisibleLayers = <TimelineOverlayLayer>[];
                        var cumulative = timeRulerHeight;
                        for (final layer in overlayLayers) {
                          if (c.maxHeight >= cumulative + layer.height) {
                            listVisibleLayers.add(layer);
                            cumulative += layer.height;
                          } else {
                            break;
                          }
                        }
                        final showScrollbarSpacer =
                            c.maxHeight >= cumulative + scrollbarBandHeight;
                        return Column(
                          children: [
                            if (showHeader)
                              const _SignalListHeader()
                            else if (isPhoneClass)
                              // Reserve the time-ruler-height slot with a blank
                              // spacer so the signal-list scroll viewport stays
                              // aligned with the canvas's TimeRulerWidget on the
                              // right (otherwise the rows would shift up by one
                              // ruler-height and the bidirectional scroll sync
                              // would clamp the canvas one ruler-height short).
                              const SizedBox(height: timeRulerHeight),
                            // Reserve the SAME vertical space the canvas column
                            // gives its timeline-overlay strips (cocotb, Pro SVA).
                            // The strips are timeline-aligned content that belongs
                            // over the canvas, so here they render invisibly — but
                            // the names column must still reserve their *rendered*
                            // height (an inactive layer renders 0 even though its
                            // `height` getter is non-zero, so reserve the built
                            // widget, not `layer.height`). Without this the names
                            // viewport is taller than the canvas's by the overlay
                            // height → a smaller maxScrollExtent → the synced
                            // scroll clamps everyone short of the canvas's last
                            // lane (the bottom-lane clip / bounce-back bug).
                            for (final layer in listVisibleLayers)
                              IgnorePointer(
                                child: Opacity(
                                  opacity: 0,
                                  child: layer.build(context),
                                ),
                              ),
                            Expanded(
                              child: SignalListPanel(
                                scrollController: _signalListScroll,
                              ),
                            ),
                            if (showScrollbarSpacer)
                              SizedBox(height: scrollbarBandHeight),
                          ],
                        );
                      },
                    ),
                  ),
                  Expanded(
                    // Same guard as the signal-list column above — the time
                    // ruler (36 dp), every contributed timeline-overlay layer
                    // (cocotb 8 dp, Pro SVA 10 dp, etc.), and the horizontal
                    // scrollbar (16 dp desktop / 24 dp touch) are fixed-height
                    // children that overflow when the IdeLayout is squeezed
                    // below its intrinsic minimum. Drop in reverse paint
                    // order — scrollbar first, then layers from highest
                    // priority (canvas-side) down to lowest (ruler-side),
                    // then ruler last — so the user always sees as much
                    // waveform canvas as the available height permits.
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final showRuler = c.maxHeight >= timeRulerHeight;
                        final visibleLayers = <TimelineOverlayLayer>[];
                        var cumulative = timeRulerHeight;
                        for (final layer in overlayLayers) {
                          if (c.maxHeight >= cumulative + layer.height) {
                            visibleLayers.add(layer);
                            cumulative += layer.height;
                          } else {
                            break;
                          }
                        }
                        final showScrollbar =
                            c.maxHeight >= cumulative + scrollbarBandHeight;
                        return Column(
                          children: [
                            if (showRuler) const TimeRulerWidget(),
                            for (final layer in visibleLayers)
                              layer.build(context),
                            Expanded(
                              child: WaveformCanvas(
                                externalScrollController: _canvasScroll,
                              ),
                            ),
                            if (showScrollbar)
                              const WaveformHorizontalScrollbar(),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCenteredOverlay({
    required BuildContext context,
    required Widget child,
  }) {
    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: child,
    );

    // Centre when the pane is tall enough, scroll when it is not.
    //
    // These overlays are fixed-height stacks (spinner + caption + Cancel, or
    // icon + explanation) sitting in a pane the user can drag arbitrarily
    // short by pulling the bottom dock up. A bare `Center` overflows there,
    // and `Column` clips from the bottom — so the first casualty is the
    // trailing action: the Cancel button that aborts a multi-second parse of a
    // large trace, exactly when the pane is likely to be sharing space with an
    // open dock. Release builds show no debug stripe; the button is just gone.
    //
    // Measured in integration run 30591309796: 119 px of content in a 92 px
    // box, `RenderFlex overflowed by 27 pixels`.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) return Center(child: content);
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: content),
            ),
          );
        },
      ),
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}

// ── Signal list action header ──────────────────────────────────────────────────

/// Thin header bar above [SignalListPanel], the same height as [TimeRulerWidget].
///
/// Contains a "New Group" icon button so users can create named signal groups
/// without leaving the viewer. The header uses the same height as the time
/// ruler so signal rows stay vertically aligned with canvas lanes.
class _SignalListHeader extends ConsumerWidget {
  const _SignalListHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final notifier = ref.read(signalGroupsProvider.notifier);
    final groupCount = ref
        .watch(signalGroupsProvider)
        .entries
        .where((e) => e.kind.name == 'group')
        .length;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      height: timeRulerHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
        ),
      ),
      // Wrap the header chrome in a horizontal scroll view per
      // ARCHITECTURE.md §3.1.8.12: when the signal-tree pane is resized
      // narrower than the "+ New Group" affordance's intrinsic width, the
      // chrome scrolls horizontally instead of asserting on overflow.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: l10n.signalGroupCreateTooltip,
              child: InkWell(
                onTap: () => notifier.addGroup(
                  'Group ${groupCount + 1}',
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.create_new_folder_outlined,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        l10n.signalGroupCreateNew,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
