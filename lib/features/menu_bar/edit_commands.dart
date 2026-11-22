// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The standard Edit-menu commands: Cut, Copy, Paste and Select All.
///
/// They are not [ShortcutAction]s on purpose. A `ShortcutAction` is a command
/// of the product that the user can rebind, search for in the command palette
/// and see in the toolbar overflow menu; these four are the operating
/// system's, fixed to their conventional keys, and only ever reach the user
/// through the macOS Edit menu (see [DesktopMenuBar]).
///
/// Why the macOS Edit menu needs them at all: with no menu item claiming
/// Cmd+C, a key press the framework leaves unhandled falls through AppKit's
/// responder chain to the alert sound, and nothing copies. A menu item that
/// claims the key equivalent turns that fall-through into a call to
/// [performEditCommand], which finds the copy for itself instead of relying on
/// the key having reached the right widget.
enum EditCommand {
  /// Cut the selection (Cmd+X).
  cut(LogicalKeyboardKey.keyX),

  /// Copy the selection (Cmd+C).
  copy(LogicalKeyboardKey.keyC),

  /// Paste the clipboard (Cmd+V).
  paste(LogicalKeyboardKey.keyV),

  /// Select everything in the focused text (Cmd+A).
  selectAll(LogicalKeyboardKey.keyA);

  const EditCommand(this.key);

  /// The key that, with Cmd, invokes the command.
  final LogicalKeyboardKey key;

  /// The Cmd+key chord the macOS menu shows and claims.
  SingleActivator get activator => SingleActivator(key, meta: true);

  /// The command's menu label.
  String label(L10N l10n) => switch (this) {
    EditCommand.cut => l10n.menuEditCut,
    EditCommand.copy => l10n.menuEditCopy,
    EditCommand.paste => l10n.menuEditPaste,
    EditCommand.selectAll => l10n.menuEditSelectAll,
  };

  /// The framework intent a focused text widget answers to.
  Intent get intent => switch (this) {
    EditCommand.cut => const CopySelectionTextIntent.cut(
      SelectionChangedCause.keyboard,
    ),
    EditCommand.copy => CopySelectionTextIntent.copy,
    EditCommand.paste => const PasteTextIntent(SelectionChangedCause.keyboard),
    EditCommand.selectAll => const SelectAllTextIntent(
      SelectionChangedCause.keyboard,
    ),
  };
}

/// What the focused widget offers the Edit commands.
///
/// Read from the focus rather than asked of the focused widget's actions: a
/// selectable area's copy action reports the key handled even when its
/// selection is empty, so asking it whether Copy would do anything always
/// answers yes. The nearest text widget above the primary focus decides:
/// an [EditableText] (a text field, or the read-only one under
/// [SelectableText]) or a [SelectableRegion] (a rendered note).
@immutable
class EditFocus {
  /// Creates a description of the focused text.
  const EditFocus({
    this.editable = false,
    this.readOnly = false,
    this.obscured = false,
    this.hasTextSelection = false,
    this.selectable = false,
  });

  /// Describes the widget that has primary focus now.
  factory EditFocus.current() {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return none;
    EditableTextState? editable;
    var selectable = false;
    bool visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        editable = element.state as EditableTextState;
        return false;
      }
      if (element.widget is SelectableRegion) {
        selectable = true;
        return false;
      }
      return true;
    }

    if (focus is Element && visit(focus)) focus.visitAncestorElements(visit);
    final field = editable;
    if (field != null) {
      final selection = field.textEditingValue.selection;
      return EditFocus(
        editable: true,
        readOnly: field.widget.readOnly,
        obscured: field.widget.obscureText,
        hasTextSelection: selection.isValid && !selection.isCollapsed,
      );
    }
    return selectable ? const EditFocus(selectable: true) : none;
  }

  /// Nothing text-like has focus.
  static const none = EditFocus();

  /// The focused editable text's controller, for watching its selection.
  static TextEditingController? currentController() {
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus
        ?.findAncestorStateOfType<EditableTextState>()
        ?.widget
        .controller;
  }

  /// Text that takes typing, or the read-only text of a [SelectableText].
  final bool editable;

  /// The [editable] text cannot be changed (Cut and Paste do nothing).
  final bool readOnly;

  /// The [editable] text is a password, which is never copied.
  final bool obscured;

  /// The [editable] text has a non-empty selection.
  final bool hasTextSelection;

  /// Focus is in a selectable area: a rendered note.
  final bool selectable;

  @override
  bool operator ==(Object other) =>
      other is EditFocus &&
      other.editable == editable &&
      other.readOnly == readOnly &&
      other.obscured == obscured &&
      other.hasTextSelection == hasTextSelection &&
      other.selectable == selectable;

  @override
  int get hashCode =>
      Object.hash(editable, readOnly, obscured, hasTextSelection, selectable);
}

/// What Copy copies.
enum CopySource {
  /// The selection in the focused text field, through its own copy action.
  focusedText,

  /// The text selected in a rendered note ([EditSelectionRegistry]).
  selectedText,

  /// The selected annotation: its time, signal and note.
  annotation,
}

/// Which Edit commands would do something, and what Copy would copy.
///
/// The rules a Mac app's Edit menu follows: Copy with a selection to copy,
/// Cut with a selection in text that can change, Paste into text that can
/// change, Select All in text that can be selected. A greyed item does not
/// claim its key, so the key reaches the alert sound, which is the system's
/// way of saying there is nothing to do.
@immutable
class EditAvailability {
  /// Creates an availability; see [EditAvailability.resolve].
  const EditAvailability({
    this.canCut = false,
    this.copySource,
    this.canPaste = false,
    this.canSelectAll = false,
  });

  /// Works out the commands from the focused text, whether a rendered note
  /// has a selection, and whether an annotation is selected.
  ///
  /// Copy's precedence: a selection in the focused text field, then a
  /// selection in a rendered note, then the selected annotation. A focused
  /// text field with nothing selected in it keeps Copy for itself and has
  /// nothing to copy, as in any Mac app: the annotation selected elsewhere is
  /// not what Copy in a text field means.
  factory EditAvailability.resolve({
    required EditFocus focus,
    required bool hasSelectedText,
    required bool annotationSelected,
  }) {
    final copySource = switch (focus) {
      EditFocus(editable: true, hasTextSelection: true, obscured: false) =>
        CopySource.focusedText,
      _ when hasSelectedText => CopySource.selectedText,
      EditFocus(editable: true) => null,
      _ when annotationSelected => CopySource.annotation,
      _ => null,
    };
    final changeable = focus.editable && !focus.readOnly;
    return EditAvailability(
      canCut: changeable && focus.hasTextSelection && !focus.obscured,
      copySource: copySource,
      canPaste: changeable,
      canSelectAll: focus.editable || focus.selectable,
    );
  }

  /// The availability now, from the primary focus and
  /// [EditSelectionRegistry].
  factory EditAvailability.current({required bool annotationSelected}) =>
      EditAvailability.resolve(
        focus: EditFocus.current(),
        hasSelectedText: EditSelectionRegistry.instance.text != null,
        annotationSelected: annotationSelected,
      );

  /// Cut would remove a selection from changeable text.
  final bool canCut;

  /// What Copy would copy, or null when there is nothing to copy.
  final CopySource? copySource;

  /// Paste would insert into changeable text.
  final bool canPaste;

  /// Select All would select text.
  final bool canSelectAll;

  /// Whether [command] would do something.
  bool isEnabled(EditCommand command) => switch (command) {
    EditCommand.cut => canCut,
    EditCommand.copy => copySource != null,
    EditCommand.paste => canPaste,
    EditCommand.selectAll => canSelectAll,
  };

  @override
  bool operator ==(Object other) =>
      other is EditAvailability &&
      other.canCut == canCut &&
      other.copySource == copySource &&
      other.canPaste == canPaste &&
      other.canSelectAll == canSelectAll;

  @override
  int get hashCode => Object.hash(canCut, copySource, canPaste, canSelectAll);
}

/// Runs [command] against whatever the user is working in, and reports
/// whether anything took it.
///
/// [annotationText] is what Copy puts on the clipboard for the selected
/// annotation (the active tab's), or null when none is selected. Copy takes,
/// in order: the selection in the focused text field; the selection in a
/// rendered note ([EditSelectionRegistry]), which is copied even when nothing
/// in the focus chain answers to it; the selected annotation. See
/// [EditAvailability.resolve].
///
/// Cut, Paste and Select All are sent to the focused text widget, which is
/// what the key would have done had it reached it.
///
/// A command that would do nothing ([EditAvailability.isEnabled] false) is not
/// sent at all, so an empty selection's copy action, which reports success
/// without copying, cannot stand in for the annotation. Never throws and
/// never beeps.
bool performEditCommand(EditCommand command, {String? annotationText}) {
  final availability = EditAvailability.current(
    annotationSelected: annotationText != null,
  );
  if (!availability.isEnabled(command)) return false;
  if (command == EditCommand.copy) {
    switch (availability.copySource) {
      case CopySource.selectedText:
        final text = EditSelectionRegistry.instance.text;
        if (text == null) return false;
        unawaited(Clipboard.setData(ClipboardData(text: text)));
        return true;
      case CopySource.annotation:
        unawaited(Clipboard.setData(ClipboardData(text: annotationText!)));
        return true;
      case CopySource.focusedText:
      case null:
        break;
    }
  }
  return _invokeAtFocus(command.intent);
}

bool _invokeAtFocus(Intent intent) {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  final action = Actions.maybeFind<Intent>(focus, intent: intent);
  if (action == null) return false;
  final (handled, _) = Actions.of(focus).invokeActionIfEnabled(action, intent);
  return handled;
}

/// Watches what decides [EditAvailability]: the primary focus, the selection
/// in a focused text field, and [EditSelectionRegistry].
///
/// Notifies only when the focus description or whether a note has a selection
/// changes, so a listener that rebuilds the menu does so when an item would
/// enable or grey, not on every keystroke or caret move. A change reported
/// while a frame is being built is passed on after the frame.
class EditAvailabilityWatcher extends ChangeNotifier {
  /// Starts watching.
  EditAvailabilityWatcher() {
    FocusManager.instance.addListener(_focusChanged);
    EditSelectionRegistry.instance.addListener(_schedule);
    _focusChanged();
  }

  EditFocus _focus = EditFocus.none;
  bool _hasSelectedText = false;
  TextEditingController? _controller;
  bool _pending = false;
  bool _disposed = false;

  /// The availability now, with [annotationSelected] from the caller.
  EditAvailability availability({required bool annotationSelected}) =>
      EditAvailability.resolve(
        focus: _focus,
        hasSelectedText: _hasSelectedText,
        annotationSelected: annotationSelected,
      );

  void _focusChanged() {
    final controller = EditFocus.currentController();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_schedule);
      _controller = controller?..addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_pending) return;
      _pending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        _update();
      });
      return;
    }
    _update();
  }

  void _update() {
    if (_disposed) return;
    final focus = EditFocus.current();
    final hasSelectedText = EditSelectionRegistry.instance.text != null;
    if (focus == _focus && hasSelectedText == _hasSelectedText) return;
    _focus = focus;
    _hasSelectedText = hasSelectedText;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    FocusManager.instance.removeListener(_focusChanged);
    EditSelectionRegistry.instance.removeListener(_schedule);
    _controller?.removeListener(_schedule);
    _controller = null;
    super.dispose();
  }
}

/// Copies the selected annotation, bound to Ctrl+C on Windows and Linux.
///
/// The in-window menu there carries no Edit commands, so nothing outside the
/// framework catches a Ctrl+C that no focused widget took. [CopyAnnotationAction]
/// answers it, and is enabled only when Copy would copy a rendered note's
/// selection or the selected annotation: with a text field focused it stands
/// aside, and the key goes on to the field's own copy.
class CopyAnnotationIntent extends Intent {
  /// Creates the intent.
  const CopyAnnotationIntent();
}

/// See [CopyAnnotationIntent].
class CopyAnnotationAction extends Action<CopyAnnotationIntent> {
  /// Creates the action; [annotationText] reads the selected annotation's
  /// clipboard text, or null when none is selected.
  CopyAnnotationAction(this.annotationText);

  /// The selected annotation's clipboard text, read when the key is pressed.
  final String? Function() annotationText;

  @override
  bool isEnabled(CopyAnnotationIntent intent) =>
      switch (EditAvailability.current(
        annotationSelected: annotationText() != null,
      ).copySource) {
        CopySource.selectedText || CopySource.annotation => true,
        CopySource.focusedText || null => false,
      };

  @override
  Object? invoke(CopyAnnotationIntent intent) => performEditCommand(
    EditCommand.copy,
    annotationText: annotationText(),
  );
}

/// The text currently selected in the selectable areas that report to it.
///
/// A [SelectionArea] reports its selection through `onSelectionChanged`;
/// registering it here lets the Edit menu's Copy reach it without the focus
/// chain. An area reports `null` when its selection clears, which the
/// framework does when the area loses focus, so an entry is never older than
/// the highlight the user sees. Listeners hear every change, so the Edit menu
/// can enable Copy when a selection appears.
class EditSelectionRegistry extends ChangeNotifier {
  EditSelectionRegistry._();

  /// The registry the app uses.
  static final EditSelectionRegistry instance = EditSelectionRegistry._();

  // Insertion order is report order, so the latest reporter is the last.
  final Map<Object, String> _byOwner = <Object, String>{};

  /// Records that [owner]'s selection is now [text]; null or empty clears it.
  void report(Object owner, String? text) {
    if (text == null || text.isEmpty) {
      forget(owner);
      return;
    }
    if (_byOwner.keys.lastOrNull == owner && _byOwner[owner] == text) return;
    _byOwner
      ..remove(owner)
      ..[owner] = text;
    notifyListeners();
  }

  /// Forgets [owner], for when its area is disposed.
  void forget(Object owner) {
    if (_byOwner.remove(owner) != null) notifyListeners();
  }

  /// The most recently reported selection, or null when none is selected.
  String? get text => _byOwner.isEmpty ? null : _byOwner.values.last;

  /// Clears every entry, for tests.
  @visibleForTesting
  void debugReset() {
    if (_byOwner.isEmpty) return;
    _byOwner.clear();
    notifyListeners();
  }
}
