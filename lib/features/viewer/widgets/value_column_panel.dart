// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart' show kCruxDockStripHeight;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/comparison/constants/diff_constants.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/decoders/constants/transaction_lane_constants.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/viewer/providers/active_toolbar_height_provider.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/plugins/timeline_overlay_layers_provider.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// One pre-flattened item shown in [ValueColumnPanel]'s lazy list.
///
/// We pre-flatten because [ListView.builder] needs an `itemCount` and
/// `itemBuilder(index)`, and a single [SignalEntry] may produce both a
/// value row *and* an XOR-diff spacer.
sealed class _ValueColumnItem {
  const _ValueColumnItem();
}

class _EntryItem extends _ValueColumnItem {
  const _EntryItem(this.entry, {this.childRows = 0});
  final SignalEntry entry;

  /// Reserved translator child (subfield) rows for this signal (from the
  /// shared [LaneGeometry]). `0` for non-signal or collapsed rows.
  final int childRows;
}

class _XorSpacerItem extends _ValueColumnItem {
  const _XorSpacerItem(this.signalRef);
  final String signalRef;
}

/// The right-pane value column panel.
///
/// Lists one row per signal/group/separator/comment entry, vertically
/// synchronized with [SignalListPanel] and [WaveformCanvas] via the shared
/// [WaveformScrollNotifier] offset. Each [SignalEntryKind.signal] row shows
/// the signal's formatted value at the primary cursor time.
///
/// Vertical scroll position is kept in sync with the centre pane through
/// [WaveformScrollNotifier]: [WaveformViewCenter] writes the offset; this
/// widget reads it and mirrors it via [_scrollController].
class ValueColumnPanel extends ConsumerStatefulWidget {
  const ValueColumnPanel({super.key});

  @override
  ConsumerState<ValueColumnPanel> createState() => _ValueColumnPanelState();
}

class _ValueColumnPanelState extends ConsumerState<ValueColumnPanel> {
  final ScrollController _scrollController = ScrollController();
  bool _syncing = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Syncs this panel's scroll position to [offset] from the shared notifier.
  void _syncTo(double offset) {
    if (_syncing || !_scrollController.hasClients) return;
    _syncing = true;
    try {
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, max));
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mirror scroll position whenever the centre pane scrolls.
    ref.listen<double>(waveformScrollProvider, (_, offset) {
      _syncTo(offset);
    });

    // The flattened row list + per-row heights come from the shared
    // [LaneGeometry] model (keyed by a [LaneMetrics] resolved identically by
    // SignalListPanel and WaveformCanvas), so this column can't drift out of
    // vertical alignment with the names list and the canvas.
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final laneMetrics = LaneMetrics(minLaneHeight: metrics.minLaneHeight);
    final geometry = ref.watch(laneGeometryProvider(laneMetrics));

    final diff = ref.watch(diffProvider);
    final toolbarHeight = ref.watch(activeToolbarHeightProvider);
    // Height of the canvas's vertical scroll viewport (center pane). The value
    // column lives in the full-height right pane, so without matching this it
    // would be taller than the canvas by the center↔bottom resizer (and bottom
    // panel) — diverging maxScrollExtents that make the synced scroll bounce
    // back at the bottom, clipping the last lane. `0` until the canvas lays out.
    final canvasViewportHeight = ref.watch(canvasViewportHeightProvider);
    // Timeline-overlay strips (cocotb, Pro SVA) render above the canvas lanes
    // in the centre pane. This pane reserves their *rendered* height (invisibly,
    // below) so its value rows start at the same y as the canvas lanes — without
    // it the values sit one overlay-height (e.g. 10 dp SVA) above their waves.
    final overlayLayers = ref.watch(timelineOverlayLayersProvider);
    // Bottom padding equal to the total transaction-lane height appended to
    // the canvas. Matches [SignalListPanel]'s padding so the three columns
    // share an identical scroll extent and stay vertically aligned when the
    // user scrolls all the way to the canvas's transaction-lane region.
    // Held decoders (session entries this build cannot load) get a blank lane
    // each after the active ones, matching their rows in the signal list.
    final activeDecoderCount =
        ref.watch(activeDecodersProvider).length +
        ref.watch(heldDecodersProvider).length;
    final bottomPadding = activeDecoderCount * transactionLaneHeight;

    // Pre-flatten into the per-list-item shape ListView.builder needs.
    // A signal with an active xorTrace produces an entry-row + spacer pair.
    final items = <_ValueColumnItem>[];
    for (final row in geometry.rows) {
      final entry = row.entry;
      items.add(_EntryItem(entry, childRows: row.childRows));
      if (diff.isActive &&
          entry.kind == SignalEntryKind.signal &&
          diff.xorTraces.containsKey(entry.signalRef ?? '')) {
        items.add(_XorSpacerItem(entry.signalRef ?? ''));
      }
    }

    // Blank header matches the TimeRulerWidget height plus any active toolbar
    // heights so value rows stay vertically aligned with the canvas lanes —
    // MINUS the right dock's strip, which already consumed that many pixels
    // above this panel (the center pane has no strip, so without the
    // deduction every value sat one strip-height below its wave).
    //
    // Bottom spacer matches the WaveformHorizontalScrollbar band height
    // reserved in the canvas column inside WaveformViewCenter. Without it,
    // the value column's Expanded would be 16/24 dp taller than the canvas
    // column's, their maxScrollExtents would diverge, and the bidirectional
    // vertical scroll sync would drift apart at the bottom of the list — the
    // user reads that as "the value moves from top of lane to bottom of lane
    // when the very last wave shows."
    final scrollbarBandHeight = metrics.isTouch ? 24.0 : 16.0;
    // The scroll body, reused by both the measured and the fallback layout.
    Widget buildBody() {
      return items.isEmpty
          ? _buildEmpty(context)
          : ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                // .builder so off-screen rows do NOT call
                // signalValueAtCursorProvider on every cursor frame.
                // With 1000+ signals loaded the previous eager Column
                // resolved every signal's value on every cursor frame
                // even though only ~20–40 rows were on screen.
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    switch (item) {
                      case _XorSpacerItem():
                        return SizedBox(
                          key: ValueKey('xor_$i'),
                          height: diffXorLaneHeight,
                        );
                      case _EntryItem():
                        final entry = item.entry;
                        if (entry.kind != SignalEntryKind.signal) {
                          return ValueColumnRow(
                            key: ValueKey(i),
                            entry: entry,
                            signalValue: null,
                          );
                        }
                        final childRows = item.childRows;
                        // Per-row Consumer: cursor-scrub hot path.
                        // Only visible signal rows subscribe to their
                        // own value, so the FFI/parser load drops
                        // from O(N total) to O(N visible).
                        final signalRef = entry.signalRef ?? '';
                        return Consumer(
                          key: ValueKey(i),
                          builder: (context, innerRef, _) {
                            final signalValue = signalRef.isNotEmpty
                                ? innerRef.watch(
                                    signalValueAtCursorProvider(
                                      signalRef,
                                      entry.format,
                                      entry.translatorConfig,
                                    ),
                                  )
                                : null;
                            return ValueColumnRow(
                              entry: entry,
                              signalValue: signalValue,
                              childRows: childRows,
                            );
                          },
                        );
                    }
                  },
                ),
              ),
            );
    }

    return Column(
      children: [
        SizedBox(
          height: (timeRulerHeight + toolbarHeight - kCruxDockStripHeight)
              .clamp(0, double.infinity)
              .toDouble(),
        ),
        // Reserve the canvas's rendered timeline-overlay height (invisibly, so
        // the strips themselves stay over the canvas) so value rows line up
        // with the canvas lanes that start below those strips. Reserve the
        // built widget, not `layer.height` — an inactive layer renders 0.
        for (final layer in overlayLayers)
          IgnorePointer(
            child: Opacity(opacity: 0, child: layer.build(context)),
          ),
        if (canvasViewportHeight > 0) ...[
          // Match the canvas viewport height exactly so the value column, the
          // signal-names list, and the canvas all share one maxScrollExtent —
          // the synced vertical scroll no longer clamps short and bounces back
          // at the bottom (see [canvasViewportHeightProvider]).
          //
          // The body is hosted in an Expanded + ClipRect/OverflowBox rather than
          // a bare SizedBox so the column can NEVER overflow. `overlayLayers`
          // (above) updates synchronously when an overlay is added (e.g.
          // entering diff mode adds a divergence-band layer), but
          // `canvasViewportHeight` is republished by the canvas one frame late
          // (post-frame callback in WaveformViewCenter). For that single frame
          // the reserved header + overlays + (stale, larger) canvasViewportHeight
          // exceed the pane by the new layer's height — an 8 dp RenderFlex
          // overflow that surfaces in the Pro decoder + diff/pattern-search
          // coexistence integration tests. The Expanded absorbs the remaining
          // pane height (so the Column has no fixed overflow), OverflowBox lets
          // the body keep its exact canvasViewportHeight without a constraint
          // error, and ClipRect hides the transient one-frame overshoot. In
          // steady state canvasViewportHeight is comfortably shorter than this
          // full-height right pane (the centre pane is shortened by the
          // scrollbar band + bottom panel), so nothing clips and the body sits
          // at its exact height, top-aligned, with blank filler below — the
          // historical layout, byte-for-byte.
          // Host the body in a loose Flexible rather than a bare SizedBox so the
          // column can NEVER overflow. `overlayLayers` (above) updates
          // synchronously when an overlay is added (e.g. entering diff mode adds
          // a divergence-band layer), but `canvasViewportHeight` is republished
          // by the canvas one frame late (post-frame callback in
          // WaveformViewCenter). For that single frame the reserved header +
          // overlays + (stale, larger) canvasViewportHeight exceed the pane — an
          // 8 dp RenderFlex overflow that surfaced in the Pro decoder +
          // diff/pattern-search coexistence integration tests. FlexFit.loose
          // bounds the body to the remaining pane height, so the stale frame
          // shrinks instead of overflowing and self-corrects next frame. In
          // steady state canvasViewportHeight is comfortably shorter than the
          // remaining pane, so the body sits at its exact height — same
          // maxScrollExtent as the canvas and names list (the synced vertical
          // scroll reaches the last lane). An OverflowBox here instead distorts
          // the ListView's measured maxScrollExtent and reintroduces the
          // last-lane clip, so it must not be used.
          Flexible(
            child: SizedBox(height: canvasViewportHeight, child: buildBody()),
          ),
        ] else ...[
          // Pre-measurement fallback (canvas has not laid out yet): fill the
          // pane and reserve the scrollbar band — the historical behavior.
          Expanded(child: buildBody()),
          SizedBox(height: scrollbarBandHeight),
        ],
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: const SizedBox.expand(),
    );
  }
}
