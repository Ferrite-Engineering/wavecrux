// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_startup_render_gate_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/draggable_resizable_instance.dart';
import 'package:wavecrux/features/stage/widgets/stage_bindings_pane.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/editor_host_boundary.dart';

/// Logical-pixel step used by single-arrow-key nudges of the selected
/// stage instance.
const double kStageNudgeSmallStep = 1;

/// Logical-pixel step used by Shift+arrow nudges of the selected stage
/// instance — eight times the small step so it tracks the canvas grid
/// users tend to align to.
const double kStageNudgeLargeStep = 8;

/// The dockable Stage panel that hosts the user's signal-bound widgets.
///
/// Renders the **active** Stage panel's canvas (plus the bindings pane).
/// Panel *selection* lives in the bottom dock's strip — one dock tab per
/// [StagePanelConfig], with the playback transport and add-panel /
/// add-widget / rename as the active tab's strip actions — so this widget
/// carries no tab bar or control row of its own.
///
/// Hidden on phone-class devices ([DeviceClass.phone] and
/// [DeviceClass.phoneLandscape]): a phone-screen
/// Stage requires either overlaying the waveform (blocking
/// correlation) or a full-screen mode (losing timeline context),
/// neither of which is acceptable. Phone Stage is deferred to Future
/// Phases.
class StagePanel extends ConsumerWidget {
  const StagePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    if (deviceClass.isPhoneClass) {
      return _PhoneNotSupported(message: l10n.stagePanelPhoneUnsupported);
    }

    // Inside a VSCode editor panel the Stage tab is **present and empty with
    // an explanation** — never hidden: do not omit the panel, because an
    // absent feature teaches nothing.
    // The dock tab, its label, its close button and its strip actions are all
    // still there; only the canvas is replaced. An engineer who never sees
    // Stage does not know it exists, and one who opens it and reads two
    // sentences knows exactly what the desktop app is for.
    //
    // Same structural position as the phone gate above, and for a comparable
    // reason: Stage instances are laid out against a full application window,
    // and the custom-widget bundle path reads from disk (see
    // `stage/bundle/widget_bundle_reader.dart`, which is `dart:io`), which a
    // webview has none of.
    if (isEditorHosted(ref)) {
      return const EditorHostBoundary(capability: EditorHostCapability.stage);
    }

    final workspace = ref.watch(stageWorkspaceProvider);

    // An empty workspace never renders on its own tab anymore — turning
    // the Stage feature on seeds a default panel, and closing the last
    // panel's tab turns the feature off. The guard is defensive (e.g. a
    // restored legacy session with Stage on and zero panels).
    final Widget body;
    if (workspace.panels.isEmpty) {
      body = const SizedBox.shrink();
    } else {
      final active = workspace.activePanel ?? workspace.panels.first;
      final selectedId = ref.watch(stageSelectedInstanceProvider);
      final showBindingsPane =
          selectedId != null && active.instances.any((i) => i.id == selectedId);

      // Panel selection lives in the bottom dock's strip now — one dock tab
      // per Stage panel, with add-panel / add-widget / rename as the active
      // tab's strip actions. The internal `_StageTabBar` that duplicated a
      // second row of tabs under the dock's is gone; this widget renders the
      // active panel only.
      body = Row(
        children: [
          Expanded(child: _StageInstanceCanvas(panel: active)),
          if (showBindingsPane) ...[
            const VerticalDivider(width: 1),
            const SizedBox(
              width: StageBindingsPane.width,
              child: StageBindingsPane(),
            ),
          ],
        ],
      );
    }

    // The playback transport lives in the dock strip's per-active-tab action
    // cluster (see `stagePlaybackDockActions`) — no bottom control row here.
    return body;
  }
}

class _StageInstanceCanvas extends ConsumerStatefulWidget {
  const _StageInstanceCanvas({required this.panel});

  final StagePanelConfig panel;

  @override
  ConsumerState<_StageInstanceCanvas> createState() =>
      _StageInstanceCanvasState();
}

class _StageInstanceCanvasState extends ConsumerState<_StageInstanceCanvas> {
  /// Extra space drawn beyond the right/bottom-most instance, so the
  /// user can drag tiles outward without immediately hitting the canvas
  /// edge.
  static const double _canvasMargin = 200;

  /// Focus node for keyboard-driven nudge / delete. The canvas takes
  /// focus when its bounds receive a tap and on first build so users
  /// can keyboard-edit immediately after opening the Stage panel.
  final FocusNode _focusNode = FocusNode(debugLabel: 'StageInstanceCanvas');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Moves the currently selected instance by ([dx], [dy]) logical
  /// pixels via [StageWorkspaceNotifier.updateLayout]. The mutation is
  /// undoable through the workspace's command stack — the user gets one
  /// undo step per arrow press, which is the right granularity for
  /// fine-grained nudging.
  void _nudgeSelection({required double dx, required double dy}) {
    final selectedId = ref.read(stageSelectedInstanceProvider);
    if (selectedId == null) return;
    final workspace = ref.read(stageWorkspaceProvider);
    for (final p in workspace.panels) {
      for (final i in p.instances) {
        if (i.id != selectedId) continue;
        final newX = (i.x + dx).clamp(0.0, double.infinity);
        final newY = (i.y + dy).clamp(0.0, double.infinity);
        ref
            .read(stageWorkspaceProvider.notifier)
            .updateLayout(i.id, x: newX, y: newY);
        return;
      }
    }
  }

  /// Deletes the currently selected instance. No-op when nothing is
  /// selected. The workspace clears the now-stale selection itself
  /// (per the listener in `stageSelectedInstanceProvider.build`).
  void _deleteSelection() {
    final selectedId = ref.read(stageSelectedInstanceProvider);
    if (selectedId == null) return;
    ref.read(stageWorkspaceProvider.notifier).removeInstance(selectedId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    if (widget.panel.instances.isEmpty) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerLowest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.stagePanelNoInstances,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    // Cold-start restore serialization: while the startup render gate is
    // engaged, defer building the (GPU-heavy) board/instance content so it does
    // not join the active tab's signal-tree / canvas / value-column restoration
    // burst — the concurrent GPU device/surface init that trips the
    // Windows/Intel `ExitProcess(0x8F)` crash documented in
    // `docs/flutter-windows-gpu-crash-issue.md`. The gate releases once the
    // restore's content frame has rendered, after which these instances build
    // on their own frame. No-op outside cold-start restore (gate defaults
    // false), so normal Stage usage and tests render instances immediately.
    if (ref.watch(stageStartupRenderGateProvider)) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerLowest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Canvas size: at least the viewport, plus space beyond the
        // outermost instance so tiles can be dragged further out.
        var maxRight = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 800.0;
        var maxBottom = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 400.0;
        for (final i in widget.panel.instances) {
          final right = i.x + i.width;
          final bottom = i.y + i.height;
          if (right > maxRight) maxRight = right;
          if (bottom > maxBottom) maxBottom = bottom;
        }
        final contentW = maxRight + _canvasMargin;
        final contentH = maxBottom + _canvasMargin;

        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _nudgeSelection(
                    dx: -kStageNudgeSmallStep,
                    dy: 0,
                  ),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _nudgeSelection(
                    dx: kStageNudgeSmallStep,
                    dy: 0,
                  ),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _nudgeSelection(
                    dx: 0,
                    dy: -kStageNudgeSmallStep,
                  ),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _nudgeSelection(
                    dx: 0,
                    dy: kStageNudgeSmallStep,
                  ),
              const SingleActivator(
                LogicalKeyboardKey.arrowLeft,
                shift: true,
              ): () => _nudgeSelection(
                dx: -kStageNudgeLargeStep,
                dy: 0,
              ),
              const SingleActivator(
                LogicalKeyboardKey.arrowRight,
                shift: true,
              ): () => _nudgeSelection(
                dx: kStageNudgeLargeStep,
                dy: 0,
              ),
              const SingleActivator(
                LogicalKeyboardKey.arrowUp,
                shift: true,
              ): () => _nudgeSelection(
                dx: 0,
                dy: -kStageNudgeLargeStep,
              ),
              const SingleActivator(
                LogicalKeyboardKey.arrowDown,
                shift: true,
              ): () => _nudgeSelection(
                dx: 0,
                dy: kStageNudgeLargeStep,
              ),
              const SingleActivator(LogicalKeyboardKey.delete):
                  _deleteSelection,
              const SingleActivator(LogicalKeyboardKey.backspace):
                  _deleteSelection,
            },
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerLowest,
              child: InteractiveViewer(
                constrained: false,
                scaleEnabled: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: SizedBox(
                  width: contentW,
                  height: contentH,
                  child: GestureDetector(
                    // Tap on empty canvas deselects and gives the
                    // canvas keyboard focus so subsequent arrow keys
                    // nudge instead of falling through to the global
                    // pan shortcut. Tile / handle taps win in the
                    // gesture arena because their GestureDetectors are
                    // deeper in the tree.
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      _focusNode.requestFocus();
                      ref.read(stageSelectedInstanceProvider.notifier).clear();
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final i in widget.panel.instances)
                          Positioned(
                            key: ValueKey('stageInstanceWrap:${i.id}'),
                            left: i.x,
                            top: i.y,
                            width: i.width,
                            height: i.height,
                            child: DraggableResizableInstance(instance: i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhoneNotSupported extends StatelessWidget {
  const _PhoneNotSupported({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
