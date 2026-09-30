// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart' show announceCrux;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_picker_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/parameter_value_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_menu_anchor.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/platform_context_menu.dart';
import 'package:wavecrux/shared/widgets/signal_drag_chip.dart';

/// A leaf row in the signal hierarchy tree representing a single [Variable].
///
/// Tapping adds the signal to the waveform viewer. Ctrl/Cmd+click toggles
/// multi-selection; Shift+click selects the visible range from the last
/// interaction. Right-click opens a context menu with add and copy actions —
/// plus bulk-add and apply-decoder actions when a multi-selection is active.
/// HDL parameter leaves show their constant value inline (`= 32`).
///
/// For a screen reader the row is one node: a button named after the signal
/// (and its width when it is a vector), with its selected state. The keyboard
/// reaches it through `SignalTreeRowList`, where Enter does what a plain click
/// does.
class VariableTreeLeaf extends ConsumerWidget {
  const VariableTreeLeaf({
    required this.variable,
    this.indentLevel = 0,
    this.keyboardFocused = false,
    this.onTapped,
    this.onFocusRequested,
    super.key,
  });

  final Variable variable;

  /// Nesting depth — each level adds [_kIndent] pixels of left padding.
  final int indentLevel;

  /// Whether the tree has keyboard focus and this is its current row: the
  /// row draws a focus ring and reports focus to assistive technology.
  final bool keyboardFocused;

  /// Called when the row is clicked or tapped, before the click is handled,
  /// so the tree can make it the keyboard's current row.
  final VoidCallback? onTapped;

  /// Called when assistive technology asks to focus this row.
  final VoidCallback? onFocusRequested;

  static const double _kIndent = 16;
  static const double _kRowHeight = kSignalTreeRowHeight;

  /// What a plain click on [variable]'s row does: makes it the only selected
  /// row and adds it to the viewer. Announced, because the new waveform lane
  /// appears away from where keyboard focus is.
  static void addToViewer(
    BuildContext context,
    WidgetRef ref,
    Variable variable,
  ) {
    ref.read(selectedVariablesProvider.notifier).selectOnly(variable.fullPath);
    ref.read(signalGroupsProvider.notifier).addSignal(variable);
    announceCrux(context, L10N.of(context).a11ySignalAdded(variable.name));
  }

  /// The name a screen reader gives [variable]'s row: the signal name, plus
  /// its bit range when it is a vector — the same form the signal search
  /// results use.
  static String spokenName(Variable variable) {
    final width = variable.bitWidth;
    return [
      variable.name,
      if (width != null && width > 1) '[${width - 1}:0]',
    ].join(', ');
  }

  /// Whether this leaf is an HDL parameter whose constant value should be
  /// shown inline. `eventParameter` is excluded — events have no value to
  /// show. Note this only covers variables the dump *declares* as
  /// parameters; simulators that emit parameters as plain wires are
  /// indistinguishable from ordinary signals.
  bool get _isValuedParameter =>
      variable.varType == VarType.parameter ||
      variable.varType == VarType.realParameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isSelected = ref
        .watch(selectedVariablesProvider)
        .contains(variable.fullPath);

    final heatValue = ref.watch(
      switchingActivityProvider.select(
        (s) => s.heatmapValues[variable.fullPath],
      ),
    );

    final paramValue = _isValuedParameter
        ? ref
              .watch(
                parameterValueProvider(
                  variable.signalRef,
                  variable.bitWidth ?? 0,
                ),
              )
              .value
        : null;

    final bgColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.18)
        : heatValue != null
        ? _heatColor(heatValue)
        : Colors.transparent;

    final deviceClass = ref.watch(deviceClassProvider);
    final enableLongPress = shouldEnableLongPressContextMenu(
      deviceClass,
      theme.platform,
    );

    final row = Container(
      height: _kRowHeight,
      color: bgColor,
      foregroundDecoration: keyboardFocused
          ? BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      padding: EdgeInsets.only(left: _kIndent * (indentLevel + 1)),
      child: Row(
        children: [
          Icon(
            _iconForVarType(variable.varType),
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              variable.name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'JetBrainsMono',
                fontFamilyFallback: const [
                  'FiraCode',
                  'Courier New',
                  'monospace',
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (paramValue != null) _ParamValueBadge(value: paramValue),
          if (variable.bitWidth != null && variable.bitWidth! > 1)
            _BitWidthBadge(bitWidth: variable.bitWidth!),
          const SizedBox(width: 4),
        ],
      ),
    );

    final tappable = GestureDetector(
      onTap: () => _handleTap(context, ref),
      onSecondaryTapDown: (details) => showContextMenu(
        context,
        ref,
        signalTreePointerMenuAnchor(details.globalPosition),
      ),
      onLongPressStart: enableLongPress
          ? (details) => showContextMenu(
              context,
              ref,
              signalTreePointerMenuAnchor(details.globalPosition),
            )
          : null,
      // The row's own node carries the name; the icon, name text and badges
      // underneath would otherwise be read a second time.
      child: ExcludeSemantics(child: row),
    );

    // Wrap in a Draggable so the signal can be dropped onto a Stage
    // widget renderer (which is a DragTarget<String>). The dragged
    // payload is the signal ref — the same value that
    // SignalBindingPickerDialog returns. Affinity is horizontal so
    // vertical pans inside the signal tree's ListView remain
    // available for scrolling; the user pulls slightly sideways to
    // pick up a signal, then moves freely.
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: spokenName(variable),
      value: paramValue == null ? null : '= $paramValue',
      focusable: onFocusRequested != null ? true : null,
      focused: onFocusRequested != null ? keyboardFocused : null,
      onFocus: theme.platform == TargetPlatform.iOS ? null : onFocusRequested,
      child: Draggable<String>(
        data: variable.signalRef,
        affinity: Axis.horizontal,
        feedback: SignalDragChip(text: variable.fullPath),
        childWhenDragging: Opacity(opacity: 0.4, child: tappable),
        child: tappable,
      ),
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    onTapped?.call();
    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final selection = ref.read(selectedVariablesProvider.notifier);
    if (keyboard.isShiftPressed) {
      selection.selectRangeTo(variable.fullPath, _visiblePathsInOrder(ref));
    } else if (isCtrl) {
      selection.toggle(variable.fullPath);
    } else {
      // Plain tap adds the signal AND makes the tapped row the (single)
      // selection — the file-manager convention. The highlight gives the
      // click visible local feedback and makes the Shift+click range anchor
      // visible instead of implicit (it always ranged from the last-tapped
      // row; before this the anchor had no on-screen representation).
      addToViewer(context, ref, variable);
    }
  }

  /// The tree's current visible rows (as fullPaths), top to bottom — the
  /// coordinate system a Shift+click range resolves in. Mirrors exactly what
  /// the tree widgets render (expansion state + search filter).
  List<String> _visiblePathsInOrder(WidgetRef ref) {
    final scopes = ref.read(hierarchyProvider).value ?? const <Scope>[];
    return [
      for (final v in variablesInTreeOrder(
        scopes,
        expandedPaths: ref.read(expandedScopesProvider),
        searchQuery: ref.read(signalSearchQueryProvider),
      ))
        v.fullPath,
    ];
  }

  /// Opens the row's context menu at [position].
  ///
  /// A right-click or long-press anchors it at the pointer. The tree opens it
  /// from the keyboard (Shift+F10 or the Menu key) through this same method,
  /// anchored at the row, so every item is reachable without a pointer.
  Future<void> showContextMenu(
    BuildContext context,
    WidgetRef ref,
    RelativeRect position,
  ) async {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final selection = ref.read(selectedVariablesProvider);
    // Bulk actions target the selection, so they only make sense from a row
    // that is part of it (matching file-manager convention) and only when
    // there is more than one row selected (a single row is served by the
    // plain "Add to Viewer" item).
    final hasBulkSelection =
        selection.length >= 2 && selection.contains(variable.fullPath);
    final paramValue = _isValuedParameter
        ? ref
              .read(
                parameterValueProvider(
                  variable.signalRef,
                  variable.bitWidth ?? 0,
                ),
              )
              .value
        : null;

    final result = await showMenu<String>(
      context: context,
      position: position,
      items: [
        // Non-interactive header revealing the full parameter value — the
        // context-menu counterpart of the row badge's hover tooltip, per the
        // truncated-text reveal rule (ARCHITECTURE.md §3.1.8.14).
        if (paramValue != null)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              '${variable.name} = $paramValue',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'JetBrainsMono',
                fontFamilyFallback: const [
                  'FiraCode',
                  'Courier New',
                  'monospace',
                ],
              ),
            ),
          ),
        PopupMenuItem(value: 'add', child: Text(l10n.signalTreeAddToViewer)),
        if (hasBulkSelection) ...[
          PopupMenuItem(
            value: 'addSelected',
            child: Text(l10n.signalTreeAddSelected(selection.length)),
          ),
          PopupMenuItem(
            value: 'applyDecoder',
            child: Text(l10n.signalTreeApplyDecoderToSelection),
          ),
        ],
        PopupMenuItem(value: 'copy', child: Text(l10n.signalTreeCopyPath)),
      ],
    );
    if (result == null || !context.mounted) return;
    switch (result) {
      case 'add':
        ref.read(signalGroupsProvider.notifier).addSignal(variable);
        announceCrux(context, l10n.a11ySignalAdded(variable.name));
      case 'addSelected':
        _addSelectedToViewer(context, ref, selection);
      case 'applyDecoder':
        _applyDecoderToSelection(context, ref, selection);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: variable.fullPath));
    }
  }

  /// Adds every selected variable to the viewer, ordered by the tree's full
  /// (expansion-independent) order so the viewer rows land in the order the
  /// user sees in the tree — even for selections whose scope has since been
  /// collapsed.
  ///
  /// Idempotent: signals already displayed are skipped, so the common
  /// "plain-tap signal A (added), then Shift+click a range including A, then
  /// bulk-add" flow does not duplicate A. Deliberate duplicates (two rows of
  /// one signal with different formats) remain available via the single-add
  /// tap, which does not dedupe.
  void _addSelectedToViewer(
    BuildContext context,
    WidgetRef ref,
    Set<String> selection,
  ) {
    final scopes = ref.read(hierarchyProvider).value ?? const <Scope>[];
    final displayed = ref.read(signalGroupsProvider).displayedSignalRefs;
    // Selection carries fullPaths (row identity); the dedupe against the
    // canvas stays ref-based (data identity), so adding one alias of an
    // already-shown net is still skipped.
    final ordered = variablesInTreeOrder(scopes)
        .where(
          (v) =>
              selection.contains(v.fullPath) &&
              !displayed.contains(v.signalRef),
        )
        .toList();
    if (ordered.isEmpty) return;
    ref.read(signalGroupsProvider.notifier).addSignals(ordered);
    announceCrux(context, L10N.of(context).a11ySignalsAdded(ordered.length));
  }

  /// Opens the decoder picker scoped to the selected signals only: the
  /// config dialog's binding dropdowns and auto-bind heuristic operate on
  /// the selection subset, and confident name-heuristic matches are
  /// pre-filled on open ([DecoderPickerDialog.autoBindOnSelect]).
  void _applyDecoderToSelection(
    BuildContext context,
    WidgetRef ref,
    Set<String> selection,
  ) {
    // Resolve the EXACT rows the user selected (fullPath → Variable), then
    // key the dialog's map by signalRef as its contract requires. Resolving
    // through the ref-keyed map instead used to surface an arbitrary ALIAS
    // of each selected net (FST aliasing), so the config dialog displayed
    // names from scopes the user never clicked and auto-bind matched almost
    // nothing (the wb_streamer beta report).
    final byPath = ref.read(signalVariablesByPathProvider);
    final subset = <String, Variable>{
      for (final variable in selection.map((path) => byPath[path]).nonNulls)
        variable.signalRef: variable,
    };
    if (subset.isEmpty) return;
    unawaited(
      DecoderPickerDialog.show(
        context,
        signalMap: subset,
        // The leaf renders inside the per-tab UncontrolledProviderScope, so
        // this resolves the tab's container — the picker forwards it so the
        // config dialog writes to the tab's decoder notifier rather than the
        // root container's (dialog routes sit above the tab scope).
        tabContainer: ProviderScope.containerOf(context, listen: false),
        autoBindOnSelect: true,
      ),
    );
  }
}

/// Inline badge showing an HDL parameter's constant value (e.g. `= 32`).
///
/// Width-capped so a pathological value cannot squeeze the signal name out
/// of the row; the full value is revealed by hover tooltip (manual trigger,
/// per the gesture-arena rule) and by the context menu's header item.
class _ParamValueBadge extends StatelessWidget {
  const _ParamValueBadge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: value,
      triggerMode: TooltipTriggerMode.manual,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            '= $value',
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'JetBrainsMono',
              fontFamilyFallback: const [
                'FiraCode',
                'Courier New',
                'monospace',
              ],
              color: theme.colorScheme.primary.withValues(alpha: 0.75),
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Small badge showing the bit-width of a vector signal (e.g. `[7:0]`).
class _BitWidthBadge extends StatelessWidget {
  const _BitWidthBadge({required this.bitWidth});

  final int bitWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '[${bitWidth - 1}:0]',
      style: theme.textTheme.labelSmall?.copyWith(
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: const ['FiraCode', 'Courier New', 'monospace'],
        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
        fontSize: 10,
      ),
    );
  }
}

/// Maps a normalized heat value [0.0, 1.0] to a background tint color.
///
/// Cool (0.0) → blue tint; hot (1.0) → red tint.
Color _heatColor(double heat) {
  const cool = Color(0x2000A0FF);
  const hot = Color(0x30FF4040);
  return Color.lerp(cool, hot, heat.clamp(0.0, 1.0))!;
}

IconData _iconForVarType(VarType varType) {
  return switch (varType) {
    VarType.real ||
    VarType.realTime ||
    VarType.svShortReal ||
    VarType.realParameter => Icons.show_chart,
    VarType.integer ||
    VarType.svInt ||
    VarType.svShortInt ||
    VarType.svLongInt ||
    VarType.svByte => Icons.tag,
    VarType.event || VarType.eventParameter => Icons.flash_on,
    VarType.string => Icons.text_fields,
    VarType.parameter => Icons.settings,
    VarType.port => Icons.input,
    _ => Icons.graphic_eq,
  };
}
