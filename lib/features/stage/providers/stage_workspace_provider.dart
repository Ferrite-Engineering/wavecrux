// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';

part 'stage_workspace_provider.g.dart';

/// Maximum number of workspace snapshots retained on the undo stack.
/// Older entries are silently dropped so memory stays bounded; this is a
/// reasonable upper limit for a session of stage editing in practice.
const int kStageWorkspaceUndoHistoryLimit = 100;

/// The `stage.widget_added` token reported for a community `.wcrux-widget`
/// bundle, which has a family id we neither chose nor document.
const String _kCustomStageWidgetToken = 'custom';

/// The ingestion Worker's property-value class, mirrored client-side.
final RegExp _kStageWidgetToken = RegExp(r'^[a-z0-9_]{1,64}$');

/// Owns the in-memory [StageWorkspaceState] for the current session.
///
/// External callers add or remove panels and instances through the
/// methods on this notifier. State is persisted by [SessionService] when
/// a `.wavecrux` file is saved and restored by [SessionNotifier] when
/// one is loaded — see `restoreFromSession` and `snapshot` below.
///
/// **Undo/Redo.** Every mutation on this notifier is wrapped in a
/// command stack. The pre-mutation [StageWorkspaceState] is captured and
/// pushed onto [_undoStack] (with a redo stack cleared on each fresh
/// edit). [undo] / [redo] swap snapshots between the two stacks. Drag
/// gestures and resize that fire many [updateLayout] events in quick
/// succession should bracket their work between [beginTransaction] and
/// [endTransaction] so the entire interaction is one undo step.
/// Selection (single-instance, single-panel) is *not* tracked by this
/// stack — selection state lives in `stageSelectedInstanceProvider` and
/// is intentionally ephemeral.
@Riverpod(keepAlive: true)
class StageWorkspaceNotifier extends _$StageWorkspaceNotifier {
  /// Monotonic counter used to generate unique panel ids per workspace.
  /// Reset by [restoreFromSession] when loading an existing workspace.
  int _nextPanelId = 0;

  /// Monotonic counter used to generate unique instance ids per workspace.
  int _nextInstanceId = 0;

  /// Workspace snapshots captured before each undoable command, oldest
  /// first. Bounded at [kStageWorkspaceUndoHistoryLimit] entries.
  final List<StageWorkspaceState> _undoStack = [];

  /// Workspace snapshots discarded from the redo path because the user
  /// invoked a fresh command after [undo]. Cleared on every new edit.
  final List<StageWorkspaceState> _redoStack = [];

  /// Snapshot captured at [beginTransaction]. Non-null while a
  /// transaction is open; the captured state is what [endTransaction]
  /// pushes onto the undo stack regardless of how many intermediate
  /// mutations fired.
  StageWorkspaceState? _pendingTransactionSnapshot;

  @override
  StageWorkspaceState build() => const StageWorkspaceState();

  // ── undo / redo ──────────────────────────────────────────────────────────

  /// Whether [undo] would have an effect.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether [redo] would have an effect.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Reverts the most recent undoable command, pushing the current state
  /// onto the redo stack. No-op when [canUndo] is false.
  void undo() {
    if (_undoStack.isEmpty) return;
    final target = _undoStack.removeLast();
    final current = state;
    _redoStack.add(current);
    state = target;
  }

  /// Re-applies the most recently undone command. No-op when [canRedo]
  /// is false.
  void redo() {
    if (_redoStack.isEmpty) return;
    final target = _redoStack.removeLast();
    final current = state;
    _undoStack.add(current);
    state = target;
  }

  /// Captures the workspace snapshot before [mutate] runs, applies the
  /// mutation, then pushes the captured snapshot onto the undo stack
  /// (and clears the redo stack) **only if state actually changed**.
  ///
  /// While a [_pendingTransactionSnapshot] is open (between
  /// [beginTransaction] and [endTransaction]), the captured snapshot is
  /// the transaction's, not the per-mutation one — successive mutations
  /// inside the transaction therefore coalesce into a single undo step.
  void _recordChange(void Function() mutate) {
    if (_pendingTransactionSnapshot != null) {
      // Transaction is open — let the mutation run; endTransaction
      // will push the captured snapshot when the transaction closes.
      mutate();
      return;
    }
    final before = state;
    mutate();
    if (identical(before, state)) return;
    _undoStack.add(before);
    if (_undoStack.length > kStageWorkspaceUndoHistoryLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Opens a transaction that coalesces every subsequent mutation into
  /// a single undo step until [endTransaction] (or [cancelTransaction])
  /// closes it.
  ///
  /// Idempotent — calling [beginTransaction] while one is already open
  /// is a no-op (the original snapshot is preserved). Drag-to-move and
  /// resize gestures call this on `onPanStart` and pair it with
  /// [endTransaction] on `onPanEnd` so the dozens of intermediate
  /// [updateLayout] events fire as one user-visible edit.
  void beginTransaction() {
    _pendingTransactionSnapshot ??= state;
  }

  /// Closes the open transaction, pushing the captured snapshot onto
  /// the undo stack. No-op when no transaction is open or when the
  /// workspace did not actually change during the transaction.
  void endTransaction() {
    final before = _pendingTransactionSnapshot;
    if (before == null) return;
    _pendingTransactionSnapshot = null;
    if (identical(before, state)) return;
    _undoStack.add(before);
    if (_undoStack.length > kStageWorkspaceUndoHistoryLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Discards the open transaction without recording an undo step.
  /// Used when the user cancels a drag mid-flight (e.g. presses Esc).
  void cancelTransaction() {
    _pendingTransactionSnapshot = null;
  }

  // ── panel management ─────────────────────────────────────────────────────

  /// Adds a new empty panel with [name] and selects it.
  ///
  /// Returns the new panel's id.
  String addPanel(String name) {
    final id = 'stagePanel_${_nextPanelId++}';
    _recordChange(() {
      final panel = StagePanelConfig(id: id, name: name);
      state = state.copyWith(
        panels: [...state.panels, panel],
        activePanelId: id,
      );
    });
    return id;
  }

  /// Removes the panel with [panelId]. If it was the active panel, the
  /// next remaining panel (or null) becomes active.
  void removePanel(String panelId) {
    _recordChange(() {
      final remaining = state.panels
          .where((p) => p.id != panelId)
          .toList(growable: false);
      final newActive = state.activePanelId == panelId
          ? (remaining.isEmpty ? null : remaining.first.id)
          : state.activePanelId;
      state = StageWorkspaceState(panels: remaining, activePanelId: newActive);
    });
  }

  /// Renames panel [panelId] to [name]. No-op when the panel is unknown.
  void renamePanel(String panelId, String name) {
    _recordChange(() {
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            if (p.id == panelId) p.copyWith(name: name) else p,
        ],
      );
    });
  }

  /// Selects [panelId] as the active panel. No-op when unknown.
  ///
  /// Active-panel selection is intentionally **not** undoable: it is a
  /// view-state change rather than a workspace edit, and putting it on
  /// the undo stack would surface as confusing extra undo steps when
  /// the user is just navigating between panels.
  void selectPanel(String panelId) {
    if (state.panels.every((p) => p.id != panelId)) return;
    state = state.copyWith(activePanelId: panelId);
  }

  // ── instance management ──────────────────────────────────────────────────

  /// Adds a new instance of the registered widget [widgetId] to the
  /// active panel and returns its id.
  ///
  /// Initial size is taken from [StageWidget.defaultSize] (or a 160×100
  /// fallback when the widget is not registered). Returns null when no
  /// active panel exists or the widget id is unknown.
  String? addInstance(String widgetId) {
    final activeId = state.activePanelId;
    if (activeId == null) return null;
    final widget = StageRegistry.instance.get(widgetId);
    final (defaultW, defaultH) = widget?.defaultSize ?? const (160.0, 100.0);

    final id = 'stageInstance_${_nextInstanceId++}';
    _recordChange(() {
      final instance = StageInstance(
        id: id,
        widgetId: widgetId,
        width: defaultW,
        height: defaultH,
        x: _nextOffsetX(activeId, defaultW),
        y: _nextOffsetY(activeId, defaultH),
      );
      _updatePanel(
        activeId,
        (p) => p.copyWith(instances: [...p.instances, instance]),
      );
    });
    _recordWidgetAdded(widgetId);
    return id;
  }

  /// Records `stage.widget_added` for a family the user picked.
  ///
  /// Called only from [addInstance] — the picker's path, and the one shared by
  /// the open-core families and the Pro pack, which register into the same
  /// [StageRegistry] and so need no second call site. [addInstanceAt] is
  /// deliberately not instrumented: its only caller is the CXP-driven RISC-V
  /// commit auto-mount, where nobody chose a widget.
  ///
  /// The reported token is the id's last dot segment, lowercased — `led`,
  /// `dsp_eye`, `tachometer`, `nexysa7`. The segment split exists because the
  /// Pro pack namespaces its families (`wavecrux.pro.dsp_eye`) and the Worker's
  /// property-value class has no room for dots; the lowercasing exists because
  /// two open-core board ids are camelCase. A community bundle reports the
  /// fixed [_kCustomStageWidgetToken] instead — its id is its author's
  /// vocabulary and its cardinality is unbounded.
  void _recordWidgetAdded(String widgetId) {
    final token = StageRegistry.instance.isUserSupplied(widgetId)
        ? _kCustomStageWidgetToken
        : widgetId.split('.').last.toLowerCase();
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'stage.widget_added',
            properties: <String, Object?>{
              // Belt and braces on the derivation above: a family id that grew
              // a character outside the Worker's class would otherwise be
              // dropped at the edge, silently, and the count would look like
              // nobody used the widget.
              'widget': _kStageWidgetToken.hasMatch(token)
                  ? token
                  : _kCustomStageWidgetToken,
            },
          ),
        );
  }

  /// Adds a new instance of [widgetId] to the active panel at the
  /// requested ([x], [y]) origin (clamped to a non-negative origin)
  /// and returns its id.
  ///
  /// In contrast to [addInstance] (which cascade-offsets new instances
  /// so successive picker-driven adds don't stack), this puts the new
  /// instance exactly where the caller asks. Useful when an external
  /// gesture (drop position, restore from session, scripted setup) is
  /// the source of truth for placement.
  ///
  /// Optional [width] / [height] override the registered widget's
  /// [StageWidget.defaultSize]; pass `null` to keep the default.
  /// Returns `null` when no active panel exists.
  String? addInstanceAt(
    String widgetId, {
    required double x,
    required double y,
    double? width,
    double? height,
  }) {
    final activeId = state.activePanelId;
    if (activeId == null) return null;
    final widget = StageRegistry.instance.get(widgetId);
    final (defaultW, defaultH) = widget?.defaultSize ?? const (160.0, 100.0);

    final id = 'stageInstance_${_nextInstanceId++}';
    _recordChange(() {
      final instance = StageInstance(
        id: id,
        widgetId: widgetId,
        width: width ?? defaultW,
        height: height ?? defaultH,
        x: x < 0 ? 0 : x,
        y: y < 0 ? 0 : y,
      );
      _updatePanel(
        activeId,
        (p) => p.copyWith(instances: [...p.instances, instance]),
      );
    });
    return id;
  }

  /// Removes the instance [instanceId] from whichever panel contains it.
  void removeInstance(String instanceId) {
    _recordChange(() {
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            p.copyWith(
              instances: p.instances.where((i) => i.id != instanceId).toList(),
            ),
        ],
      );
    });
  }

  /// Updates the signal binding [pin] for [instanceId] to [signalRef]
  /// (optionally with a single-bit [bitIndex] for multibit-to-1-bit
  /// slot binding). When [signalRef] is null or empty the binding is
  /// removed.
  void setBinding(
    String instanceId,
    String pin,
    String? signalRef, {
    int? bitIndex,
  }) {
    _recordChange(() {
      final binding = (signalRef == null || signalRef.isEmpty)
          ? null
          : StageSignalBinding(signalRef: signalRef, bitIndex: bitIndex);
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            p.copyWith(
              instances: [
                for (final i in p.instances)
                  if (i.id == instanceId)
                    i.copyWith(
                      signalBindings:
                          {
                            ...i.signalBindings,
                            pin: ?binding,
                          }..removeWhere(
                            (k, v) => k == pin && binding == null,
                          ),
                    )
                  else
                    i,
              ],
            ),
        ],
      );
    });
  }

  /// Replaces the entire signal-binding map of [instanceId] with
  /// [bindings]. Used by the auto-bind preview dialog when applying
  /// many bindings atomically.
  void setBindings(
    String instanceId,
    Map<String, StageSignalBinding> bindings,
  ) {
    _recordChange(() {
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            p.copyWith(
              instances: [
                for (final i in p.instances)
                  if (i.id == instanceId)
                    i.copyWith(signalBindings: Map.unmodifiable(bindings))
                  else
                    i,
              ],
            ),
        ],
      );
    });
  }

  /// Replaces the position and/or size of [instanceId].
  ///
  /// Drag-to-move and resize gestures fire many [updateLayout] events
  /// in rapid succession. Bracket those between [beginTransaction] and
  /// [endTransaction] so they coalesce into a single undo step.
  void updateLayout(
    String instanceId, {
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    _recordChange(() {
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            p.copyWith(
              instances: [
                for (final i in p.instances)
                  if (i.id == instanceId)
                    i.copyWith(x: x, y: y, width: width, height: height)
                  else
                    i,
              ],
            ),
        ],
      );
    });
  }

  /// Replaces the entire configuration map for [instanceId]. Used by
  /// the bindings pane's Configuration editor when the user resets a
  /// widget's settings to defaults or pastes a saved config.
  void setConfiguration(
    String instanceId,
    Map<String, Object?> configuration,
  ) {
    _recordChange(() {
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            p.copyWith(
              instances: [
                for (final i in p.instances)
                  if (i.id == instanceId)
                    i.copyWith(
                      configuration: Map<String, Object?>.from(configuration),
                    )
                  else
                    i,
              ],
            ),
        ],
      );
    });
  }

  /// Updates a single configuration entry for [instanceId]. Pass null
  /// to remove the key (which has the same observable effect as setting
  /// it to the schema default).
  ///
  /// Called by every change handler in the generic configuration
  /// editor so each user edit produces one minimal state transition.
  void setConfigurationValue(
    String instanceId,
    String key, {
    required Object? value,
  }) {
    _recordChange(() {
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            p.copyWith(
              instances: [
                for (final i in p.instances)
                  if (i.id == instanceId)
                    i.copyWith(
                      configuration: {
                        ...i.configuration,
                        if (value != null) key: value else ...{},
                      }..removeWhere((k, _) => value == null && k == key),
                    )
                  else
                    i,
              ],
            ),
        ],
      );
    });
  }

  /// Sets the user-visible label for [instanceId]. Pass null to clear.
  void setLabel(String instanceId, String? label) {
    _recordChange(() {
      state = state.copyWith(
        panels: [
          for (final p in state.panels)
            p.copyWith(
              instances: [
                for (final i in p.instances)
                  if (i.id == instanceId)
                    i.copyWith(label: label, clearLabel: label == null)
                  else
                    i,
              ],
            ),
        ],
      );
    });
  }

  // ── z-order ──────────────────────────────────────────────────────────────
  //
  // The canvas renders [StagePanelConfig.instances] in list order, so a
  // later-list instance paints on top. The four reorder helpers below
  // mutate the list to change the apparent z-order without otherwise
  // touching state.

  /// Moves [instanceId] to the end of its panel's instance list — paints
  /// on top of every other widget in the panel.
  void bringInstanceToFront(String instanceId) =>
      _reorder(instanceId, (list, idx) {
        if (idx == list.length - 1) return null;
        final moved = list.removeAt(idx);
        list.add(moved);
        return list;
      });

  /// Moves [instanceId] one position toward the front (toward the end
  /// of the list) within its panel.
  void bringInstanceForward(String instanceId) =>
      _reorder(instanceId, (list, idx) {
        if (idx == list.length - 1) return null;
        final moved = list.removeAt(idx);
        list.insert(idx + 1, moved);
        return list;
      });

  /// Moves [instanceId] one position toward the back (toward the start
  /// of the list) within its panel.
  void sendInstanceBackward(String instanceId) =>
      _reorder(instanceId, (list, idx) {
        if (idx == 0) return null;
        final moved = list.removeAt(idx);
        list.insert(idx - 1, moved);
        return list;
      });

  /// Moves [instanceId] to the beginning of its panel's instance list —
  /// paints behind every other widget in the panel.
  void sendInstanceToBack(String instanceId) =>
      _reorder(instanceId, (list, idx) {
        if (idx == 0) return null;
        final moved = list.removeAt(idx);
        list.insert(0, moved);
        return list;
      });

  /// Internal helper: finds the panel and index containing [instanceId]
  /// then applies [transform] to the mutable instances list. The
  /// transform returns the new list, or null when the move is a no-op.
  void _reorder(
    String instanceId,
    List<StageInstance>? Function(List<StageInstance> list, int index)
    transform,
  ) {
    _recordChange(() {
      for (final panel in state.panels) {
        final idx = panel.instances.indexWhere((i) => i.id == instanceId);
        if (idx < 0) continue;
        final mutable = [...panel.instances];
        final result = transform(mutable, idx);
        if (result == null) return;
        _updatePanel(panel.id, (p) => p.copyWith(instances: result));
        return;
      }
    });
  }

  // ── persistence helpers ──────────────────────────────────────────────────

  /// Replaces the workspace with [workspace] and resets the id counters
  /// so future inserts don't collide with restored ids.
  ///
  /// Clears undo/redo history — loading a session is a fresh starting
  /// point, not a continuation of the prior session's edit history.
  void restoreFromSession(StageWorkspaceState workspace) {
    state = workspace;
    _nextPanelId = _highestSuffix(workspace.panels.map((p) => p.id)) + 1;
    final allInstances = workspace.panels.expand(
      (p) => p.instances.map((i) => i.id),
    );
    _nextInstanceId = _highestSuffix(allInstances) + 1;
    _undoStack.clear();
    _redoStack.clear();
    _pendingTransactionSnapshot = null;
  }

  // ── view-composition recipe seams ──────────────────────────────────

  /// Serialize the Stage workspace into a **signal-identity-based** recipe:
  /// every [StageSignalBinding.signalRef] (a backend-local ref) is rewritten to
  /// its canonical signal path via [resolver]. The per-instance schema-driven
  /// `configuration` map, the bit-slice (`bitIndex` / `bitWidth`), layout, and
  /// labels ride along **verbatim** — the existing serializer is reused as-is.
  StageWorkspaceState toCompositionRecipe(SignalIdentityResolver resolver) =>
      StageWorkspaceState(
        activePanelId: state.activePanelId,
        panels: [
          for (final panel in state.panels)
            panel.copyWith(
              instances: [
                for (final instance in panel.instances)
                  instance.copyWith(
                    signalBindings: {
                      for (final b in instance.signalBindings.entries)
                        b.key: b.value.signalRef.isEmpty
                            ? b.value
                            : b.value.copyWith(
                                signalRef: resolver.pathForRef(
                                  b.value.signalRef,
                                ),
                              ),
                    },
                  ),
              ],
            ),
        ],
      );

  /// Apply a presenter's Stage [recipe], rewriting each binding's canonical
  /// path back to the follower's local `signalRef` via [resolver] and replacing
  /// the workspace. A widget id absent from the follower's [StageRegistry]
  /// renders as a placeholder (the runtime already degrades an unknown widget
  /// gracefully); a binding whose path no local variable matches is bound to
  /// the empty string (the widget renders "unbound"). Both are reported.
  ///
  /// Returns the missing-reference degradation sets.
  ({List<String> missingWidgetIds, List<String> missingSignalPaths})
  applyCompositionRecipe(
    StageWorkspaceState recipe,
    SignalIdentityResolver resolver,
  ) {
    final missingWidgetIds = <String>{};
    final missingSignalPaths = <String>[];
    final panels = [
      for (final panel in recipe.panels)
        panel.copyWith(
          instances: [
            for (final instance in panel.instances)
              () {
                if (!StageRegistry.instance.isRegistered(instance.widgetId)) {
                  missingWidgetIds.add(instance.widgetId);
                }
                return instance.copyWith(
                  signalBindings: {
                    for (final b in instance.signalBindings.entries)
                      b.key: () {
                        if (b.value.signalRef.isEmpty) return b.value;
                        final ref = resolver.refForPath(b.value.signalRef);
                        if (ref == null) {
                          missingSignalPaths.add(b.value.signalRef);
                          return b.value.copyWith(signalRef: '');
                        }
                        return b.value.copyWith(signalRef: ref);
                      }(),
                  },
                );
              }(),
          ],
        ),
    ];
    restoreFromSession(
      StageWorkspaceState(panels: panels, activePanelId: recipe.activePanelId),
    );
    return (
      missingWidgetIds: missingWidgetIds.toList(),
      missingSignalPaths: missingSignalPaths,
    );
  }

  /// Resets the workspace to its initial empty state (used when closing
  /// the current waveform).
  void clear() {
    state = const StageWorkspaceState();
    _nextPanelId = 0;
    _nextInstanceId = 0;
    _undoStack.clear();
    _redoStack.clear();
    _pendingTransactionSnapshot = null;
  }

  // ── internals ────────────────────────────────────────────────────────────

  void _updatePanel(
    String panelId,
    StagePanelConfig Function(StagePanelConfig) f,
  ) {
    state = state.copyWith(
      panels: [
        for (final p in state.panels)
          if (p.id == panelId) f(p) else p,
      ],
    );
  }

  /// Cascade-offsets new instances so the most recent additions don't
  /// stack on top of previous ones at (0, 0).
  double _nextOffsetX(String panelId, double width) {
    final panel = state.panels.firstWhere((p) => p.id == panelId);
    return (panel.instances.length * 24) % 320;
  }

  double _nextOffsetY(String panelId, double height) {
    final panel = state.panels.firstWhere((p) => p.id == panelId);
    return (panel.instances.length * 24) % 240;
  }

  /// Returns the highest numeric suffix found across [ids] of the form
  /// `prefix_<n>`, or -1 if none parse. Used to seed the monotonic
  /// counters after restoring a session.
  static int _highestSuffix(Iterable<String> ids) {
    var max = -1;
    for (final id in ids) {
      final underscore = id.lastIndexOf('_');
      if (underscore < 0) continue;
      final tail = id.substring(underscore + 1);
      final parsed = int.tryParse(tail);
      if (parsed != null && parsed > max) max = parsed;
    }
    return max;
  }
}
