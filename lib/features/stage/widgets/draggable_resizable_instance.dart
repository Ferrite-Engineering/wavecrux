// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/bit_picker_dialog.dart';
import 'package:wavecrux/features/stage/widgets/fan_out_prompt_dialog.dart';
import 'package:wavecrux/features/stage/widgets/signal_binding_picker_dialog.dart';
import 'package:wavecrux/features/stage/widgets/stage_instance_tile.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/stage/stage_slot_family.dart';

/// Fallback minimum width when a widget is not registered (or its
/// definition omits a `minSize`). Real widgets declare their own
/// minimum via [StageWidget.minSize].
const double kStageInstanceMinWidth = 80;

/// Fallback minimum height when a widget is not registered. Real
/// widgets declare their own minimum via [StageWidget.minSize].
const double kStageInstanceMinHeight = 60;

/// Wraps a [StageInstanceTile] with drag-to-move (any tile body) and
/// 8-directional resize handles (4 corners + 4 edges).
///
/// Edits write back to [StageWorkspaceNotifier] via [updateLayout]. The
/// wrapper is meant to be hosted inside a [Positioned] that supplies the
/// rendered position from [StageInstance.x] / [StageInstance.y] and the
/// size from [StageInstance.width] / [StageInstance.height].
class DraggableResizableInstance extends ConsumerWidget {
  const DraggableResizableInstance({required this.instance, super.key});

  final StageInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reads the latest persisted instance from state. Pan callbacks
    // need this because multiple onPanUpdate events fire within a
    // single gesture before the consuming widget rebuilds — referring
    // to `instance.x` directly would apply each delta against the same
    // stale starting position.
    StageInstance latest() {
      final s = ref.read(stageWorkspaceProvider);
      for (final p in s.panels) {
        for (final i in p.instances) {
          if (i.id == instance.id) return i;
        }
      }
      return instance;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Whole tile is drag-to-move + tap-to-select. Both gestures
        // share one GestureDetector so the pan and tap recognizers
        // disambiguate without nested-detector slop loss. Translucent
        // hit-test lets deeper IconButtons (close, etc.) win taps in
        // their own areas via the gesture arena.
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // DragStartBehavior.down makes the first onPanUpdate
              // include the touch-slop movement that the recognizer
              // accumulated before accepting. Without this, sharing a
              // detector with onTap leaves the tile permanently lagging
              // the cursor by ~18 dp.
              dragStartBehavior: DragStartBehavior.down,
              onTap: () => _handleTap(context, ref),
              onSecondaryTapDown: (details) => _showContextMenu(
                context,
                ref,
                details.globalPosition,
              ),
              onLongPressStart: (details) => _showContextMenu(
                context,
                ref,
                details.globalPosition,
              ),
              // Bracket the drag in a workspace transaction so the
              // dozens of intermediate updateLayout events that fire
              // during a single user drag coalesce into one undo step.
              onPanStart: (_) =>
                  ref.read(stageWorkspaceProvider.notifier).beginTransaction(),
              onPanEnd: (_) =>
                  ref.read(stageWorkspaceProvider.notifier).endTransaction(),
              onPanCancel: () =>
                  ref.read(stageWorkspaceProvider.notifier).cancelTransaction(),
              onPanUpdate: (details) {
                final cur = latest();
                final newX = (cur.x + details.delta.dx).clamp(
                  0.0,
                  double.infinity,
                );
                final newY = (cur.y + details.delta.dy).clamp(
                  0.0,
                  double.infinity,
                );
                ref
                    .read(stageWorkspaceProvider.notifier)
                    .updateLayout(instance.id, x: newX, y: newY);
              },
              child: _TileDragTarget(
                instance: instance,
                child: StageInstanceTile(instance: instance),
              ),
            ),
          ),
        ),
        // Resize handles sit on top so they win hit-tests at the edges
        // and corners. Their GestureDetectors use HitTestBehavior.opaque
        // so corner/edge pans never reach the move detector beneath.
        ..._buildResizeHandles(context, ref, latest),
      ],
    );
  }

  // ── context menu (right-click / long-press) ──────────────────────────────

  /// Pops a popup menu at [position] with stack-order operations and
  /// remove. Both right-click (`onSecondaryTapDown`) and long-press
  /// (`onLongPressStart`) route here so touch users get the same
  /// affordance as desktop users.
  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final l10n = L10N.of(context);
    final notifier = ref.read(stageWorkspaceProvider.notifier);
    // Selecting on context-menu open mirrors tap-to-select
    // behavior so the bindings pane reflects what the user is acting
    // on.
    ref.read(stageSelectedInstanceProvider.notifier).select(instance.id);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'front',
          child: Text(l10n.stageInstanceMenuBringToFront),
        ),
        PopupMenuItem(
          value: 'forward',
          child: Text(l10n.stageInstanceMenuBringForward),
        ),
        PopupMenuItem(
          value: 'backward',
          child: Text(l10n.stageInstanceMenuSendBackward),
        ),
        PopupMenuItem(
          value: 'back',
          child: Text(l10n.stageInstanceMenuSendToBack),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'remove',
          child: Text(l10n.stageInstanceMenuRemove),
        ),
      ],
    );
    switch (result) {
      case 'front':
        notifier.bringInstanceToFront(instance.id);
      case 'forward':
        notifier.bringInstanceForward(instance.id);
      case 'backward':
        notifier.sendInstanceBackward(instance.id);
      case 'back':
        notifier.sendInstanceToBack(instance.id);
      case 'remove':
        notifier.removeInstance(instance.id);
    }
  }

  // ── tap-to-select ─────────────────────────────────────────────────────────

  /// Selects the instance and, when the registered widget exposes a
  /// single input pin, opens the binding picker so the user can wire
  /// the signal in one tap (LED, seven-segment, etc.). Multi-input
  /// widgets only select — the bindings pane handles per-pin picking.
  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    ref.read(stageSelectedInstanceProvider.notifier).select(instance.id);

    final widgetDef = StageRegistry.instance.get(instance.widgetId);
    if (widgetDef == null) return;
    final pins = [
      ...widgetDef.requiredSignals,
      ...widgetDef.optionalSignals,
    ];
    if (pins.length != 1) return;

    final pin = pins.first;
    final result = await SignalBindingPickerDialog.show(
      context,
      pinName: pin.name,
      pinDescription: pin.description,
      currentSignalRef: instance.signalBindings[pin.name]?.signalRef,
      tabContainer: ProviderScope.containerOf(context, listen: false),
    );
    if (result == null) return;
    ref
        .read(stageWorkspaceProvider.notifier)
        .setBinding(instance.id, pin.name, result.signalRef);
  }

  // ── resize handles ────────────────────────────────────────────────────────

  static const double _cornerHit = 14;
  static const double _cornerVisual = 6;
  static const double _edgeHit = 6;

  List<Widget> _buildResizeHandles(
    BuildContext context,
    WidgetRef ref,
    StageInstance Function() latest,
  ) {
    final theme = Theme.of(context);
    // Per-widget min size from the registry (falls back to the global
    // constants when the widget is unregistered or doesn't override).
    final widgetDef = StageRegistry.instance.get(instance.widgetId);
    final (minW, minH) =
        widgetDef?.minSize ?? (kStageInstanceMinWidth, kStageInstanceMinHeight);

    void apply(_ResizeDirection dir, Offset delta) {
      final cur = latest();
      var newX = cur.x;
      var newY = cur.y;
      var newW = cur.width;
      var newH = cur.height;

      if (dir.edges.contains(_ResizeEdge.left)) {
        newX = cur.x + delta.dx;
        newW = cur.width - delta.dx;
      }
      if (dir.edges.contains(_ResizeEdge.right)) {
        newW = cur.width + delta.dx;
      }
      if (dir.edges.contains(_ResizeEdge.top)) {
        newY = cur.y + delta.dy;
        newH = cur.height - delta.dy;
      }
      if (dir.edges.contains(_ResizeEdge.bottom)) {
        newH = cur.height + delta.dy;
      }

      // Clamp to minimum size, anchoring to the opposite edge if the
      // user pulled the top/left edge past the minimum.
      if (newW < minW) {
        if (dir.edges.contains(_ResizeEdge.left)) {
          newX = cur.x + (cur.width - minW);
        }
        newW = minW;
      }
      if (newH < minH) {
        if (dir.edges.contains(_ResizeEdge.top)) {
          newY = cur.y + (cur.height - minH);
        }
        newH = minH;
      }

      // Clamp position to the canvas origin. When the left/top edge
      // hits the wall, absorb the overshoot into the width/height so
      // the right/bottom edge stays put under the cursor.
      if (newX < 0) {
        if (dir.edges.contains(_ResizeEdge.left)) {
          newW = newW + newX;
        }
        newX = 0;
      }
      if (newY < 0) {
        if (dir.edges.contains(_ResizeEdge.top)) {
          newH = newH + newY;
        }
        newY = 0;
      }

      ref
          .read(stageWorkspaceProvider.notifier)
          .updateLayout(
            instance.id,
            x: newX,
            y: newY,
            width: newW,
            height: newH,
          );
    }

    Widget edge({
      required ValueKey<String> key,
      required _ResizeDirection dir,
      required MouseCursor cursor,
      double? top,
      double? left,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) => Positioned(
      key: key,
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) =>
              ref.read(stageWorkspaceProvider.notifier).beginTransaction(),
          onPanEnd: (_) =>
              ref.read(stageWorkspaceProvider.notifier).endTransaction(),
          onPanCancel: () =>
              ref.read(stageWorkspaceProvider.notifier).cancelTransaction(),
          onPanUpdate: (d) => apply(dir, d.delta),
        ),
      ),
    );

    Widget corner({
      required ValueKey<String> key,
      required _ResizeDirection dir,
      required MouseCursor cursor,
      double? top,
      double? left,
      double? right,
      double? bottom,
    }) => Positioned(
      key: key,
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: _cornerHit,
      height: _cornerHit,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanUpdate: (d) => apply(dir, d.delta),
          child: Center(
            child: Container(
              width: _cornerVisual,
              height: _cornerVisual,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );

    return [
      // Edge handles: thin strips along each side, between the corner
      // squares. Invisible — discoverable by cursor change on hover.
      edge(
        key: ValueKey('stageResizeTop:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.top}),
        cursor: SystemMouseCursors.resizeUpDown,
        top: 0,
        left: _cornerHit,
        right: _cornerHit,
        height: _edgeHit,
      ),
      edge(
        key: ValueKey('stageResizeBottom:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.bottom}),
        cursor: SystemMouseCursors.resizeUpDown,
        bottom: 0,
        left: _cornerHit,
        right: _cornerHit,
        height: _edgeHit,
      ),
      edge(
        key: ValueKey('stageResizeLeft:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.left}),
        cursor: SystemMouseCursors.resizeLeftRight,
        top: _cornerHit,
        bottom: _cornerHit,
        left: 0,
        width: _edgeHit,
      ),
      edge(
        key: ValueKey('stageResizeRight:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.right}),
        cursor: SystemMouseCursors.resizeLeftRight,
        top: _cornerHit,
        bottom: _cornerHit,
        right: 0,
        width: _edgeHit,
      ),
      // Corner handles: small filled squares at the absolute corners.
      corner(
        key: ValueKey('stageResizeTopLeft:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.top, _ResizeEdge.left}),
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        top: 0,
        left: 0,
      ),
      corner(
        key: ValueKey('stageResizeTopRight:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.top, _ResizeEdge.right}),
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        top: 0,
        right: 0,
      ),
      corner(
        key: ValueKey('stageResizeBottomLeft:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.bottom, _ResizeEdge.left}),
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        bottom: 0,
        left: 0,
      ),
      corner(
        key: ValueKey('stageResizeBottomRight:${instance.id}'),
        dir: const _ResizeDirection({_ResizeEdge.bottom, _ResizeEdge.right}),
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        bottom: 0,
        right: 0,
      ),
    ];
  }
}

enum _ResizeEdge { top, right, bottom, left }

@immutable
class _ResizeDirection {
  const _ResizeDirection(this.edges);
  final Set<_ResizeEdge> edges;
}

/// Wraps the [StageInstanceTile] in a `DragTarget<String>` that accepts
/// a signal-ref payload from a [VariableTreeLeaf] drag.
///
/// On drop:
/// - For widgets with a single input pin, the signal is bound directly.
/// - For widgets with multiple pins, a popup menu opens at the drop
///   location asking the user which pin to bind.
/// - In either case, the instance is selected so the bindings pane
///   reflects the new state.
///
/// While a drag is hovering over the tile, a primary-color overlay
/// makes the drop target visible. Per-slot board drops win
/// over this outer target via gesture arena depth.
class _TileDragTarget extends ConsumerWidget {
  const _TileDragTarget({required this.instance, required this.child});

  final StageInstance instance;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DragTarget<String>(
      onAcceptWithDetails: (details) => _handleDrop(context, ref, details),
      builder: (context, candidate, rejected) {
        if (candidate.isEmpty) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleDrop(
    BuildContext context,
    WidgetRef ref,
    DragTargetDetails<String> details,
  ) async {
    ref.read(stageSelectedInstanceProvider.notifier).select(instance.id);

    final widgetDef = StageRegistry.instance.get(instance.widgetId);
    if (widgetDef == null) return;
    final pins = [
      ...widgetDef.requiredSignals,
      ...widgetDef.optionalSignals,
    ];
    if (pins.isEmpty) return;

    String? targetPin;
    if (pins.length == 1) {
      targetPin = pins.first.name;
    } else {
      targetPin = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          details.offset.dx,
          details.offset.dy,
          details.offset.dx + 1,
          details.offset.dy + 1,
        ),
        items: [
          for (final pin in pins)
            PopupMenuItem(
              value: pin.name,
              child: Text(
                pin.description.isEmpty
                    ? pin.name
                    : '${pin.name} — ${pin.description}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
        ],
      );
    }
    if (targetPin == null) return;
    if (!context.mounted) return;

    final pinSpec = pins.firstWhere((p) => p.name == targetPin);
    await applyDropBinding(
      context,
      ref,
      instanceId: instance.id,
      pinName: targetPin,
      pinBitWidth: pinSpec.bitWidth,
      signalRef: details.data,
    );
  }
}

/// Sets a stage signal binding for a drop, opening [BitPickerDialog]
/// when a multi-bit vector is being dropped onto a 1-bit slot. Shared
/// helper used by both the tile-level drag target and the per-slot
/// board drop targets so the bit-pick UX is identical everywhere.
Future<void> applyDropBinding(
  BuildContext context,
  WidgetRef ref, {
  required String instanceId,
  required String pinName,
  required int? pinBitWidth,
  required String signalRef,
}) async {
  final variables = ref.read(signalVariablesMapProvider);
  final variable = variables[signalRef];
  final signalWidth = variable?.bitWidth ?? 1;
  final slotWidth = pinBitWidth ?? 0;

  // Trigger the bit picker only when the slot is explicitly 1-bit and
  // the bound signal is wider than 1 bit. A slot with bitWidth == null
  // (= "accepts any width") should NOT prompt — bus readouts and the
  // like deliberately accept the full vector.
  final shouldAskForBit = slotWidth == 1 && signalWidth > 1;
  if (!shouldAskForBit) {
    ref
        .read(stageWorkspaceProvider.notifier)
        .setBinding(instanceId, pinName, signalRef);
    return;
  }

  final result = await BitPickerDialog.show(
    context,
    signalRef: signalRef,
    bitWidth: signalWidth,
  );
  if (result == null) return;
  ref
      .read(stageWorkspaceProvider.notifier)
      .setBinding(
        instanceId,
        pinName,
        signalRef,
        bitIndex: result.bindWhole ? null : result.bitIndex,
      );
}

/// Drop handler for a board slot that is potentially part of a slot
/// family (`led0..led15`, `sw0..sw15`).
///
/// When the dropped vector signal's width matches the family size and
/// the slot is genuinely 1-bit, the user is offered a fan-out: bind
/// every slot in the family to its matching bit of the vector. The
/// "just this one" path falls back to [applyDropBinding] so the
/// single-slot bit-picker UX is unchanged for users who decline the
/// fan-out.
Future<void> applyBoardSlotDrop(
  BuildContext context,
  WidgetRef ref, {
  required String instanceId,
  required String slotName,
  required int? pinBitWidth,
  required String signalRef,
  required List<StageWidgetSlot> parentSlots,
}) async {
  final variables = ref.read(signalVariablesMapProvider);
  final variable = variables[signalRef];
  final signalWidth = variable?.bitWidth ?? 1;
  final family = StageSlotFamilyResolver.familyOf(parentSlots, slotName);

  // Two fan-out modes, both gated by membership in a slot family
  // (`led0..led15`, `adc_ch0..adc_ch7`):
  //
  //   - Single-bit fan-out: every slot is 1-bit and the dropped
  //     signal width matches the family size exactly. Each slot
  //     binds one bit (bit i ← slot i). Original LED-bus pattern.
  //   - Multi-bit slice fan-out: every slot accepts a multi-bit
  //     value and the dropped signal width is an exact integer
  //     multiple of the family size, with slice width > 1. Each
  //     slot binds an N-bit slice of the bus. Used by the
  //     DE10-Nano `adc_ch[95:0]` 96-bit packed bus → 8 ADC channel
  //     slots, 12 bits each.
  final familySize = family?.size ?? 0;
  final canFanOutSingle =
      family != null && pinBitWidth == 1 && signalWidth == familySize;
  final canFanOutSlice =
      family != null &&
      pinBitWidth != 1 &&
      familySize > 1 &&
      signalWidth > familySize &&
      signalWidth % familySize == 0;
  final sliceWidth = canFanOutSlice ? signalWidth ~/ familySize : 1;

  if (!canFanOutSingle && !canFanOutSlice) {
    await applyDropBinding(
      context,
      ref,
      instanceId: instanceId,
      pinName: slotName,
      pinBitWidth: pinBitWidth,
      signalRef: signalRef,
    );
    return;
  }

  final choice = await FanOutPromptDialog.show(
    context,
    signalRef: signalRef,
    signalWidth: signalWidth,
    familyPrefix: family.prefix,
    familySize: family.size,
    familyMinIndex: family.minIndex,
    sliceWidth: canFanOutSlice ? sliceWidth : null,
  );
  if (!context.mounted) return;
  switch (choice) {
    case FanOutPromptChoice.cancel:
      return;
    case FanOutPromptChoice.bindOne:
      await applyDropBinding(
        context,
        ref,
        instanceId: instanceId,
        pinName: slotName,
        pinBitWidth: pinBitWidth,
        signalRef: signalRef,
      );
      return;
    case FanOutPromptChoice.bindAll:
      // Build a complete updated map atomically so widgets see the
      // fan-out as one state transition rather than N successive ones.
      final notifier = ref.read(stageWorkspaceProvider.notifier);
      final workspace = ref.read(stageWorkspaceProvider);
      Map<String, StageSignalBinding>? current;
      for (final p in workspace.panels) {
        for (final i in p.instances) {
          if (i.id == instanceId) {
            current = Map.of(i.signalBindings);
            break;
          }
        }
        if (current != null) break;
      }
      current ??= <String, StageSignalBinding>{};
      for (final m in family.members) {
        final slotOffset = m.index - family.minIndex;
        if (canFanOutSlice) {
          // Slice fan-out: slot i binds bits [(i+1)*sliceWidth-1 : i*sliceWidth].
          // E.g. ADC: adc_ch0 → bits[11:0], adc_ch1 → bits[23:12], ...
          current[m.slot.name] = StageSignalBinding(
            signalRef: signalRef,
            bitIndex: slotOffset * sliceWidth,
            bitWidth: sliceWidth,
          );
        } else {
          // Single-bit fan-out: slot i binds bit i.
          current[m.slot.name] = StageSignalBinding(
            signalRef: signalRef,
            bitIndex: slotOffset,
          );
        }
      }
      notifier.setBindings(instanceId, current);
  }
}
