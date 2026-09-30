// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Puts keyboard focus on the first item of the popup menu that is opening.
///
/// Call it right after `showMenu`. Flutter's popup route takes focus on its
/// own scope and leaves every item unfocused, so a screen reader announces
/// nothing until an arrow key moves into the menu. The route claims focus
/// from a microtask its first build schedules, so the check runs after the
/// frame that builds the menu and after that microtask, and tries once more a
/// frame later. Does nothing if the focus is not in a popup route by then.
///
/// When the menu closes, the route hands focus back to the control that had
/// it, so callers need no restore of their own.
void focusFirstItemOfOpeningMenu({int attempts = 2}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    scheduleMicrotask(() {
      final menu = FocusManager.instance.primaryFocus;
      final menuContext = menu?.context;
      if (menu is FocusScopeNode &&
          menuContext != null &&
          menuContext.mounted &&
          ModalRoute.of(menuContext) is PopupRoute) {
        menu.nextFocus();
      } else if (attempts > 1) {
        focusFirstItemOfOpeningMenu(attempts: attempts - 1);
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    });
  });
}
