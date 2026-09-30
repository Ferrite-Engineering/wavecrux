// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/core/shortcuts/shortcut_conflicts.dart';

/// A [ShortcutManager] that passes all key events through when a text-input
/// widget ([EditableText]) currently holds focus.
///
/// Without this guard, single-character shortcuts (WASD, A–Z keys) would
/// swallow keystrokes inside dialogs or inline text fields.
class _TextAwareShortcutManager extends ShortcutManager {
  _TextAwareShortcutManager({
    required super.shortcuts,
  });

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    // Only suppress bare-letter keys (WASD, QEZ, arrow keys) while text input
    // has focus. Modifier combos like Cmd+Shift+P must always fire so that
    // shortcuts like the command palette work from any focus state.
    if (_isTextInputFocused() && _isBareLetter()) {
      return KeyEventResult.ignored;
    }
    if (_activatesFocusedControl(event)) return KeyEventResult.ignored;
    return super.handleKeypress(context, event);
  }

  /// Returns true for a bare Space or Enter while the focused widget is a
  /// control that Space and Enter activate — a button, a checkbox, a tile.
  ///
  /// Space is bound to Stage playback, and this manager sits above the
  /// framework's own `Space → ActivateIntent` shortcut. The viewer's action
  /// for every shortcut is always enabled, so it consumed Space on a focused
  /// toolbar or start-screen button even when playback had nothing to do,
  /// and only Enter activated buttons. Controls that accept activation own
  /// those two keys; everywhere else (the waveform canvas) Space still plays.
  static bool _activatesFocusedControl(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    if (!_isBareLetter() || HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final action = Actions.maybeFind<ActivateIntent>(focusContext);
    return action != null && action.isEnabled(const ActivateIntent());
  }

  /// Returns true when the current key event has no primary modifier keys
  /// (Ctrl, Cmd/Meta, Alt). Shift alone is not counted — bare Shift+key
  /// combos like Shift+Escape should still be blocked inside text fields.
  static bool _isBareLetter() =>
      !HardwareKeyboard.instance.isControlPressed &&
      !HardwareKeyboard.instance.isMetaPressed &&
      !HardwareKeyboard.instance.isAltPressed;

  /// Returns true when a text-input widget is anywhere in the focus ancestry.
  ///
  /// `EditableText` attaches its `FocusNode` to an inner `Focus` child widget,
  /// so `primaryFocus.context.widget` is never `EditableText` itself.
  /// Walking up the ancestor elements from that `Focus` finds it reliably.
  static bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    var found = false;
    focusContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}

/// Wraps [child] with Flutter's [Shortcuts] and [Actions] machinery, using
/// bindings from [ShortcutBindingsNotifier].
///
/// Pass [handlers] for globally-scoped actions (e.g. [ShortcutAction.toggleTheme]
/// in [WaveCruxApp]).  Context-sensitive actions (zoom, pan) should register their
/// own [Actions] widget lower in the tree — unhandled intents propagate up.
class ShortcutManagerWidget extends ConsumerWidget {
  const ShortcutManagerWidget({
    required this.child,
    this.handlers = const {},
    super.key,
  });

  final Widget child;

  /// Callbacks invoked when a matched shortcut fires.
  /// Actions not present here propagate to [Actions] widgets registered below.
  final Map<ShortcutAction, VoidCallback> handlers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(shortcutBindingsProvider);
    // Resolve collisions deterministically: when two actions share a chord, the
    // user's customized binding wins over the action that holds it by default
    // (and shadowed losers are dropped), so a fresh remap actually fires.
    // Previously the map literal below let whichever action came later in
    // `bindings` iteration order (i.e. ShortcutAction enum declaration order)
    // silently win.
    final effective = resolveShortcutConflicts(bindings).effectiveBindings;
    return Shortcuts.manager(
      manager: _TextAwareShortcutManager(
        shortcuts: {
          for (final e in effective.entries)
            // Bare-key navigation + marker chords are owned by the viewer's
            // global HardwareKeyboard handler (focus-independent + marker-chord
            // exclusive); excluding them here prevents a double dispatch, since
            // a HardwareKeyboard handler returning true does not suppress this
            // focus Shortcuts layer. See [kGlobalKeyHandledActions].
            if (!kGlobalKeyHandledActions.contains(e.key))
              e.value: ShortcutActionIntent(e.key),
        },
      ),
      child: Actions(
        actions: <Type, Action<Intent>>{
          ShortcutActionIntent: _GlobalHandlerAction(handlers),
        },
        child: child,
      ),
    );
  }
}

/// Dispatches a [ShortcutActionIntent] to its globally-registered callback —
/// but ONLY for actions that actually have a handler in [_handlers].
///
/// This conditional enablement is load-bearing on macOS. The native
/// [PlatformMenuBar] registers each menu action's chord as an AppKit
/// key-equivalent, but AppKit walks the responder chain — i.e.
/// `FlutterView.performKeyEquivalent:` — *before* the main menu. If this
/// global [Actions] entry handled (and therefore consumed) *every*
/// [ShortcutActionIntent], an action that has no global handler and whose
/// per-screen [Actions] handler is not in the current focus chain (e.g. focus
/// is on toolbar chrome rather than the canvas) would be silently swallowed
/// here: Flutter reports the key handled, AppKit stops, and the native menu
/// key-equivalent never fires. The chord does nothing.
///
/// By disabling for unhandled actions, the intent falls through: a lower
/// [Actions] (e.g. `ViewerScreen`) catches it when focused, and otherwise
/// Flutter returns "not handled" so the native macOS menu fires the
/// key-equivalent as designed. Windows/Linux use an in-window menu that binds
/// no keys, so the framework path is unaffected there.
class _GlobalHandlerAction extends Action<ShortcutActionIntent> {
  _GlobalHandlerAction(this._handlers);

  final Map<ShortcutAction, VoidCallback> _handlers;

  @override
  bool isEnabled(ShortcutActionIntent intent) =>
      _handlers.containsKey(intent.action);

  @override
  Object? invoke(ShortcutActionIntent intent) {
    _handlers[intent.action]?.call();
    return null;
  }
}
