// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/utils/focus_opening_menu.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_navigation.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/widgets/scope_tree_node.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_menu_anchor.dart';
import 'package:wavecrux/features/signal_tree/widgets/variable_tree_leaf.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The signal tree's rows, as one keyboard control.
///
/// The whole tree is a single Tab stop. Up and Down move between visible
/// rows, Home and End go to the first and last, Page Up and Page Down move by
/// a screenful. Right expands a collapsed scope or moves into an expanded one;
/// Left collapses an expanded scope or moves to the row's parent. Enter and
/// Space do what a click does: toggle a scope, or add a signal to the viewer.
///
/// What a pointer does with a modifier or the right button, the keyboard does
/// too. Shift+Up and Shift+Down extend a range of selected signals, as
/// Shift+click does; Ctrl+Space toggles one, as Ctrl+click does. Shift+F10 or
/// the Menu key opens the current row's context menu over the row, focus
/// starts on its first item, and closing it returns focus to the row — so Add
/// All in Scope, Copy Signal Path and the bulk actions need no pointer.
///
/// **One focus node, not one per row.** The list is lazy (see
/// `signalTreeRowsInOrder`): a row scrolled out of the build window is
/// disposed, and a focus node that lived in it would take keyboard focus down
/// with it. So the tree holds the only focus node, and the row the keyboard
/// is on is remembered here as its hierarchy object and index. The row
/// reports focus to assistive technology through its own semantics node, which
/// is what the desktop accessibility bridges announce, so a screen reader
/// hears each row as focus moves exactly as it would with a focus node per
/// row. Tab into the tree returns to the row the keyboard or pointer was last
/// on, so the Tab stop follows the user.
///
/// A pointer click moves the current row but does not take keyboard focus:
/// arrow keys stay with the waveform for someone who clicks signals in and
/// then pans.
///
/// The tree's key handler sits below the app's shortcut layer in focus order,
/// so while the tree has focus its arrows and Home/End win over the viewer's
/// pan and jump bindings. Other modified keys are left alone and still reach
/// the app (Ctrl+Shift+Arrow resizes the dock).
class SignalTreeRowList extends ConsumerStatefulWidget {
  const SignalTreeRowList({
    required this.rows,
    required this.scrollController,
    super.key,
  });

  /// The visible rows, top to bottom. Must not be empty.
  final List<SignalTreeRow> rows;

  /// The tree's scroll controller, owned by the panel so the offset persists
  /// in the session.
  final ScrollController scrollController;

  @override
  ConsumerState<SignalTreeRowList> createState() => _SignalTreeRowListState();
}

class _SignalTreeRowListState extends ConsumerState<SignalTreeRowList> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Signal tree');

  /// The hierarchy object of the row the keyboard is on.
  Object? _activeItem;

  /// Where [_activeItem] was last found in [SignalTreeRowList.rows].
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _resolveActive();
  }

  @override
  void didUpdateWidget(SignalTreeRowList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rows, widget.rows)) _resolveActive();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _resolveActive() {
    final rows = widget.rows;
    if (rows.isEmpty) return;
    _activeIndex = resolveSignalTreeActiveIndex(
      rows,
      item: _activeItem,
      previousIndex: _activeIndex,
    );
    _activeItem = signalTreeRowItem(rows[_activeIndex]);
  }

  void _setActive(int index) {
    final rows = widget.rows;
    if (rows.isEmpty) return;
    final target = index.clamp(0, rows.length - 1);
    setState(() {
      _activeIndex = target;
      _activeItem = signalTreeRowItem(rows[target]);
    });
  }

  void _moveTo(int index) {
    _setActive(index);
    _reveal(_activeIndex);
  }

  /// Scrolls the least distance that brings row [index] fully into view.
  ///
  /// Jumps rather than animates, so a held arrow key keeps up and the row is
  /// built — and announced — in the very next frame.
  void _reveal(int index, {bool retry = true}) {
    final controller = widget.scrollController;
    if (!controller.hasClients) return;
    final position = controller.position;
    if (!position.hasViewportDimension) return;
    final viewport = position.viewportDimension;
    final top = index * kSignalTreeRowHeight;
    final bottom = top + kSignalTreeRowHeight;
    final double target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + viewport) {
      target = bottom - viewport;
    } else {
      return;
    }
    controller.jumpTo(
      math.min(target, math.max(position.maxScrollExtent, 0)),
    );
    // The extent can lag a row count that changed this frame; try once more
    // after layout has caught up.
    if (retry && target > position.maxScrollExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(index, retry: false);
      });
    }
  }

  void _onFocusChange(bool focused) {
    setState(() {});
    if (focused) _reveal(_activeIndex);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final rows = widget.rows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final index = _activeIndex.clamp(0, rows.length - 1);
    final shift = keyboard.isShiftPressed;
    final primary = keyboard.isControlPressed || keyboard.isMetaPressed;
    final alt = keyboard.isAltPressed;

    if (!primary && !alt) {
      if ((shift && key == LogicalKeyboardKey.f10) ||
          (!shift && key == LogicalKeyboardKey.contextMenu)) {
        if (event is KeyDownEvent) _openContextMenu(rows, index);
        return KeyEventResult.handled;
      }
      if (shift &&
          (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowUp)) {
        _extendSelection(
          rows,
          index,
          key == LogicalKeyboardKey.arrowDown ? index + 1 : index - 1,
        );
        return KeyEventResult.handled;
      }
    }
    if (primary && !shift && !alt && key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) _toggleSelection(rows[index]);
      return KeyEventResult.handled;
    }
    if (primary || alt || shift) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveTo(index + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveTo(index - 1);
    } else if (key == LogicalKeyboardKey.home) {
      _moveTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _moveTo(rows.length - 1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _moveTo(index + _pageRows);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _moveTo(index - _pageRows);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _expandOrEnter(rows, index);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _collapseOrLeave(rows, index);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      // A held Enter must not add the same signal once per auto-repeat.
      if (event is KeyDownEvent) _activate(rows[index]);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  int get _pageRows {
    final controller = widget.scrollController;
    if (!controller.hasClients) return 1;
    final rowsInView =
        controller.position.viewportDimension ~/ kSignalTreeRowHeight;
    return math.max(1, rowsInView - 1);
  }

  void _expandOrEnter(List<SignalTreeRow> rows, int index) {
    final row = rows[index];
    if (row is! ScopeRow || !ScopeTreeNode.hasContent(row.scope)) return;
    if (!ref.read(expandedScopesProvider).contains(row.scope.path)) {
      ScopeTreeNode.toggle(ref, row.scope);
      return;
    }
    final child = signalTreeFirstChildIndex(rows, index);
    if (child != null) _moveTo(child);
  }

  void _collapseOrLeave(List<SignalTreeRow> rows, int index) {
    final row = rows[index];
    if (row is ScopeRow &&
        ScopeTreeNode.hasContent(row.scope) &&
        ref.read(expandedScopesProvider).contains(row.scope.path)) {
      ScopeTreeNode.toggle(ref, row.scope);
      return;
    }
    final parent = signalTreeParentIndex(rows, index);
    if (parent != null) _moveTo(parent);
  }

  /// Moves to [target] and selects the signals between the range's anchor
  /// and it — Shift+click from the keyboard. A range started on a row that is
  /// not selected is anchored there; a scope row moves without changing the
  /// selection, since only signals are selectable.
  void _extendSelection(List<SignalTreeRow> rows, int index, int target) {
    final to = target.clamp(0, rows.length - 1);
    final selection = ref.read(selectedVariablesProvider.notifier);
    final from = rows[index];
    if (from is VariableRow &&
        !ref.read(selectedVariablesProvider).contains(from.variable.fullPath)) {
      selection.selectOnly(from.variable.fullPath);
    }
    final row = rows[to];
    if (row is VariableRow) {
      selection.selectRangeTo(row.variable.fullPath, [
        for (final r in rows)
          if (r is VariableRow) r.variable.fullPath,
      ]);
    }
    _moveTo(to);
  }

  /// Toggles the current signal in the selection without adding it to the
  /// viewer — Ctrl+click from the keyboard.
  void _toggleSelection(SignalTreeRow row) {
    if (row is! VariableRow) return;
    ref.read(selectedVariablesProvider.notifier).toggle(row.variable.fullPath);
  }

  /// Opens the context menu of the row at [index] over that row, the way a
  /// right-click opens it at the pointer.
  ///
  /// The menu route takes focus but none of its items does, so a screen
  /// reader would hear nothing until an arrow key: focus moves to the first
  /// item once the menu is built. When the menu closes, the route hands focus
  /// back to the tree, which is still on the same row.
  void _openContextMenu(List<SignalTreeRow> rows, int index) {
    _reveal(index);
    final list = context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (list is! RenderBox || overlay is! RenderBox) return;
    final anchor = signalTreeRowMenuAnchor(
      list: list,
      overlay: overlay,
      index: index,
      scrollOffset: widget.scrollController.hasClients
          ? widget.scrollController.offset
          : 0,
    );
    if (anchor == null) return;
    final shown = switch (rows[index]) {
      ScopeRow(:final scope) => ScopeTreeNode(
        scope: scope,
      ).showContextMenu(context, ref, anchor),
      VariableRow(:final variable) => VariableTreeLeaf(
        variable: variable,
      ).showContextMenu(context, ref, anchor),
    };
    unawaited(shown);
    focusFirstItemOfOpeningMenu();
  }

  void _activate(SignalTreeRow row) {
    switch (row) {
      case ScopeRow(:final scope):
        ScopeTreeNode.toggle(ref, scope);
      case VariableRow(:final variable):
        VariableTreeLeaf.addToViewer(context, ref, variable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final focused = _focusNode.hasFocus;
    final active = _activeIndex;
    final isDesktop = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };

    final list = ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      // Fixed extent lets the list compute scroll geometry without building
      // any off-screen rows.
      itemExtent: kSignalTreeRowHeight,
      itemCount: rows.length,
      itemBuilder: (_, i) => switch (rows[i]) {
        // Instance-identity keys: gate-level FSTs have sibling variables
        // sharing a signalRef and even a full name (escaped identifiers
        // dumped twice), and the same can hold for scopes — no value key is
        // sibling-unique.
        ScopeRow(:final scope, :final indentLevel) => ScopeTreeNode(
          key: ObjectKey(scope),
          scope: scope,
          indentLevel: indentLevel,
          keyboardFocused: focused && i == active,
          onTapped: () => _setActive(i),
          onFocusRequested: () => _focusRow(i),
        ),
        VariableRow(:final variable, :final indentLevel) => VariableTreeLeaf(
          key: ObjectKey(variable),
          variable: variable,
          indentLevel: indentLevel,
          keyboardFocused: focused && i == active,
          onTapped: () => _setActive(i),
          onFocusRequested: () => _focusRow(i),
        ),
      },
    );

    return Semantics(
      // Spoken once, when focus enters the tree: the rows are buttons, and
      // nothing else says the arrow keys move between them. Touch screen
      // readers navigate by swiping, so the instructions would mislead there.
      container: isDesktop,
      explicitChildNodes: true,
      label: isDesktop ? L10N.of(context).signalTreeKeyboardHint : null,
      child: Focus(
        focusNode: _focusNode,
        // The focused row announces itself; a node for the whole list would
        // be a second, nameless focus.
        includeSemantics: false,
        onFocusChange: _onFocusChange,
        onKeyEvent: _onKeyEvent,
        child: list,
      ),
    );
  }

  void _focusRow(int index) {
    _setActive(index);
    _focusNode.requestFocus();
  }
}
