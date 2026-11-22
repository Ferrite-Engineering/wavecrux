// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
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

/// Runs [command] against whatever the user is working in, and reports
/// whether anything took it.
///
/// First the focused widget: the intent is sent where the focus is, which is
/// what a Cmd+C that reached the framework would have done, so a text field, a
/// selectable note and any widget that handles the framework's text intents
/// all answer as they do to the key.
///
/// Then, for Copy only, the selection a selectable area last reported
/// ([EditSelectionRegistry]). A selection that is on screen is copied even
/// when nothing in the focus chain answers, which is the case the beep was.
///
/// Never throws and never beeps: a command nothing can take is a no-op.
bool performEditCommand(EditCommand command) {
  final intent = command.intent;
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus != null) {
    final action = Actions.maybeFind<Intent>(focus, intent: intent);
    if (action != null) {
      final (handled, _) = Actions.of(
        focus,
      ).invokeActionIfEnabled(action, intent);
      if (handled) return true;
    }
  }
  if (command == EditCommand.copy) {
    final text = EditSelectionRegistry.instance.text;
    if (text != null) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
      return true;
    }
  }
  return false;
}

/// The text currently selected in the selectable areas that report to it.
///
/// A [SelectionArea] reports its selection through `onSelectionChanged`;
/// registering it here lets the Edit menu's Copy reach it without the focus
/// chain. An area reports `null` when its selection clears, which the
/// framework does when the area loses focus, so an entry is never older than
/// the highlight the user sees.
class EditSelectionRegistry {
  EditSelectionRegistry._();

  /// The registry the app uses.
  static final EditSelectionRegistry instance = EditSelectionRegistry._();

  // Insertion order is report order, so the latest reporter is the last.
  final Map<Object, String> _byOwner = <Object, String>{};

  /// Records that [owner]'s selection is now [text]; null or empty clears it.
  void report(Object owner, String? text) {
    if (text == null || text.isEmpty) {
      _byOwner.remove(owner);
      return;
    }
    _byOwner
      ..remove(owner)
      ..[owner] = text;
  }

  /// Forgets [owner], for when its area is disposed.
  void forget(Object owner) => _byOwner.remove(owner);

  /// The most recently reported selection, or null when none is selected.
  String? get text => _byOwner.isEmpty ? null : _byOwner.values.last;

  /// Clears every entry, for tests.
  @visibleForTesting
  void debugReset() => _byOwner.clear();
}
