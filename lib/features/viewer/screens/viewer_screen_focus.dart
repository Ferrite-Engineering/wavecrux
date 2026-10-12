// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Focus predicates for the viewer's global key handler (`_onKeyEvent`). That
// handler is registered on HardwareKeyboard, below focus, so it has to ask
// where focus is before it acts on a key: a text field owns its letters, an
// open menu owns its Escape.

part of 'viewer_screen.dart';

/// Whether a text-input widget ([EditableText]) currently holds focus, in
/// which case bare-key shortcuts must not fire (the user is typing). Mirrors
/// the guard in `_TextAwareShortcutManager` for the focus Shortcuts layer.
bool _isTextInputFocused() {
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

/// Whether the focused widget sits inside a menu that will dismiss on
/// Escape: its nearest [DismissIntent] binding is an enabled
/// [DismissMenuAction], which `MenuAnchor` installs around its open menu
/// panel (and `MenuBar` around the bar).
///
/// A `MenuAnchor` menu is an overlay entry, not a route, so the handler's
/// `ModalRoute.isCurrent` check does not see it. Walks the ancestors by hand
/// rather than through `Actions.maybeFind`, which would register a dependency
/// on the focused element.
bool _isFocusInOpenMenu() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  var inMenu = false;
  focusContext.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is! Actions) return true;
    final dismiss = widget.actions[DismissIntent];
    if (dismiss == null) return true;
    inMenu =
        dismiss is DismissMenuAction &&
        dismiss.isEnabled(const DismissIntent());
    return false;
  });
  return inMenu;
}
