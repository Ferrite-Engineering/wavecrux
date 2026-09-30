// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/fsm_layout.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_bubble_painter.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Panel hosting the FSM bubble-diagram visualisation.
///
/// Used in two presentation modes:
/// - bottom-pane on tablet/desktop (alongside transaction table, X-trace,
///   activity report)
/// - modal sheet on phone (via [showFsmModal])
///
/// The diagram is wrapped in an [InteractiveViewer] for pinch-to-zoom and
/// pan, working uniformly across mouse, trackpad, and touch input.
///
/// The currently active state (cursor-based) is highlighted; tapping any
/// state node jumps the primary cursor to the first occurrence of that
/// state in the analysed time range.
class FsmPanel extends ConsumerWidget {
  const FsmPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final fsmState = ref.watch(fsmProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (!fsmState.isActive) {
      return _empty(
        context,
        l10n,
        fsmState.error,
        fsmState.noWaveform,
        colorScheme,
      );
    }

    final model = fsmState.model!;
    final layout = fsmState.layout!;
    final activeStateId = ref.watch(fsmCurrentStateIdProvider);
    final activeTransition = ref.watch(fsmRecentTransitionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: l10n.fsmPanelTitle(model.signalPath),
          stateCount: model.states.length,
          transitionCount: model.totalTransitionCount,
          onClear: () => ref.read(fsmProvider.notifier).clearFsm(),
          clearLabel: l10n.fsmPanelClose,
        ),
        Expanded(
          child: _FsmDiagram(
            model: model,
            layout: layout,
            activeStateId: activeStateId,
            activeTransition: activeTransition,
            onStateTap: (id) =>
                ref.read(fsmProvider.notifier).jumpToFirstOccurrence(id),
          ),
        ),
      ],
    );
  }

  Widget _empty(
    BuildContext context,
    L10N l10n,
    String? error,
    bool noWaveform,
    ColorScheme colorScheme,
  ) {
    // `noWaveform` is localized guidance; `error` is raw failure text. Both
    // render in the error color; the neutral empty prompt uses onSurfaceVariant.
    final highlighted = noWaveform || error != null;
    final message = noWaveform
        ? l10n.fsmPanelNoWaveform
        : (error ?? l10n.fsmPanelEmpty);
    return ColoredBox(
      color: colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: highlighted
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// Shows the FSM panel as a modal bottom sheet — used on phone where the
  /// bottom pane is unavailable.
  /// Pass [tabContainer] so the sheet's [FsmPanel] reads the active tab's
  /// `fsmProvider` (and friends). The sheet is built by the root navigator,
  /// outside the per-tab [UncontrolledProviderScope], so without this it shows
  /// the empty root FSM state.
  static Future<void> showFsmModal(
    BuildContext context, {
    ProviderContainer? tabContainer,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        const sheet = FractionallySizedBox(
          heightFactor: 0.85,
          child: FsmPanel(),
        );
        return tabContainer != null
            ? UncontrolledProviderScope(container: tabContainer, child: sheet)
            : sheet;
      },
    );
  }
}

// ── _PanelHeader ──────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.stateCount,
    required this.transitionCount,
    required this.onClear,
    required this.clearLabel,
  });

  final String title;
  final int stateCount;
  final int transitionCount;
  final VoidCallback onClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.account_tree,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Stats text is allowed to shrink and ellipsize at narrow widths
          // (iPad split-screen, narrow desktop windows). Without Flexible,
          // the Row's intrinsic width includes the full stats string and
          // the Clear button — they overflow at < ~400 dp.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                l10n.fsmPanelStats(stateCount, transitionCount),
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: Text(clearLabel),
          ),
        ],
      ),
    );
  }
}

// ── _FsmDiagram ───────────────────────────────────────────────────────────────

/// The interactive (pinch-zoom + pan) bubble-diagram surface.
class _FsmDiagram extends StatefulWidget {
  const _FsmDiagram({
    required this.model,
    required this.layout,
    required this.activeStateId,
    required this.activeTransition,
    required this.onStateTap,
  });

  final FsmModel model;
  final FsmLayout layout;
  final String? activeStateId;
  final ({String fromId, String toId})? activeTransition;
  final ValueChanged<String> onStateTap;

  @override
  State<_FsmDiagram> createState() => _FsmDiagramState();
}

class _FsmDiagramState extends State<_FsmDiagram> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapUp(TapUpDetails details, Size size, FsmBubblePainter painter) {
    // Map screen-local tap to scene coordinates via the inverse transform.
    final sceneOffset = _controller.toScene(details.localPosition);
    final stateId = painter.hitTestState(sceneOffset, size);
    if (stateId != null) {
      widget.onStateTap(stateId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final painter = FsmBubblePainter(
            model: widget.model,
            layout: widget.layout,
            colorScheme: colorScheme,
            activeStateId: widget.activeStateId,
            activeTransition: widget.activeTransition,
          );
          return InteractiveViewer(
            transformationController: _controller,
            minScale: 0.5,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(80),
            child: GestureDetector(
              onTapUp: (details) => _handleTapUp(details, size, painter),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CustomPaint(
                  painter: painter,
                  size: size,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
