// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_view_data.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Edge of one grid cell, and the minimum height of a row label.
///
/// Every cell moves the cursor when tapped, so every cell is a touch target
/// and the app's 44 dp mobile standard (ARCHITECTURE §3.1.8) applies. A
/// denser grid would be prettier and would fail that rule; the grid scrolls
/// instead.
const double kPipelineCellSize = 44;

/// Width of the pinned instruction-label column.
const double kPipelineLabelWidth = 168;

/// A centred, wrapped message — every empty and unusable state.
class PipelineNotice extends StatelessWidget {
  const PipelineNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
}

/// Fill colour for stage [stageIndex].
///
/// Derived from the active scheme rather than a fixed palette so the diagram
/// belongs to whichever theme the user is running, and by hue rotation rather
/// than a hand-picked list so it stays coherent for any stage count from 2 to
/// 8. Lightness is pinned per brightness so the label always has contrast.
Color pipelineStageColor(ThemeData theme, int stageIndex, int stageCount) {
  final base = HSLColor.fromColor(theme.colorScheme.primary);
  final span = math.max(1, stageCount);
  final hue = (base.hue + 360.0 * stageIndex / span) % 360;
  final dark = theme.brightness == Brightness.dark;
  return base
      .withHue(hue)
      .withSaturation(base.saturation.clamp(0.35, 0.75))
      .withLightness(dark ? 0.34 : 0.76)
      .toColor();
}

/// Text colour that reads against [pipelineStageColor].
Color pipelineStageTextColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? Colors.white : Colors.black87;

/// The instructions × cycles grid.
///
/// Vertical scrolling wraps the pinned label column *and* the grid so the two
/// stay aligned; horizontal scrolling moves only the cycle columns and their
/// header, so the row labels stay readable however far right the user scrolls.
class PipelineGrid extends StatefulWidget {
  const PipelineGrid({
    required this.data,
    required this.onSeekCycle,
    super.key,
  });

  final PipelineViewData data;

  /// Moves the primary cursor to the tick of the given cycle index.
  final void Function(int cycleIndex) onSeekCycle;

  @override
  State<PipelineGrid> createState() => _PipelineGridState();
}

class _PipelineGridState extends State<PipelineGrid> {
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final cycles = <int>[
      for (var c = data.windowStart; c < data.windowEnd; c++) c,
    ];

    // `ScrollBehavior` only ever adds a scrollbar to a *vertical* scrollable
    // (see `MaterialScrollBehavior.buildScrollbar`), so the vertical scroll
    // view below is already served on desktop and the horizontal one is not:
    // it scrolled with no visual affordance at all, and a grid wider than its
    // panel simply read as clipped and stuck.
    //
    // The scrollbar is hoisted *outside* the vertical scroll view rather than
    // wrapped around the horizontal one it drives. Wrapped inside, its box
    // would be the full height of every row, so the thumb would sit at the
    // bottom of the content — off-screen for any grid taller than the panel,
    // which is exactly the case that needs it. Out here the box is the
    // viewport, so the thumb is pinned to the bottom edge the user can see.
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabelColumn(data: data),
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CycleHeader(cycles: cycles, anchor: data.anchorCycle),
                    for (final row in data.rows)
                      _CellRow(
                        data: data,
                        row: row,
                        cycles: cycles,
                        onSeekCycle: widget.onSeekCycle,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelColumn extends StatelessWidget {
  const _LabelColumn({required this.data});

  final PipelineViewData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    return SizedBox(
      width: kPipelineLabelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: kPipelineCellSize,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  l10n.pipelineColumnInstruction,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          for (final row in data.rows)
            SizedBox(
              height: kPipelineCellSize,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rowLabel(row, l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: row.hasMismatch ? theme.colorScheme.error : null,
                      ),
                    ),
                    if (row.pc != null && row.disassembly != null)
                      Text(
                        _hex(row.pc!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CycleHeader extends StatelessWidget {
  const _CycleHeader({required this.cycles, required this.anchor});

  final List<int> cycles;
  final int anchor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final c in cycles)
          SizedBox(
            width: kPipelineCellSize,
            height: kPipelineCellSize,
            child: Center(
              child: Text(
                '$c',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: c == anchor
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: c == anchor ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CellRow extends StatelessWidget {
  const _CellRow({
    required this.data,
    required this.row,
    required this.cycles,
    required this.onSeekCycle,
  });

  final PipelineViewData data;
  final PipelineRow row;
  final List<int> cycles;
  final void Function(int cycleIndex) onSeekCycle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    return Row(
      children: [
        for (final c in cycles)
          SizedBox(
            width: kPipelineCellSize,
            height: kPipelineCellSize,
            child: Builder(
              builder: (context) {
                final cell = row.cells[c];
                if (cell == null) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: const SizedBox.expand(),
                  );
                }
                final name = cell.stageIndex < data.stageNames.length
                    ? data.stageNames[cell.stageIndex]
                    : '${cell.stageIndex + 1}';
                return Tooltip(
                  message: cell.mismatch
                      ? l10n.pipelineCellMismatchTooltip(name, c)
                      : l10n.pipelineCellTooltip(name, c),
                  child: InkWell(
                    onTap: () => onSeekCycle(c),
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: pipelineStageColor(
                          theme,
                          cell.stageIndex,
                          data.stageCount,
                        ),
                        borderRadius: BorderRadius.circular(3),
                        border: cell.mismatch
                            ? Border.all(
                                color: theme.colorScheme.error,
                                width: 2,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _abbreviate(name),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: pipelineStageTextColor(theme),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The stage legend — which colour is which stage.
class PipelineLegend extends StatefulWidget {
  const PipelineLegend({required this.data, super.key});

  final PipelineViewData data;

  @override
  State<PipelineLegend> createState() => _PipelineLegendState();
}

class _PipelineLegendState extends State<PipelineLegend> {
  /// Only so the legend's scrollbar has something to bind to. Horizontal
  /// scrollables get no scrollbar from `ScrollBehavior`, so at eight stages in
  /// a narrow panel the legend used to run off the edge with no hint that the
  /// missing stages were one swipe away.
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var s = 0; s < data.stageCount; s++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: pipelineStageColor(theme, s, data.stageCount),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s < data.stageNames.length
                          ? data.stageNames[s]
                          : '${s + 1}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _rowLabel(PipelineRow row, L10N l10n) {
  final disasm = row.disassembly;
  if (disasm != null && disasm.isNotEmpty) return disasm;
  final pc = row.pc;
  if (pc != null) return _hex(pc);
  return l10n.pipelineRowUnlabelled(row.instructionId);
}

String _hex(int value) {
  final digits = value.toRadixString(16).padLeft(8, '0');
  return '0x${digits.substring(0, 4)}_${digits.substring(4)}';
}

/// Keeps a long stage name inside a 44 dp cell without an ellipsis, which at
/// this size costs more glyphs than it saves.
String _abbreviate(String name) =>
    name.length <= 4 ? name : name.substring(0, 4);
