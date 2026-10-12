// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: key-dispatch regression harness, not a presentational
// test. What it asserts is cursor state and the *absence* of a SnackBar — it
// renders no localized string and reads none, and the bug it pins (which
// handler wins a keystroke, and what the descriptor guard sees when it does)
// is locale-independent. The hint string's own rendering is covered where the
// hint is exercised for real, in viewer_screen_test.dart's disabled-shortcut
// tests. The MaterialApp carries L10N.localizationsDelegates only because
// ViewerScreen will not build without them.

import 'dart:async';

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

// The two Escape bindings, driven through the real key pipeline.
//
// THE LOAD-BEARING PART OF THIS FILE IS [ShortcutManagerWidget]. Escape reaches
// the viewer twice — once through `_onKeyEvent`, registered on
// HardwareKeyboard, and once through the focus `Shortcuts` layer that
// ShortcutManagerWidget installs, because a HardwareKeyboard handler returning
// `true` does not suppress that layer. Every bug this file covers lives in the
// gap between those two, and none of them reproduce without the second one
// mounted. `viewer_screen_test.dart` pumps ViewerScreen bare, which is exactly
// why its 60-odd tests were all green while Escape was broken in two ways:
//
//   1. `clearCursors` was dispatched a second time, *after* step 2 had cleared
//      the cursors, so `_handleShortcut`'s descriptor guard refused it for want
//      of a cursor and hinted "Place a cursor in the waveform to use this
//      command" on every Escape that had just successfully cleared one.
//   2. Step 2 matched Escape with any modifier, so ⇧Escape never reached
//      `clearSecondaryCursor` and cleared both cursors instead of the secondary.
//
// A future refactor that moves Escape handling around should keep this harness
// shape whatever else it changes.

/// Per-tab notifiers that arm real `Timer`s and outlive the widget tree; both
/// are stubbed inert for the same reason `viewer_screen_test.dart` stubs them,
/// since placing a cursor is a per-tab mutation and trips the autosave debounce.
class _InertMemoryStatsNotifier extends MemoryStatsNotifier {
  @override
  MemoryStats? build() => null;
}

class _InertSessionAutoSaveNotifier extends SessionAutoSaveNotifier {
  @override
  void build() {}
}

/// Pumps the viewer under the app-level shortcut layer with a waveform
/// reported loaded, and returns the active tab's provider container — the scope
/// the cursors actually live in.
Future<ProviderContainer> _pumpViewer(WidgetTester tester) async {
  final tcm = TabContainerManager(
    extraTabOverrides: [
      memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
      sessionAutoSaveProvider.overrideWith(_InertSessionAutoSaveNotifier.new),
    ],
  );
  final pcm = PaneContainerManager();
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      tabContainerManagerProvider.overrideWithValue(tcm),
      paneContainerManagerProvider.overrideWithValue(pcm),
      ...testWorkspaceOverrides(),
      // The documented widget-test escape hatch for the loaded-file branch:
      // without it every cursor action is disabled on `fileLoaded` instead,
      // and the test would pass for the wrong reason.
      waveformIsLoadedProvider.overrideWithValue(true),
    ],
  );
  tcm.init(root);
  pcm.init(root);
  unawaited(root.wavecruxWorkspace.newTab(displayName: 'New Tab'));
  addTearDown(() {
    tcm.dispose();
    pcm.dispose();
    root.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: root,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const ShortcutManagerWidget(child: ViewerScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tcm.containerFor(root.read(activeTabIdProvider));
}

/// The app's own shape, which the harness above simplifies: the shortcut layer
/// in `MaterialApp.builder` above the Navigator, so a menu's overlay sits under
/// it too. Beside the viewer, a toolbar split button from crux_toolbar, whose
/// sibling menu is a `MenuAnchor` overlay rather than a route.
Future<ProviderContainer> _pumpViewerWithSplitButton(
  WidgetTester tester, {
  required List<String> fired,
}) async {
  final tcm = TabContainerManager(
    extraTabOverrides: [
      memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
      sessionAutoSaveProvider.overrideWith(_InertSessionAutoSaveNotifier.new),
    ],
  );
  final pcm = PaneContainerManager();
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      tabContainerManagerProvider.overrideWithValue(tcm),
      paneContainerManagerProvider.overrideWithValue(pcm),
      ...testWorkspaceOverrides(),
      waveformIsLoadedProvider.overrideWithValue(true),
    ],
  );
  tcm.init(root);
  pcm.init(root);
  unawaited(root.wavecruxWorkspace.newTab(displayName: 'New Tab'));
  addTearDown(() {
    tcm.dispose();
    pcm.dispose();
    root.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: root,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        builder: (context, child) =>
            ShortcutManagerWidget(child: child ?? const SizedBox.shrink()),
        home: Stack(
          children: [
            const ViewerScreen(),
            Positioned(
              right: 8,
              bottom: 40,
              child: Material(
                child: CruxToolbarSplitButton<String>(
                  key: _splitKey,
                  item: const CruxToolbarSplitItem(
                    id: 'test-split',
                    tooltip: 'Variants',
                    variants: [
                      CruxToolbarButtonItem(
                        action: 'a',
                        icon: Icons.looks_one,
                        tooltip: 'Variant A',
                      ),
                      CruxToolbarButtonItem(
                        action: 'b',
                        icon: Icons.looks_two,
                        tooltip: 'Variant B',
                      ),
                    ],
                  ),
                  metrics: CruxToolbarMetrics.desktop,
                  isEnabled: (_) => true,
                  onAction: fired.add,
                  shortcutOf: (_) => null,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tcm.containerFor(root.read(activeTabIdProvider));
}

const _splitKey = Key('test-split-button');

/// Opens the split button's sibling menu with a right-click and puts focus
/// inside it. crux_toolbar from 64b936f focuses the menu itself on open; on an
/// older pin focus stays outside, so the test moves it to the first item, the
/// state a keyboard user (or the newer crux_toolbar) leaves it in. Either way
/// focus ends up inside the menu, which is the case under test.
Future<void> _openSplitMenuWithFocus(WidgetTester tester) async {
  await tester.tap(find.byKey(_splitKey), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  expect(find.text('Variant B'), findsOneWidget);

  final button = tester.widget<ButtonStyleButton>(
    find.descendant(
      of: find.ancestor(
        of: find.text('Variant A'),
        matching: find.byType(MenuItemButton),
      ),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
  final node = button.focusNode;
  expect(node, isNotNull, reason: 'MenuItemButton owns a focus node');
  node?.requestFocus();
  await tester.pump();
  expect(node?.hasPrimaryFocus, isTrue);
}

Future<void> _pressShiftEscape(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

void main() {
  group('Escape', () {
    testWidgets('clears the cursors and says nothing about it', (tester) async {
      final tab = await _pumpViewer(tester);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(tab.read(cursorStateProvider).primaryCursorTime, isNull);
      // The regression: a hint telling the user to place the cursor they had
      // just placed, raised by the action's own success.
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no cursor is silent too', (tester) async {
      // Escape is a dismiss key. "Nothing to dismiss" is not a user error, and
      // the hint would now be the only feedback Escape ever gives — which would
      // be precisely backwards.
      final tab = await _pumpViewer(tester);
      expect(tab.read(cursorStateProvider).primaryCursorTime, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clears both cursors, not just the primary', (tester) async {
      final tab = await _pumpViewer(tester);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      tab.read(cursorStateProvider.notifier).placeSecondary(200);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final state = tab.read(cursorStateProvider);
      expect(state.primaryCursorTime, isNull);
      expect(state.secondaryCursorTime, isNull);
    });
  });

  group('Shift+Escape', () {
    testWidgets('clears only the secondary cursor', (tester) async {
      final tab = await _pumpViewer(tester);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      tab.read(cursorStateProvider.notifier).placeSecondary(200);
      await tester.pumpAndSettle();

      await _pressShiftEscape(tester);
      await tester.pumpAndSettle();

      final state = tab.read(cursorStateProvider);
      // "Remove only the secondary (delta) cursor; primary remains" — the
      // action's own doc, the menu label, and what the keymap editor advertises.
      expect(state.primaryCursorTime, 100);
      expect(state.secondaryCursorTime, isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is silent with no secondary cursor to clear', (tester) async {
      final tab = await _pumpViewer(tester);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      await tester.pumpAndSettle();

      await _pressShiftEscape(tester);
      await tester.pumpAndSettle();

      expect(tab.read(cursorStateProvider).primaryCursorTime, 100);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // wavecrux#26. A `MenuAnchor` menu is an overlay entry, not a route, so the
  // viewer's route check does not see it. With focus inside an open toolbar
  // split-button menu, Escape belongs to the menu.
  group('Escape on an open split-button menu', () {
    testWidgets('closes the menu and keeps the cursors', (tester) async {
      final fired = <String>[];
      final tab = await _pumpViewerWithSplitButton(tester, fired: fired);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      tab.read(cursorStateProvider.notifier).placeSecondary(200);
      await tester.pumpAndSettle();

      await _openSplitMenuWithFocus(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Variant B'), findsNothing, reason: 'menu closed');
      final state = tab.read(cursorStateProvider);
      expect(state.primaryCursorTime, 100);
      expect(state.secondaryCursorTime, 200);
      expect(fired, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shift+Escape also leaves the secondary cursor alone', (
      tester,
    ) async {
      final tab = await _pumpViewerWithSplitButton(tester, fired: []);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      tab.read(cursorStateProvider.notifier).placeSecondary(200);
      await tester.pumpAndSettle();

      await _openSplitMenuWithFocus(tester);
      await _pressShiftEscape(tester);
      await tester.pumpAndSettle();

      expect(tab.read(cursorStateProvider).secondaryCursorTime, 200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the next Escape, with the menu closed, clears the cursors', (
      tester,
    ) async {
      final tab = await _pumpViewerWithSplitButton(tester, fired: []);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      await tester.pumpAndSettle();

      await _openSplitMenuWithFocus(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tab.read(cursorStateProvider).primaryCursorTime, 100);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tab.read(cursorStateProvider).primaryCursorTime, isNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('with the menu closed, Escape clears the cursors as before', (
      tester,
    ) async {
      final tab = await _pumpViewerWithSplitButton(tester, fired: []);
      tab.read(cursorStateProvider.notifier).placePrimary(100);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(tab.read(cursorStateProvider).primaryCursorTime, isNull);
    });
  });
}
