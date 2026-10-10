// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show showCruxErrorSnack;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/comparison/constants/diff_constants.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_list_entry.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/process_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/translator_expansion_provider.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_annotate_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_panel.dart';
import 'package:wavecrux/features/viewer/widgets/signal_color_picker_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/signal_group_header.dart';
import 'package:wavecrux/features/viewer/widgets/signal_removal_feedback.dart';
import 'package:wavecrux/features/viewer/widgets/signal_separator.dart';
import 'package:wavecrux/features/viewer/widgets/translate_filter_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/platform_context_menu.dart';
import 'package:wavecrux/shared/widgets/signal_drag_chip.dart';
import 'package:wavecrux/shared/widgets/trackpad_scroll_listener.dart';

// Sizing for interactive elements is read from [MobileMetrics] per
// ARCHITECTURE.md §3.1.8.1 — see uses below.

// ── Diff status colors ────────────────────────────────────────────────────────

/// Color for a signal dot/label when the diff shows values are identical.
const Color _kDiffIdenticalColor = Color(0xFF43A047); // green 700

/// Color for a signal dot/label when the diff shows values differ.
const Color _kDiffDifferentColor = Color(0xFFE53935); // red 600

/// Color for a signal dot/label when the signal has no counterpart in file B.
const Color _kDiffUnmatchedColor = Color(0xFF9E9E9E); // grey 500

Color? _diffStatusColor(DiffSignalStatus? status) => switch (status) {
  DiffSignalStatus.identical => _kDiffIdenticalColor,
  DiffSignalStatus.different => _kDiffDifferentColor,
  DiffSignalStatus.unmatchedA => _kDiffUnmatchedColor,
  null => null,
};

/// Opaque drag data passed between signal rows and group drop targets.
///
/// Carries the top-level index of the signal being dragged so that
/// [SignalGroupsNotifier.moveSignalIntoGroup] can be called on drop.
typedef _DragData = int;

/// Fixed-width panel showing the ordered list of signals in the waveform viewer.
///
/// Supports drag-and-drop reordering of top-level entries (via the drag
/// handle), group collapse/expand, color cycling, per-signal lane height
/// adjustment, and two ways to move a signal into a group:
///
/// 1. Right-click the signal name → group names appear inline in the menu.
/// 2. Long-press the signal name area and drag it onto a group header.
class SignalListPanel extends ConsumerWidget {
  const SignalListPanel({required this.scrollController, super.key});

  final ScrollController scrollController;

  /// Widget-key value for [entry]'s row — its identity, not its position.
  ///
  /// Exposed so tests address a row by the signal it shows rather than by
  /// the slot it happens to occupy.
  static String signalRowKeyValue(SignalEntry entry) => 'sig_${entry.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signalGroup = ref.watch(signalGroupsProvider);
    final l10n = L10N.of(context);
    final colors =
        Theme.of(context).extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    if (signalGroup.entries.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l10n.signalListPanelEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: colors.timeRulerTick),
            ),
          ),
        ),
      );
    }

    final entries = signalGroup.entries;
    // Positions of every group header, computed once per rebuild. Previously
    // each visible row rescanned the full entries list to offer its
    // "move into group" targets — O(entries × visibleRows) per rebuild, a
    // real cost once gate-level bulk adds put 1M+ entries in the list.
    final groupPositions = <({int index, String name})>[
      for (var i = 0; i < entries.length; i++)
        if (entries[i].kind == SignalEntryKind.group)
          (index: i, name: entries[i].groupName ?? ''),
    ];
    final notifier = ref.read(signalGroupsProvider.notifier);
    final exportNotifier = ref.read(exportProvider.notifier);
    final diff = ref.watch(diffProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final isMobile = metrics.isTouch;
    // Double-tapping a signal name resets its lane to the user's configured
    // default (Settings → Waveform Defaults → lane height), not to a baked
    // constant. This used to be a hardcoded `30`, which silently ignored the
    // setting: a user who preferred 40 dp lanes got 30 dp back on every
    // reset. 30 remains the *model* default, so the fallback here matches
    // AppSettings.defaultLaneHeight's own initializer rather than restating
    // a magic number.
    final defaultLaneHeight =
        ref.watch(appSettingsProvider).value?.defaultLaneHeight ??
        const AppSettings().defaultLaneHeight;
    // Active decoders are rendered as additional rows after the user's
    // signal entries (see itemBuilder below). The canvas appends one
    // transaction-lane per active decoder; rendering matching rows here
    // (instead of inert padding) keeps the bidirectional scroll sync in
    // [WaveformViewCenter] consistent AND gives each decoder a discoverable
    // name + Configure/Remove anchor — replacing the per-lane label that
    // used to be painted at the left edge of the canvas transaction lane,
    // where it overlapped transactions starting near t=0.
    final activeDecoders = ref.watch(activeDecodersProvider);
    // Session decoders this build cannot load follow the active ones, one
    // "not available in this build" row each; the canvas and value column
    // reserve a blank lane per entry to match.
    final heldDecoders = ref.watch(heldDecodersProvider);
    // Map of opaque signalRef → Variable, used to resolve a signal's full
    // hierarchical path for tooltips and the Show-Full-Path menu item.
    // SignalEntry only stores the opaque signalRef (a VCD identifier code
    // like `!`); the human-readable hierarchical path lives on `Variable`.
    final variablesMap = ref.watch(signalVariablesMapProvider);
    // Reserved translator child-row counts (shared with the canvas and value
    // column) so an expanded bitfield signal reserves matching space here.
    final childRowCounts = ref.watch(signalChildRowCountsProvider);

    return Semantics(
      label: l10n.accessibilitySignalListRegion,
      container: true,
      // The list's keyboard home for Delete / Backspace (remove the
      // selection). A click anywhere in the list puts focus here, so the
      // key works straight after a Shift- or Cmd/Ctrl-click without a Tab
      // stop of its own: the rows are reached by pointer, and the keyboard
      // route to the same removal is the Remove Selected Signals command.
      child: Focus(
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: (node, event) => _handleListKey(node, event, context, ref),
        child: Builder(
          builder: (focusContext) => Listener(
            onPointerDown: (_) {
              final node = Focus.of(focusContext);
              // Not while a descendant holds focus: a click into a comment
              // row's text field must keep its caret.
              if (!node.hasFocus) node.requestFocus();
            },
            child: _listBody(
              context,
              ref,
              entries: entries,
              borderColor: borderColor,
              groupPositions: groupPositions,
              notifier: notifier,
              exportNotifier: exportNotifier,
              diff: diff,
              isMobile: isMobile,
              metrics: metrics,
              defaultLaneHeight: defaultLaneHeight,
              activeDecoders: activeDecoders,
              heldDecoders: heldDecoders,
              variablesMap: variablesMap,
              childRowCounts: childRowCounts,
            ),
          ),
        ),
      ),
    );
  }

  Widget _listBody(
    BuildContext context,
    WidgetRef ref, {
    required List<SignalEntry> entries,
    required Color borderColor,
    required List<({int index, String name})> groupPositions,
    required SignalGroupsNotifier notifier,
    required ExportNotifier exportNotifier,
    required DiffState diff,
    required bool isMobile,
    required MobileMetrics metrics,
    required int defaultLaneHeight,
    required List<ActiveDecoder> activeDecoders,
    required List<PersistedDecoder> heldDecoders,
    required Map<String, Variable> variablesMap,
    required Map<String, int> childRowCounts,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: ScrollConfiguration(
        // Opt this list OUT of the app-wide `trackpad` dragDevice (see
        // [kTrackpadOwnedDragDevices]): [TrackpadScrollListener] below already
        // drives [scrollController] from the two-finger pan-zoom, so letting
        // the [ReorderableListView]'s own Scrollable also drag-scroll on the
        // same gesture would double-drive the offset.
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          dragDevices: kTrackpadOwnedDragDevices,
        ),
        // [TrackpadScrollListener] forwards iPad Magic Keyboard / macOS
        // trackpad two-finger vertical scroll into [scrollController] —
        // without it [ReorderableListView] silently swallows
        // PointerPanZoom events and the lane list never scrolls when the
        // user swipes over the signal list.
        child: TrackpadScrollListener(
          controller: scrollController,
          // .builder so off-screen rows are not constructed. With 1000+
          // signals loaded, the previous eager `ReorderableListView(children:
          // [...])` rebuilt every row on every cursor frame (because every
          // row watched a global Map provider keyed on cursor state). The
          // builder only constructs the ~20–40 rows currently visible.
          // Per-signal cursor-value subscription lives in a [Consumer] inside
          // each signal-case row (see [_buildEntryTile]).
          child: ReorderableListView.builder(
            scrollController: scrollController,
            buildDefaultDragHandles: false,
            // Decoder rows are NOT reorderable: they have no
            // [ReorderableDragStartListener], so a long-press on a decoder
            // row never initiates a drag (long-press hits the row's own
            // [PlatformContextMenu] instead). Guard the callback in case
            // the user drags an entry past the last entry — clamp into
            // the entries-only range so the list never tries to interpret
            // a drop position inside the decoder band as an entry move.
            // Under [ReorderableListView.onReorderItem], newIndex is the
            // post-removal insertion index, so the maximum valid value is
            // entries.length - 1.
            onReorderItem: (oldIndex, newIndex) {
              if (oldIndex >= entries.length) return;
              final clampedNewIndex = newIndex >= entries.length
                  ? entries.length - 1
                  : newIndex;
              notifier.reorderSignal(oldIndex, clampedNewIndex);
            },
            itemCount:
                entries.length + activeDecoders.length + heldDecoders.length,
            itemBuilder: (context, index) {
              if (index < entries.length) {
                return _buildEntryTile(
                  context,
                  ref,
                  entries[index],
                  index,
                  groupPositions,
                  notifier,
                  exportNotifier,
                  diff,
                  isMobile,
                  metrics,
                  defaultLaneHeight,
                  variablesMap,
                  childRowCounts,
                );
              }
              final decoderIndex = index - entries.length;
              if (decoderIndex >= activeDecoders.length) {
                final heldIndex = decoderIndex - activeDecoders.length;
                return HeldDecoderListEntry(
                  key: ValueKey('held_dec_$heldIndex'),
                  decoder: heldDecoders[heldIndex],
                  index: heldIndex,
                );
              }
              final decoder = activeDecoders[decoderIndex];
              return DecoderListEntry(
                key: ValueKey('dec_${decoder.id}'),
                decoder: decoder,
                index: decoderIndex,
              );
            },
          ),
        ),
      ),
    );
  }

  /// Selects the signal row whose name the user clicked. A plain click replaces
  /// the selection with just this row; Ctrl/Cmd-click toggles it into/out of the
  /// multi-selection, and Shift-click selects the run of rows from the last
  /// clicked one to this one (matching the value column and signal tree).
  /// Writes both the per-tab [selectedVariablesProvider] — which drives the
  /// name-column, canvas-lane, and value-column highlight — and the root
  /// [selectedSignalProvider], the CXP focus the live auto-broadcast emitter and
  /// the cross-probe panel's per-peer send resolve. This lets a user select an
  /// already-added signal without the signal-tree click's add-and-duplicate
  /// behaviour, and originate an outbound cross-probe straight from the canvas.
  void _selectSignalRow(
    WidgetRef ref, {
    required String fullPath,
    required String signalRef,
  }) {
    final keyboard = HardwareKeyboard.instance;
    final isToggle = keyboard.isControlPressed || keyboard.isMetaPressed;
    final selection = ref.read(selectedVariablesProvider.notifier);
    if (keyboard.isShiftPressed) {
      selection.selectRangeTo(fullPath, _orderedRowPaths(ref));
    } else if (isToggle) {
      selection.toggle(fullPath);
    } else {
      selection.selectOnly(fullPath);
    }
    // Mirror the root CXP focus to the clicked signal so the live emitter and
    // the panel's per-peer send resolve to it. `signalRef` is empty for a
    // non-signal entry; guard so we never publish an empty focus.
    if (signalRef.isNotEmpty) {
      ref.read(selectedSignalProvider.notifier).select(signalRef);
    }
  }

  /// The selection paths of the top-level signal rows, top to bottom — the
  /// order a Shift-click range runs in. Built on demand at click time rather
  /// than on every rebuild, which on a gate-level list is a million entries.
  static List<String> _orderedRowPaths(WidgetRef ref) {
    final variablesMap = ref.read(signalVariablesMapProvider);
    return [
      for (final e in ref.read(signalGroupsProvider).entries)
        if (e.kind == SignalEntryKind.signal)
          SignalGroupsNotifier.selectionPathOf(e, variablesMap),
    ];
  }

  /// Delete or Backspace while the list has focus removes the selection.
  ///
  /// Only when the list itself holds focus — a key typed into a comment row's
  /// text field belongs to that field — and only bare keys, so a modified
  /// chord still reaches whatever it is bound to.
  KeyEventResult _handleListKey(
    FocusNode node,
    KeyEvent event,
    BuildContext context,
    WidgetRef ref,
  ) {
    if (event is! KeyDownEvent || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.delete &&
        key != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    return removeSelectedSignals(context, ref)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// Removes every selected signal from this tab's canvas in one update and
  /// offers an Undo. Returns false when nothing selected is on the canvas.
  ///
  /// The selection is cleared with it: the removed paths would otherwise stay
  /// highlighted in the signal tree with nothing on the canvas to match.
  static bool removeSelectedSignals(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(signalGroupsProvider.notifier);
    final removal = notifier.removeSignalsAtPaths(
      ref.read(selectedVariablesProvider),
      ref.read(signalVariablesMapProvider),
    );
    if (removal == null) return false;
    ref.read(selectedVariablesProvider.notifier).clear();
    showSignalRemovalUndo(context, removal: removal, notifier: notifier);
    return true;
  }

  Widget _buildEntryTile(
    BuildContext context,
    WidgetRef ref,
    SignalEntry entry,
    int index,
    List<({int index, String name})> groupPositions,
    SignalGroupsNotifier notifier,
    ExportNotifier exportNotifier,
    DiffState diff,
    bool isMobile,
    MobileMetrics metrics,
    int defaultLaneHeight,
    Map<String, Variable> variablesMap,
    Map<String, int> childRowCounts,
  ) {
    // A group is never a move-target of itself — drop this row's own
    // position from the pre-computed list (O(#groups), not O(#entries)).
    final availableGroups = [
      for (final g in groupPositions)
        if (g.index != index) g,
    ];

    switch (entry.kind) {
      case SignalEntryKind.signal:
        final signalRef = entry.signalRef ?? '';
        // Resolve the human-readable hierarchical path. SignalEntry stores
        // only the opaque signalRef (a VCD identifier code like `!`); the
        // Variable record carries `scopePath` and `name`, which combine into
        // `fullPath` (e.g. `top.cpu.clk`). Falls back to displayName /
        // signalRef if the variable isn't loaded yet.
        final fullSignalPath = SignalGroupsNotifier.selectionPathOf(
          entry,
          variablesMap,
        );
        final filterNotifier = ref.read(translateFilterProvider.notifier);
        final hasFilter = ref
            .read(translateFilterProvider)
            .containsKey(signalRef);
        final processFilterNotifier = ref.read(processFilterProvider.notifier);
        final hasProcessFilter = ref
            .read(processFilterProvider)
            .containsKey(signalRef);
        final l10n = L10N.of(context);
        final xTraceNotifier = ref.read(xTraceProvider.notifier);
        final diffStatus = ref.watch(
          diffSignalStatusProvider,
        )[signalRef.isNotEmpty ? signalRef : ''];
        final hasXorTrace =
            diff.isActive && diff.xorTraces.containsKey(signalRef);
        // Per-row Consumer: this is the cursor-scrub hot path. Each visible
        // row subscribes to *its own* signalValueAtCursor(signalRef, format)
        // — only the ~20–40 visible rows refetch on cursor change.
        // ref.read(cursorStateProvider) inside the closures avoids
        // adding cursor-state as a Consumer dependency (the family provider
        // already gates rebuild on cursor change).
        // Keyed by the entry's own id, not its position.
        //
        // `_SignalRow` is stateful and a lane-resize drag lives in that
        // State, while the callback that applies the height comes from this
        // build and targets the row at that POSITION. Under a positional
        // key the State stays with the slot, so a list change landing while
        // a drag is in flight — a signal added from the search dialog, the
        // RTL source pane, an annotation, a cross-probe — leaves the
        // in-flight drag resizing a *different* signal, from the wrong
        // starting height. `ReorderableListView` also identifies the
        // dragged child by its key, which a positional key changes
        // mid-drag. Structural rows (group / separator / comment) carry no
        // id and no such state, so they stay positional.
        return Consumer(
          key: ValueKey(SignalListPanel.signalRowKeyValue(entry)),
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
            final formattedValue = signalValue?.formatted;
            final hasX = signalValue?.hasX ?? false;
            final cursorTime = innerRef
                .read(cursorStateProvider)
                .primaryCursorTime;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SignalRow(
                  entry: entry,
                  index: index,
                  formattedValue: formattedValue,
                  fullPath: fullSignalPath,
                  availableGroups: availableGroups,
                  isSelected: innerRef
                      .watch(selectedVariablesProvider)
                      .contains(fullSignalPath),
                  onSelect: () => _selectSignalRow(
                    innerRef,
                    fullPath: fullSignalPath,
                    signalRef: signalRef,
                  ),
                  diffStatusColor: _diffStatusColor(diffStatus),
                  isMobile: isMobile,
                  metrics: metrics,
                  defaultLaneHeight: defaultLaneHeight,
                  onRemove: () => notifier.removeSignal(index),
                  onRemoveSelected: () => removeSelectedSignals(context, ref),
                  onColorCycle: () => notifier.setSignalColor(
                    index,
                    _nextPaletteColor(entry.argbColor),
                  ),
                  onColorPicked: (color) =>
                      notifier.setSignalColor(index, color),
                  onToggleRenderAsAnalog: () =>
                      notifier.setSignalRenderAsAnalog(
                        entry.id,
                        renderAsAnalog: !entry.renderAsAnalog,
                      ),
                  onHeightChanged: (h) => notifier.setLaneHeight(
                    index,
                    h,
                    // Touch floor: keeps stored == rendered after an interactive
                    // resize, so a shrink drag past the visual floor doesn't
                    // leave a tiny stored value that surfaces on desktop.
                    minHeight: metrics.minLaneHeight,
                  ),
                  onMoveToGroup: (groupIndex) =>
                      notifier.moveSignalIntoGroup(index, groupIndex),
                  onCopyValue: formattedValue == null
                      ? null
                      : () => exportNotifier.copySignalValue(
                          context,
                          signalRef,
                          formattedValue,
                        ),
                  onCopyPath: () =>
                      exportNotifier.copySignalPath(context, fullSignalPath),
                  hasTranslateFilter: hasFilter,
                  onAssignFilter: () async {
                    final path = await TranslateFilterPickerDialog.show(
                      context,
                    );
                    if (path != null) {
                      await filterNotifier.assignFilter(signalRef, path);
                    }
                  },
                  onRemoveFilter: hasFilter
                      ? () => filterNotifier.removeFilter(signalRef)
                      : null,
                  hasProcessFilter: hasProcessFilter,
                  onAssignProcessFilter: () async {
                    if (ref.read(systemDialogInFlightProvider)) return;
                    // Read before the await; see [SystemDialogInFlight.end].
                    final inFlight = ref.read(
                      systemDialogInFlightProvider.notifier,
                    )..begin();
                    final FilePickerResult? result;
                    try {
                      result = await FilePicker.pickFiles(
                        dialogTitle: l10n.processFilterPickerTitle,
                      );
                    } finally {
                      inFlight.end();
                    }
                    final path = result?.files.firstOrNull?.path;
                    if (path != null && context.mounted) {
                      final error = await processFilterNotifier
                          .setProcessFilter(
                            signalRef,
                            path,
                          );
                      if (error != null && context.mounted) {
                        showCruxErrorSnack(
                          context,
                          l10n.processFilterSandboxError,
                        );
                      }
                    }
                  },
                  onClearProcessFilter: hasProcessFilter
                      ? () =>
                            processFilterNotifier.removeProcessFilter(signalRef)
                      : null,
                  hasX: hasX,
                  onTraceXOrigin: hasX && cursorTime != null
                      ? () => xTraceNotifier.traceXAndReveal(
                          signalRef,
                          cursorTime,
                        )
                      : null,
                  canVisualizeFsm: _isFsmCandidate(ref, signalRef),
                  onVisualizeFsm: () => _visualizeFsm(context, ref, signalRef),
                  onAnnotateFsm: () => _annotateFsm(context, ref, signalRef),
                ),
                // Reserve blank space matching the value column's expanded
                // translator child rows so the signal-names list stays aligned
                // with the canvas and value column (shared geometry; child names
                // are rendered in the value column).
                if (childRowCounts[entry.id] != null)
                  SizedBox(height: childRowCounts[entry.id]! * kChildRowHeight),
                if (hasXorTrace) const _XorDiffSpacer(),
              ],
            );
          },
        );

      case SignalEntryKind.group:
        return _GroupTile(
          key: ValueKey('grp_$index'),
          entry: entry,
          index: index,
          isMobile: isMobile,
          metrics: metrics,
          onToggleCollapsed: () => notifier.toggleGroupCollapsed(index),
          onRename: (name) => notifier.renameGroup(index, name),
          onDissolve: () => notifier.dissolveGroup(index),
          onRemoveWithSignals: () {
            final removal = notifier.removeGroupWithSignals(index);
            if (removal == null) return;
            showSignalRemovalUndo(
              context,
              removal: removal,
              notifier: notifier,
            );
          },
          onRemoveChild: (childIndex) =>
              notifier.removeChildFromGroup(index, childIndex),
          onSignalDropped: (signalIndex) =>
              notifier.moveSignalIntoGroup(signalIndex, index),
          xorSignalRefs: diff.isActive
              ? diff.xorTraces.keys.toSet()
              : const <String>{},
        );

      case SignalEntryKind.separator:
        return KeyedSubtree(
          key: ValueKey('sep_$index'),
          child: const SignalSeparator(isComment: false),
        );

      case SignalEntryKind.comment:
        return KeyedSubtree(
          key: ValueKey('cmt_$index'),
          child: SignalSeparator(
            isComment: true,
            commentText: entry.text,
            onCommentChanged: (text) => notifier.setCommentText(index, text),
          ),
        );
    }
  }

  static Color _nextPaletteColor(int? currentArgb) {
    final palette = signalColorPalette;
    if (currentArgb == null) return palette.first;
    final idx = palette.indexWhere((c) => c.toARGB32() == currentArgb);
    return palette[(idx + 1) % palette.length];
  }

  /// Whether [signalRef] is suitable for FSM visualisation.
  ///
  /// Currently any signal with a known bit width ≥ 2 qualifies. Real and
  /// 1-bit signals are excluded — a 1-bit FSM is just a toggle and a real
  /// value cannot enumerate a finite state space.
  bool _isFsmCandidate(WidgetRef ref, String signalRef) {
    if (signalRef.isEmpty) return false;
    final variable = ref.read(signalVariablesMapProvider)[signalRef];
    if (variable == null) return false;
    if (variable.isReal) return false;
    final bw = variable.bitWidth;
    return bw != null && bw >= 2;
  }

  Future<void> _visualizeFsm(
    BuildContext context,
    WidgetRef ref,
    String signalRef,
  ) async {
    await ref.read(fsmProvider.notifier).analyzeSignal(signalRef);
    if (!context.mounted) return;
    // On phone, the bottom pane is unavailable; show the FSM modally.
    final deviceClass = ref.read(deviceClassProvider);
    if (deviceClass == DeviceClass.phone ||
        deviceClass == DeviceClass.phoneLandscape) {
      await FsmPanel.showFsmModal(
        context,
        tabContainer: ProviderScope.containerOf(context, listen: false),
      );
    }
  }

  Future<void> _annotateFsm(
    BuildContext context,
    WidgetRef ref,
    String signalRef,
  ) async {
    final activeModel = ref.read(fsmProvider).model;
    final relevantModel = activeModel?.signalRef == signalRef
        ? activeModel
        : null;
    await FsmAnnotateDialog.show(
      context,
      signalRef: signalRef,
      model: relevantModel,
      tabContainer: ProviderScope.containerOf(context, listen: false),
    );
  }
}

// ── Context menu result type ──────────────────────────────────────────────────

/// Sealed type returned by the signal right-click context menu.
///
/// Regular actions are [_SignalMenuAction]; choosing a group to move into
/// produces [_SignalMenuMoveToGroup].
sealed class _SignalMenuResult {
  const _SignalMenuResult();
}

enum _RegularAction {
  changeColor,
  toggleRenderAsAnalog,
  copyValue,
  copyPath,
  assignFilter,
  removeFilter,
  assignProcessFilter,
  clearProcessFilter,
  traceXOrigin,
  visualizeFsm,
  annotateFsm,
  removeSelected,
}

class _SignalMenuAction extends _SignalMenuResult {
  const _SignalMenuAction(this.action);
  final _RegularAction action;
}

class _SignalMenuMoveToGroup extends _SignalMenuResult {
  const _SignalMenuMoveToGroup(this.groupIndex);
  final int groupIndex;
}

// ── Signal row ────────────────────────────────────────────────────────────────

/// One signal lane row in the signal list panel.
///
/// **Reorder drag**: grab the ≡ handle on the left — works with the outer
/// [ReorderableListView].
///
/// **Group drag**: long-press anywhere on the signal name/color area, then
/// drag onto a group header to move the signal into that group.
class _SignalRow extends StatefulWidget {
  const _SignalRow({
    required this.entry,
    required this.index,
    required this.fullPath,
    required this.availableGroups,
    required this.isSelected,
    required this.onSelect,
    required this.onRemove,
    required this.onRemoveSelected,
    required this.onColorCycle,
    required this.onColorPicked,
    required this.onToggleRenderAsAnalog,
    required this.onHeightChanged,
    required this.onMoveToGroup,
    required this.onCopyPath,
    required this.isMobile,
    required this.metrics,
    required this.defaultLaneHeight,
    this.diffStatusColor,
    this.formattedValue,
    this.onCopyValue,
    this.hasTranslateFilter = false,
    this.onAssignFilter,
    this.onRemoveFilter,
    this.hasProcessFilter = false,
    this.onAssignProcessFilter,
    this.onClearProcessFilter,
    this.hasX = false,
    this.onTraceXOrigin,
    this.canVisualizeFsm = false,
    this.onVisualizeFsm,
    this.onAnnotateFsm,
  });

  final SignalEntry entry;
  final int index;
  final String fullPath;

  /// Whether this row's signal is in the per-tab selection
  /// (`selectedVariablesProvider`). Drives the name-column selection
  /// treatment (accent background + bold name) that mirrors the canvas lane
  /// tint and value-column row highlight.
  final bool isSelected;

  /// Invoked when the user clicks the signal name to select this row. The
  /// parent inspects the keyboard modifiers (Ctrl/Cmd → toggle) and writes
  /// the per-tab `selectedVariablesProvider` + the root `selectedSignalProvider`
  /// so a canvas name-click drives the same selection an inbound cross-probe
  /// and the panel's per-peer send resolve.
  final VoidCallback onSelect;

  /// Whether we're running on a mobile device class (phone or tablet).
  /// Used to increase touch target sizes and enable long-press context menus.
  final bool isMobile;

  /// Sizing for icons, drag handle, color swatch, remove button, and lane
  /// resize handle. Per ARCHITECTURE.md §3.1.8.
  final MobileMetrics metrics;

  /// Lane height a double-tap on the signal name resets this row to, in dp.
  ///
  /// Sourced from the user's Settings → Waveform Defaults lane height rather
  /// than a baked constant, so "reset" returns to the height the user chose.
  final int defaultLaneHeight;

  /// When non-null, overrides the normal entry color with the active diff
  /// status color (green = identical, red = different, grey = unmatched).
  final Color? diffStatusColor;

  final String? formattedValue;
  final List<({int index, String name})> availableGroups;
  final VoidCallback onRemove;

  /// Removes the whole selection (this row among it). Offered in the context
  /// menu of a selected row only — on an unselected row it would remove rows
  /// other than the one clicked.
  final VoidCallback onRemoveSelected;
  final VoidCallback onColorCycle;
  final ValueChanged<Color> onColorPicked;

  /// Flips this row between an analog curve and a normal digital lane.
  ///
  /// The same action the value column's context menu offers. Duplicated
  /// deliberately: the format/rendering menu lives in the value column, but
  /// GTKWave puts Data Format on the signal name, so a user migrating from it
  /// right-clicks here first and finds nothing.
  final VoidCallback onToggleRenderAsAnalog;
  final ValueChanged<double> onHeightChanged;
  final ValueChanged<int> onMoveToGroup;
  final VoidCallback onCopyPath;
  final VoidCallback? onCopyValue;
  final bool hasTranslateFilter;
  final Future<void> Function()? onAssignFilter;
  final VoidCallback? onRemoveFilter;
  final bool hasProcessFilter;
  final Future<void> Function()? onAssignProcessFilter;
  final VoidCallback? onClearProcessFilter;
  final bool hasX;
  final VoidCallback? onTraceXOrigin;

  /// Whether this signal can be visualised as an FSM (vector signal with
  /// bit width ≥ 2). When false, the FSM menu entries are hidden.
  final bool canVisualizeFsm;

  /// Invoked when the user activates "Visualize as FSM" from the menu.
  final VoidCallback? onVisualizeFsm;

  /// Invoked when the user activates "Annotate FSM states…" from the menu.
  final VoidCallback? onAnnotateFsm;

  @override
  State<_SignalRow> createState() => _SignalRowState();
}

class _SignalRowState extends State<_SignalRow> {
  double _dragStartY = 0;
  double _dragStartHeight = 0;

  /// True while a vertical resize gesture is in progress. Drives the visible
  /// grip color (outlineVariant at rest → primary while dragging) per
  /// ARCHITECTURE.md §3.1.8.8.
  bool _isResizing = false;

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final l10n = L10N.of(context);
    final signalColor = widget.entry.argbColor != null
        ? Color(widget.entry.argbColor!)
        : WavecruxColors.signalGreen;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    final items = <PopupMenuEntry<_SignalMenuResult>>[
      // ── Path header — always visible reveal of the truncated row name ────
      // Per ARCHITECTURE.md §3.1.8.14, every truncated `Text(overflow:
      // ellipsis)` must pair with a reveal. The signal name in the row is
      // narrow and ellipsizes; this header surfaces the full hierarchical
      // path the moment the menu opens — no "Show Full Path…" guess
      // required. The "Copy Full Path" action below copies the same string.
      PopupMenuItem<_SignalMenuResult>(
        enabled: false,
        height: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            widget.fullPath,
            style: TextStyle(
              fontFamily: WavecruxColors.monoFontFamily,
              fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            softWrap: true,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      const PopupMenuDivider(),
      // ── Change color ──
      PopupMenuItem<_SignalMenuResult>(
        value: const _SignalMenuAction(_RegularAction.changeColor),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: signalColor,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              l10n.signalListChangeColor,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      // ── Analog / digital rendering ──
      // Sits beside Change color because both answer "how does this lane
      // look", and it is duplicated from the value column's menu on purpose:
      // GTKWave puts Data Format on the signal name, so that is where someone
      // arriving from GTKWave right-clicks first.
      PopupMenuItem<_SignalMenuResult>(
        value: const _SignalMenuAction(_RegularAction.toggleRenderAsAnalog),
        child: Row(
          children: [
            Icon(
              widget.entry.renderAsAnalog ? Icons.bar_chart : Icons.show_chart,
              size: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              widget.entry.renderAsAnalog
                  ? l10n.valueColumnRenderAsDigital
                  : l10n.valueColumnRenderAsAnalog,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      // ── Inline group targets ──────────────────────────────────────────────
      if (widget.availableGroups.isNotEmpty) ...[
        const PopupMenuDivider(),
        PopupMenuItem<_SignalMenuResult>(
          enabled: false,
          height: 22,
          child: Text(
            l10n.signalGroupMoveToGroup,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final g in widget.availableGroups)
          PopupMenuItem<_SignalMenuResult>(
            value: _SignalMenuMoveToGroup(g.index),
            height: 30,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      g.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      const PopupMenuDivider(),
      // ── Clipboard ──
      if (widget.onCopyValue != null)
        PopupMenuItem<_SignalMenuResult>(
          value: const _SignalMenuAction(_RegularAction.copyValue),
          child: Text(
            l10n.signalListCopyValue,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      PopupMenuItem<_SignalMenuResult>(
        value: const _SignalMenuAction(_RegularAction.copyPath),
        child: Text(
          l10n.signalListCopyPath,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      const PopupMenuDivider(),
      // ── Translate filter ──
      PopupMenuItem<_SignalMenuResult>(
        value: const _SignalMenuAction(_RegularAction.assignFilter),
        child: Text(
          l10n.translateFilterAssign,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      if (widget.hasTranslateFilter)
        PopupMenuItem<_SignalMenuResult>(
          value: const _SignalMenuAction(_RegularAction.removeFilter),
          child: Text(
            l10n.translateFilterRemove,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      // ── Process filter ──
      PopupMenuItem<_SignalMenuResult>(
        value: const _SignalMenuAction(_RegularAction.assignProcessFilter),
        child: Text(
          l10n.processFilterAssign,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      if (widget.hasProcessFilter)
        PopupMenuItem<_SignalMenuResult>(
          value: const _SignalMenuAction(_RegularAction.clearProcessFilter),
          child: Text(
            l10n.processFilterClear,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      // ── X-trace ──
      if (widget.hasX) ...[
        const PopupMenuDivider(),
        PopupMenuItem<_SignalMenuResult>(
          value: const _SignalMenuAction(_RegularAction.traceXOrigin),
          child: Row(
            children: [
              Icon(
                Icons.search_off,
                size: 13,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
              Text(l10n.xTraceMenuLabel, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
      // ── FSM ──
      if (widget.canVisualizeFsm) ...[
        const PopupMenuDivider(),
        PopupMenuItem<_SignalMenuResult>(
          value: const _SignalMenuAction(_RegularAction.visualizeFsm),
          child: Row(
            children: [
              Icon(
                Icons.account_tree,
                size: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(l10n.fsmMenuVisualize, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<_SignalMenuResult>(
          value: const _SignalMenuAction(_RegularAction.annotateFsm),
          child: Text(
            l10n.fsmMenuAnnotateStates,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
      // ── Remove the selection ──
      if (widget.isSelected) ...[
        const PopupMenuDivider(),
        PopupMenuItem<_SignalMenuResult>(
          value: const _SignalMenuAction(_RegularAction.removeSelected),
          child: Text(
            l10n.signalListRemoveSelected,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ];

    final result = await showMenu<_SignalMenuResult>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (!context.mounted) return;

    switch (result) {
      case _SignalMenuAction(:final action):
        switch (action) {
          case _RegularAction.changeColor:
            final picked = await SignalColorPickerDialog.show(
              context,
              signalColor,
            );
            if (picked != null) widget.onColorPicked(picked);
          case _RegularAction.toggleRenderAsAnalog:
            widget.onToggleRenderAsAnalog();
          case _RegularAction.copyValue:
            widget.onCopyValue?.call();
          case _RegularAction.copyPath:
            widget.onCopyPath();
          case _RegularAction.assignFilter:
            await widget.onAssignFilter?.call();
          case _RegularAction.removeFilter:
            widget.onRemoveFilter?.call();
          case _RegularAction.assignProcessFilter:
            await widget.onAssignProcessFilter?.call();
          case _RegularAction.clearProcessFilter:
            widget.onClearProcessFilter?.call();
          case _RegularAction.traceXOrigin:
            widget.onTraceXOrigin?.call();
          case _RegularAction.visualizeFsm:
            widget.onVisualizeFsm?.call();
          case _RegularAction.annotateFsm:
            widget.onAnnotateFsm?.call();
          case _RegularAction.removeSelected:
            widget.onRemoveSelected();
        }
      case _SignalMenuMoveToGroup(:final groupIndex):
        widget.onMoveToGroup(groupIndex);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colors =
        Theme.of(context).extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();
    // Diff status color overrides the user-configured entry color while a
    // comparison is active. The user's color is preserved; the override only
    // applies to the visual display.
    final signalColor =
        widget.diffStatusColor ??
        (widget.entry.argbColor != null
            ? Color(widget.entry.argbColor!)
            : WavecruxColors.signalGreen);
    final displayName =
        widget.entry.displayName ?? widget.entry.signalRef ?? '';

    // Wrap the entire row with PlatformContextMenu so right-click (desktop)
    // and long-press (mobile / iPad) open the context menu — including the
    // signal name itself, since the long-press drag-into-group has been
    // removed in favor of the "Move to group…" entry in the menu.  This
    // satisfies ARCHITECTURE.md §3.1.8.5 (long-press = right-click universally).
    final metrics = widget.metrics;
    // Row height comes from the shared [LaneGeometry] model (the one clamp
    // site), so the signal-names column, canvas, and value column can't
    // diverge. On touch the resize strip is 16 dp, so a stored 30 dp lane would
    // leave only 14 dp for content; the model clamps up to
    // LaneMetrics.minLaneHeight (44 dp on touch) at render time only. The
    // stored entry.laneHeight is never flattened — desktop sessions with 24 dp
    // lanes still re-open at 24 dp on desktop (store raw, render clamped).
    final effectiveLaneHeight = LaneGeometry.heightForEntry(
      widget.entry,
      LaneMetrics(minLaneHeight: metrics.minLaneHeight),
    );
    // ── Body row content (color swatch + filter icon + signal name) ─────
    // Built as a separate widget so it can be wrapped in a single
    // Draggable<String> without disturbing the surrounding reorder
    // handle + remove button. The row body is the natural drag-to-Stage
    // source for signals that are already in the viewer (since the
    // user has typically curated which signals matter by adding them
    // to the waveform). Reorder remains pinned to the explicit drag
    // handle per ARCHITECTURE.md §3.1.8.5.
    //
    // Wrapped in LayoutBuilder so that mid-resize, when the signal-tree
    // pane drops below the color swatch's `metrics.touchTarget`, we render
    // a bare signal-name `Text` instead of letting `Row` assert on overflow.
    final colorSwatchMin = metrics.touchTarget;
    final bodyContent = LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < colorSwatchMin) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: WavecruxColors.monoFontFamily,
                fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                fontSize: metrics.monoText,
                color: signalColor,
              ),
            ),
          );
        }
        return Row(
          children: [
            // ── Color swatch (44 dp hit target on touch) ──────────────
            // Behavior is `translucent` (not `opaque`) so unhandled
            // gestures — specifically long-press — bubble to the outer
            // PlatformContextMenu. Opaque hit-testing here would claim
            // the long-press, prevent the row's context menu from
            // opening, and the inner onTap would *also* fire after
            // dialog dismissal — overwriting whatever color the user
            // just chose. Per ARCHITECTURE.md §3.1.8.5 gesture bubbling.
            //
            // The tooltip uses TooltipTriggerMode.manual on touch so
            // its internal LongPressGestureRecognizer doesn't beat the
            // outer PlatformContextMenu in the gesture arena. Hover
            // still shows the tooltip on desktop (mouse) regardless.
            Tooltip(
              message: l10n.signalEntryChangeColorTooltip,
              triggerMode: TooltipTriggerMode.manual,
              child: Semantics(
                button: true,
                label: l10n.accessibilityCycleSignalColor(displayName),
                child: GestureDetector(
                  key: const ValueKey('_signalRow_colorSwatch'),
                  onTap: widget.onColorCycle,
                  behavior: HitTestBehavior.translucent,
                  child: SizedBox(
                    width: metrics.touchTarget,
                    height: metrics.touchTarget,
                    child: Center(
                      child: Container(
                        width: metrics.colorSwatch,
                        height: metrics.colorSwatch,
                        decoration: BoxDecoration(
                          color: signalColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── Process filter indicator ──────────────────────────────
            if (widget.hasProcessFilter)
              Tooltip(
                message: l10n.processFilterActiveTooltip,
                triggerMode: TooltipTriggerMode.manual,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.terminal,
                    size: metrics.iconSize * 0.6,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            // ── Signal name — double-tap resets lane height ───────────
            // Long-press is reserved for the row-wide context menu.
            // Move-to-group lives in that menu instead of being a
            // separate gesture (ARCHITECTURE.md §3.1.8.5).
            Expanded(
              // One node for the name, carrying the selected state the
              // highlight bar shows, so a screen reader hears which rows a
              // Delete would remove.
              child: Semantics(
                container: true,
                selected: widget.isSelected,
                child: GestureDetector(
                  // Single click on the signal NAME selects this row — the way to
                  // select an already-added signal without re-adding it (a signal-
                  // tree click ADDS, duplicating the lane). Writes the same
                  // per-tab `selectedVariablesProvider` an inbound cross-probe and
                  // the panel's per-peer send resolve, so a canvas name-click can
                  // originate an outbound cross-probe.
                  onTap: widget.onSelect,
                  onDoubleTap: () => widget.onHeightChanged(
                    widget.defaultLaneHeight.toDouble(),
                  ),
                  // Tooltip reveals the full hierarchical path on hover
                  // (desktop). Per ARCHITECTURE.md §3.1.8.14, every
                  // TextOverflow.ellipsis must pair with a tooltip
                  // and/or a context-menu reveal — we have both.
                  //
                  // triggerMode is `manual` so on touch the Tooltip's
                  // internal LongPressGestureRecognizer doesn't beat
                  // the outer PlatformContextMenu in the gesture arena.
                  // On touch, users see the full path via the
                  // "Show Full Path…" context-menu item instead.
                  child: Tooltip(
                    message: widget.fullPath,
                    waitDuration: const Duration(milliseconds: 600),
                    triggerMode: TooltipTriggerMode.manual,
                    // Issue 15: a bare Align(centerLeft) does not vertically center
                    // here because the outer Row uses CrossAxisAlignment.center (the
                    // default) — that gives the Expanded child loose vertical
                    // constraints, so Align ends up sized to the Text's intrinsic
                    // height and centering inside its own (shrunk) bounds has no
                    // effect. SizedBox.expand forces the Align to span the full
                    // lane height, after which Alignment.centerLeft vertically
                    // centers the Text against the lane.
                    child: SizedBox.expand(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          displayName,
                          // Font metric tuning to visually center the painted
                          // glyph at the lane's vertical middle:
                          //
                          // - `height: 1.0` collapses the Text widget's line box
                          //   to the font size, eliminating the natural line
                          //   leading that monospace fonts ship with.
                          // - `leadingDistribution: even` splits any residual
                          //   leading evenly above and below the glyph instead
                          //   of dumping it above (the default for proportional
                          //   leading behavior).
                          // - `textHeightBehavior(apply*: false)` is required
                          //   in tandem with `height` to disable the
                          //   first-line ascent and last-line descent padding
                          //   that Flutter otherwise injects.
                          // - `strutStyle(forceStrutHeight, height: 1)`
                          //   forces the actual line metrics to honor the
                          //   above even when the font's intrinsic line height
                          //   would override them.
                          //
                          // Without these, monospace fonts (notably
                          // JetBrainsMono — ascent 1.02em, descent 0.3em)
                          // position the glyph in the upper ~60% of the
                          // line box. Align(centerLeft) centered the line box
                          // but the glyph still looked top-aligned, and the
                          // effect was severe at the default 30 dp lane height
                          // where every dp of font padding is visible.
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                          strutStyle: const StrutStyle(
                            forceStrutHeight: true,
                            height: 1,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                          style: TextStyle(
                            fontFamily: WavecruxColors.monoFontFamily,
                            fontFamilyFallback:
                                WavecruxColors.monoFontFamilyFallback,
                            fontSize: metrics.monoText,
                            color: signalColor,
                            // Selected-row name treatment: bold weight only —
                            // the selection SURFACE is the full-row tint painted
                            // by the row host (matching the value column's and
                            // canvas lane's highlight bars), not a text
                            // background, so all three panes read identically.
                            fontWeight: widget.isSelected
                                ? FontWeight.bold
                                : null,
                            overflow: TextOverflow.ellipsis,
                            height: 1,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    // Drag-to-Stage source. Affinity is horizontal so vertical
    // pans inside the (scrollable) ReorderableListView still scroll
    // — the user pulls slightly sideways to pick up a signal, then
    // moves freely. Mirrors the same pattern in VariableTreeLeaf,
    // and the Stage tile / board-slot DragTargets already accept
    // any String payload so no receive-side changes are needed.
    final signalRef = widget.entry.signalRef ?? '';
    final draggableBody = signalRef.isEmpty
        ? bodyContent
        : Draggable<String>(
            data: signalRef,
            affinity: Axis.horizontal,
            feedback: SignalDragChip(text: widget.fullPath),
            childWhenDragging: Opacity(opacity: 0.4, child: bodyContent),
            child: bodyContent,
          );

    return PlatformContextMenu(
      onContextMenu: (pos) => _showContextMenu(context, pos),
      child: SizedBox(
        height: effectiveLaneHeight,
        child: Stack(
          children: [
            // Selected-row highlight BAR — the same full-row primary tint the
            // value column paints (alpha 0.18) and the canvas echoes as a lane
            // tint, so a selection reads as one continuous bar across all
            // three panes (a text-background-only treatment here would break
            // that continuity).
            if (widget.isSelected)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.18),
                ),
              ),
            // Content row spans the FULL lane height (not lane − resize
            // handle) so vertical centering of the color swatch + signal
            // name lines up with the canvas's lane-centered waveform trace.
            // Previously we used `Positioned.fill(bottom: laneResizeHandle)`
            // which restricted centering to the top (lane − 4dp) on desktop,
            // so the name and bullet ended up ~2dp above the lane's true
            // center. The resize grip is drawn LATER in this Stack with
            // `HitTestBehavior.opaque` over the bottom strip, so it still
            // wins pointer events for vertical drag-resize without needing
            // a layout reservation here.
            //
            // Visual centering nudge: the widget tree centers each child at
            // the lane's geometric center (verified by widget tests at 30
            // dp and 100 dp lanes), but in practice the painted text glyph
            // sits slightly above the Text widget's vertical center because
            // monospace fonts (JetBrainsMono ascent 1.02em > 1) have a
            // larger ascent than descent. Setting `height: 1` on the
            // TextStyle made things worse on production because the
            // natural ascent overflowed the collapsed line box. The
            // pragmatic fix is a small downward `Transform.translate` on
            // the entire row content so the visible glyph (and the bullet
            // beside it) lands at lane center. Transform shifts the
            // rendered output without affecting layout — pointer hit-test
            // rects and the test-measured widget bounds remain unchanged.
            Positioned.fill(
              child: Transform.translate(
                // Production visual nudge: with the diagnostic build (20 dp
                // offset + magenta row backgrounds), the user confirmed my
                // Transform IS being applied — every chrome element shifted
                // visibly to the bottom of (or below) each magenta row. The
                // user's earlier "still top-aligned" report with 2 dp meant
                // the shift was real but below their perception threshold.
                // 5 dp is the empirical sweet spot: large enough to read as
                // a clear downward shift, small enough that even the 16 dp
                // minimum lane on touch keeps the chrome inside the row.
                offset: const Offset(0, 5),
                // Mid-resize the signal-tree pane can momentarily drop below
                // the row's hard minimum (drag handle + close button =
                // 2 × `metrics.touchTarget` on touch). Without the
                // LayoutBuilder gate the row's `RenderFlex` asserts on every
                // intermediate resize frame; with it, we render the bare
                // draggable body until the pane is wide enough to fit the
                // chrome again. Chrome reappears the moment the resize
                // settles back above the threshold.
                child: LayoutBuilder(
                  builder: (context, c) {
                    final minChrome =
                        metrics.dragHandleHitArea + metrics.touchTarget;
                    if (c.maxWidth < minChrome) {
                      return Row(children: [Expanded(child: draggableBody)]);
                    }
                    return Row(
                      children: [
                        // ── Reorder handle (drag via ReorderableListView) ──
                        ReorderableDragStartListener(
                          index: widget.index,
                          child: SizedBox(
                            width: metrics.dragHandleHitArea,
                            height: metrics.dragHandleHitArea,
                            child: Center(
                              child: Icon(
                                Icons.drag_handle,
                                size: metrics.iconSize,
                                color: colors.timeRulerTick,
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: draggableBody),
                        // ── Remove button — full touch target on touch ─────
                        // Tooltip and GestureDetector both use `manual`/
                        // `translucent` so long-press bubbles to the outer
                        // PlatformContextMenu (ARCHITECTURE.md §3.1.8.5).
                        Tooltip(
                          message: l10n.signalEntryRemoveTooltip,
                          triggerMode: TooltipTriggerMode.manual,
                          child: Semantics(
                            button: true,
                            label: l10n.accessibilityRemoveSignal(displayName),
                            child: GestureDetector(
                              onTap: widget.onRemove,
                              behavior: HitTestBehavior.translucent,
                              child: SizedBox(
                                width: metrics.touchTarget,
                                height: metrics.touchTarget,
                                child: Center(
                                  child: Icon(
                                    Icons.close,
                                    size: metrics.iconSize * 0.7,
                                    color: colors.timeRulerTick,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // ── Lane-height resize handle (bottom strip + visible grip) ────
            // Per ARCHITECTURE.md §3.1.8.8: 16 dp on touch with a two-line grip,
            // 4 dp on desktop (existing behavior). The grip uses outlineVariant
            // for low-emphasis at rest and brightens to primary while dragging.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: metrics.laneResizeHandle,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (d) {
                    _dragStartY = d.globalPosition.dy;
                    // Capture the *rendered* height (from the shared model, the
                    // one clamp site) so the drag tracks the user's finger 1:1.
                    // With render-time minimum lane height on touch (see
                    // [build]), the stored entry.laneHeight may be smaller than
                    // what's drawn; using the stored value here would make a
                    // drag of N dp produce a visual change of
                    // N − (minLaneHeight − stored) dp.
                    _dragStartHeight = LaneGeometry.heightForEntry(
                      widget.entry,
                      LaneMetrics(minLaneHeight: widget.metrics.minLaneHeight),
                    );
                    setState(() => _isResizing = true);
                  },
                  onVerticalDragUpdate: (d) {
                    final delta = d.globalPosition.dy - _dragStartY;
                    widget.onHeightChanged(_dragStartHeight + delta);
                  },
                  onVerticalDragEnd: (_) => setState(() => _isResizing = false),
                  onVerticalDragCancel: () =>
                      setState(() => _isResizing = false),
                  child: metrics.isTouch
                      ? CustomPaint(
                          painter: _LaneResizeGripPainter(
                            color: _isResizing
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Group tile ────────────────────────────────────────────────────────────────

/// Renders a group header and its (possibly collapsed) children.
///
/// The header is a [DragTarget] — dragging a signal (via [LongPressDraggable]
/// in [_SignalRow]) onto the header calls [onSignalDropped] with the signal's
/// top-level index. A green highlight appears while a valid drag hovers.
class _GroupTile extends StatefulWidget {
  const _GroupTile({
    required this.entry,
    required this.index,
    required this.onToggleCollapsed,
    required this.onRename,
    required this.onDissolve,
    required this.onRemoveWithSignals,
    required this.onRemoveChild,
    required this.onSignalDropped,
    required this.isMobile,
    required this.metrics,
    this.xorSignalRefs = const <String>{},
    super.key,
  });

  final SignalEntry entry;
  final int index;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String> onRename;

  /// Ungroup: the header goes, its signals stay on the canvas.
  final VoidCallback onDissolve;

  /// Remove Group and Signals: the header and every row in it leave the
  /// canvas, with an Undo.
  final VoidCallback onRemoveWithSignals;
  final ValueChanged<int> onRemoveChild;
  final ValueChanged<int> onSignalDropped;
  final bool isMobile;
  final MobileMetrics metrics;

  /// Signal refs that have an active XOR diff trace. A spacer is inserted
  /// after each group child whose ref is in this set.
  final Set<String> xorSignalRefs;

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _isDragOver = false;

  static int _countSignals(List<SignalEntry> children) {
    var count = 0;
    for (final c in children) {
      if (c.kind == SignalEntryKind.signal) count++;
      if (c.kind == SignalEntryKind.group) count += _countSignals(c.children);
    }
    return count;
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final l10n = L10N.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final result = await showMenu<_GroupContextAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _GroupContextAction.rename,
          child: Text(
            l10n.signalGroupRename,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _GroupContextAction.dissolve,
          child: Text(
            l10n.signalGroupDissolve,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuItem(
          value: _GroupContextAction.removeWithSignals,
          child: Text(
            l10n.signalGroupRemoveWithSignals,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    if (result == _GroupContextAction.rename) {
      await _showRenameDialog(context);
    } else if (result == _GroupContextAction.dissolve) {
      widget.onDissolve();
    } else if (result == _GroupContextAction.removeWithSignals) {
      widget.onRemoveWithSignals();
    }
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final l10n = L10N.of(context);
    final controller = TextEditingController(
      text: widget.entry.groupName ?? '',
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.signalGroupRenameDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.signalGroupRenameHint),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.trim().isNotEmpty) {
      widget.onRename(newName.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();
    final groupBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    final dropHighlight = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.25);

    final children = widget.entry.children;
    final childRows = widget.entry.collapsed
        ? const <Widget>[]
        : [
            for (var ci = 0; ci < children.length; ci++)
              if (children[ci].kind == SignalEntryKind.signal) ...[
                _GroupChildSignalRow(
                  key: ValueKey('child_${widget.index}_$ci'),
                  entry: children[ci],
                  colors: colors,
                  metrics: widget.metrics,
                  onRemoveFromGroup: () => widget.onRemoveChild(ci),
                ),
                if (widget.xorSignalRefs.contains(children[ci].signalRef ?? ''))
                  _XorDiffSpacer(key: ValueKey('xor_${widget.index}_$ci')),
              ],
          ];

    return ColoredBox(
      color: groupBg.withValues(alpha: 0.18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DragTarget<_DragData>(
            onWillAcceptWithDetails: (details) {
              // Reject drops from this group's own children (already inside).
              final droppedIdx = details.data;
              // droppedIdx is a top-level index so it's always valid to accept.
              setState(() => _isDragOver = true);
              return droppedIdx != widget.index;
            },
            onLeave: (_) => setState(() => _isDragOver = false),
            onAcceptWithDetails: (details) {
              setState(() => _isDragOver = false);
              widget.onSignalDropped(details.data);
            },
            builder: (context, candidateData, rejectedData) {
              return PlatformContextMenu(
                onContextMenu: (pos) => _showContextMenu(context, pos),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  color: _isDragOver ? dropHighlight : groupBg,
                  height: kGroupHeaderHeight,
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: widget.index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_handle,
                            size: 14,
                            color: colors.timeRulerTick,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SignalGroupHeader(
                          groupName: widget.entry.groupName ?? '',
                          signalCount: _countSignals(children),
                          collapsed: widget.entry.collapsed,
                          onToggleCollapsed: widget.onToggleCollapsed,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          ...childRows,
        ],
      ),
    );
  }
}

enum _GroupContextAction { rename, dissolve, removeWithSignals }

// ── Group child signal row ─────────────────────────────────────────────────────

class _GroupChildSignalRow extends StatelessWidget {
  const _GroupChildSignalRow({
    required this.entry,
    required this.colors,
    required this.onRemoveFromGroup,
    required this.metrics,
    super.key,
  });

  final SignalEntry entry;
  final WavecruxColorExtension colors;
  final VoidCallback onRemoveFromGroup;
  final MobileMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final signalColor = entry.argbColor != null
        ? Color(entry.argbColor!)
        : WavecruxColors.signalGreen;

    // Height comes from the shared model (the one clamp site) so grouped
    // signals stay aligned with the canvas and value column on touch, where
    // the stored laneHeight is clamped up to LaneMetrics.minLaneHeight.
    return SizedBox(
      height: LaneGeometry.heightForEntry(
        entry,
        LaneMetrics(minLaneHeight: metrics.minLaneHeight),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: signalColor,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              // Issue 15: same fix as the main _SignalRow body. Row's
              // default CrossAxisAlignment.center gives Expanded loose
              // vertical bounds, so the Text floats to the top of the
              // lane. SizedBox.expand forces Align to span the full lane
              // height and Alignment.centerLeft then vertically centers
              // the group-child signal name.
              child: SizedBox.expand(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    entry.displayName ?? entry.signalRef ?? '',
                    style: TextStyle(
                      fontFamily: WavecruxColors.monoFontFamily,
                      fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                      fontSize: 12,
                      color: signalColor,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: l10n.signalGroupRemoveFromGroup,
              child: Semantics(
                button: true,
                label: l10n.accessibilityRemoveSignal(
                  entry.displayName ?? entry.signalRef ?? '',
                ),
                child: GestureDetector(
                  onTap: onRemoveFromGroup,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.logout,
                      size: 11,
                      color: colors.timeRulerTick,
                    ),
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

// ── Lane resize grip painter ──────────────────────────────────────────────────

/// Paints two short horizontal lines centered in the lane resize strip so
/// touch users can see and target the drag affordance. Per
/// ARCHITECTURE.md §3.1.8.4 (visible affordances) and §3.1.8.8 (lane
/// vertical resize on touch).
///
/// The strip itself is positioned by the caller — this painter only draws
/// the grip lines centered within whatever size it receives.
class _LaneResizeGripPainter extends CustomPainter {
  const _LaneResizeGripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    // Two parallel lines, 2 dp apart, centered in the strip and spanning
    // 28 dp horizontally (roughly the size of a finger pad).
    const lineWidth = 28.0;
    const gap = 2.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas
      ..drawLine(
        Offset(cx - lineWidth / 2, cy - gap),
        Offset(cx + lineWidth / 2, cy - gap),
        paint,
      )
      ..drawLine(
        Offset(cx - lineWidth / 2, cy + gap),
        Offset(cx + lineWidth / 2, cy + gap),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant _LaneResizeGripPainter old) =>
      old.color != color;
}

// ── XOR diff spacer ───────────────────────────────────────────────────────────

/// Amber-tinted spacer row inserted below a differing signal in the signal
/// list panel so it stays vertically aligned with the XOR diff lane painted
/// on the waveform canvas.
///
/// Height matches [diffXorLaneHeight] exactly. The "⊕" label and amber tint
/// mirror what [WaveformCanvasRenderObject._paintXorDiffLane] draws.
class _XorDiffSpacer extends StatelessWidget {
  const _XorDiffSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: diffXorLaneHeight,
      color: diffXorLaneBackground,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 4),
      child: const Text(
        '⊕',
        style: TextStyle(fontSize: 10, color: diffXorLaneLabelColor),
      ),
    );
  }
}
