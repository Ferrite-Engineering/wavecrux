// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';

/// Shows a modal bottom sheet over the tab [ActiveTab.navigatorFor] resolves,
/// or over the window (as `showModalBottomSheet` does) when there is none.
///
/// A sheet that reads a tab's providers is built on the tab's own navigator,
/// under the tab's one scope, instead of under a second scope over the tab's
/// container. It covers the tab's area, belongs to its tab, and closes with it.
Future<T?> showTabModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
}) {
  final navigator = ActiveTab.navigatorFor(context);
  if (navigator == null) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      builder: builder,
    );
  }
  var inNavigator = false;
  context.visitAncestorElements((element) {
    if (identical(element, navigator.context)) {
      inNavigator = true;
      return false;
    }
    return true;
  });
  return navigator.push<T>(
    ModalBottomSheetRoute<T>(
      builder: builder,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      capturedThemes: inNavigator
          ? InheritedTheme.capture(from: context, to: navigator.context)
          : null,
    ),
  );
}

/// Each tab's nested navigator, one instance for the life of the process.
///
/// Handed to `PaneHost.tabNavigators` by `WaveCruxPaneHost`, and registered as
/// a workspace scope reconciler at bootstrap BEFORE the tab and pane container
/// managers: a closing tab's dialogs are still mounted under that tab's
/// container until the next frame, so they are popped (their futures complete
/// with null) before the container manager disposes it.
final tabNavigatorsProvider = Provider<crux.CruxTabNavigators>(
  (_) => crux.CruxTabNavigators(),
  name: 'tabNavigatorsProvider',
);

/// Where a dialog that reads a tab's providers is shown.
///
/// `showDialog` mounts a dialog on the root navigator, outside every tab's
/// `UncontrolledProviderScope`, so a dialog that reads the tab's waveform,
/// cursors, signal groups, ... from there sees the root container, where no
/// file is loaded. WaveCrux used to fix that by wrapping the dialog in a
/// second scope over the tab's container, which let Riverpod flush that
/// container's rebuilds from two scopes in one frame and mark the tab's own
/// widgets dirty in the middle of a build.
///
/// Each tab's content is instead built on its own nested navigator
/// (`PaneHost.tabNavigators`), and a dialog that needs the tab is pushed on
/// it:
///
/// ```dart
/// showCruxDialog<void>(
///   context: context,
///   navigator: ActiveTab.navigatorFor(context),
///   builder: (_) => const MyDialog(),
/// );
/// ```
///
/// The dialog is then built under the tab's one scope. It covers the tab's
/// area (one pane in a split), not the window, and belongs to the tab:
/// switching tabs hides it with its tab, and closing the tab closes it (its
/// future completes with null).
abstract final class ActiveTab {
  /// The navigator of the tab [callerContext] is inside, else the active
  /// tab's navigator, else null.
  ///
  /// Null when no tab is active (the empty workspace), the active tab's
  /// content has not been built, or no workspace is mounted above
  /// [callerContext]; `showCruxDialog` then uses the root navigator, as
  /// before, and the dialog sees the root container.
  ///
  /// [callerContext] may be inside a tab (a panel, or a dialog already on the
  /// tab's navigator, so a dialog opened from a dialog lands on the same tab)
  /// or outside every tab (the menu bar, the palette, the screen itself).
  static NavigatorState? navigatorFor(BuildContext callerContext) =>
      _resolve(callerContext)?.navigator;

  /// [surface]'s `ModalGuard` key for the tab [navigatorFor] resolves, or
  /// [surface] itself when there is none.
  ///
  /// A dialog that belongs to a tab stays open, hidden, while another tab is
  /// active. One process-wide key would then swallow the same command in the
  /// other tab with nothing on screen to explain it, so each tab guards its
  /// own copy.
  static String guardKey(BuildContext callerContext, String surface) {
    final tab = _resolve(callerContext)?.tab;
    return tab == null ? surface : '$surface@${tab.value}';
  }

  static ({crux.TabId tab, NavigatorState navigator})? _resolve(
    BuildContext callerContext,
  ) {
    try {
      final container = ProviderScope.containerOf(callerContext, listen: false);
      final inTab = crux.cruxTabNavigatorOf(callerContext);
      if (inTab != null) {
        return (tab: container.read(tabIdProvider), navigator: inTab);
      }
      final active = container.read(activeTabIdProvider);
      if (!container.read(tabListProvider).any((tab) => tab.id == active)) {
        return null;
      }
      final navigator = container
          .read(tabNavigatorsProvider)
          .navigatorFor(active);
      if (navigator == null) return null;
      return (tab: active, navigator: navigator);
    } on Object {
      // No scope above the caller, or a host with no workspace: not in a tab.
      return null;
    }
  }
}
