// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/tabs/tab_drag_reorder_test.dart
//
// Tab drag-to-reorder end-to-end integration tests.
//
// Runs against the fully-bootstrapped app under
// LiveTestWidgetsFlutterBinding so the gesture pipeline, DragTarget
// hit-testing, and TabListNotifier are all exercised through the real
// production code path.
//
// Why integration test and not widget test?
//   Widget tests use a synthetic pointer that, combined with the
//   AnimatedContainer 100 ms hover-animation on the insertion slot,
//   made the 0-width slots unreachable. The fix (permanent 8 dp hit
//   zone in _buildInsertionTarget) makes the widget-test-level drag
//   work too — see viewer_tab_bar_test.dart — but an integration test
//   also validates the full app bootstrap, workspace provider alignment,
//   and live binding behaviour, which are out of scope for a widget test.
//
// Slot geometry after the 8 dp hit-zone fix:
//   [slot_0  8dp] [chip_A] [slot_1  8dp] [chip_B] [slot_2  8dp] …
//
// Dropping chip A on slot_2 → [B, A]
// Dropping chip B on slot_0 → [B, A]  (same result via opposite gesture)
//
// The skip guard (skipOnMobileDevice) keeps these tests off the on-device
// emulator/simulator matrix, which runs under the real physical screen size
// and cannot use tester.binding.setSurfaceSize to establish a desktop
// surface. The gestures are validated on the Linux/macOS/Windows CI matrix.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../helpers/app_driver.dart';

String _fixturePath(String relative) => [
  Directory.current.path,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

/// Finds the tab CHIP for [id].
///
/// Deliberately UNSCOPED: a tab chip is keyed `ValueKey(tab.id)`, and that key
/// is required to be unique app-wide. Content/scope/diagnostics subtrees that
/// also key on a tab id are namespaced (`tabScope.pane:…`, `diagTabRow:…`, …)
/// precisely so this lookup resolves to exactly the chip. So this finder also
/// doubles as a regression guard: if a future widget re-introduces a bare
/// `ValueKey(tab.id)` on the active tab, `findsOneWidget` / `tester.drag` here
/// blow up with "Found 2 … is too many" — which is what regressed once before.
Finder _chipByKey(TabId id) => find.byKey(ValueKey(id));

/// Drags the [chip] onto the insertion slot centred at [target] with a
/// multi-step gesture, then waits for the reorder to land.
///
/// A naive single `tester.drag` (one down → one move → up) is unreliable for
/// these reorders under headless Linux/xvfb, so the gesture is hardened two
/// ways:
///
///  1. **Engage the Draggable vertically.** The tab chips live in a horizontal
///     `SingleChildScrollView` (`ViewerTabBar`). Starting the drag with a
///     *horizontal* move competes with that scroll view's
///     `HorizontalDragGestureRecognizer` in the gesture arena. A **vertical**
///     slop-breaking nudge lets the `Draggable`'s multi-axis recognizer claim
///     the gesture first while the horizontal scroller — which only reacts to
///     horizontal motion — stays out of the arena. Only then do we move
///     horizontally to the slot.
///  2. **Walk the pointer slot-by-slot.** The `Draggable` → `DragTarget`
///     pipeline needs the pointer to actually *cross* each 8 dp insertion slot,
///     frame by frame, for the slot under the pointer to latch as the accept
///     candidate. We step the pointer with a pump after each, then hold so the
///     slot's `onWillAcceptWithDetails` latches and its 100 ms insertion-bar
///     `AnimatedContainer` settles.
///
/// (Reachability of the *leading* slot on the Linux frameless build — where the
/// window's left drag-to-resize border would otherwise occlude it — is handled
/// in production by `ViewerTabBar`'s `windowChromeLeftResizeEdge` inset, not
/// here.) [orderReached] is then polled (bounded) so slow state propagation
/// doesn't race the assertion.
Future<void> _dragChipToSlot(
  WidgetTester tester,
  Finder chip,
  Offset target, {
  required bool Function() orderReached,
}) async {
  final start = tester.getCenter(chip);
  final gesture = await tester.startGesture(start);
  try {
    // Engage the Draggable with a VERTICAL slop-breaking nudge (kTouchSlop ≈
    // 18 dp) so its multi-axis recognizer claims the gesture before any
    // horizontal motion — keeping the surrounding horizontal scroll view out
    // of the arena (see doc comment, point 1). Down stays inside the window
    // (the tab bar sits at the top).
    final engaged = start + const Offset(0, 28);
    await gesture.moveTo(engaged);
    await tester.pump();

    // Now walk horizontally (and back up to the slot row) to the target slot.
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(engaged, target, i / steps)!);
      await tester.pump();
    }
    // Hold over the slot so onWillAccept latches and the insertion bar settles.
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
  } catch (_) {
    await gesture.up();
    rethrow;
  }
  await pumpUntil(tester, orderReached);
}

/// Finds the keyed insertion slot at pane-local position [index]
/// (`tabInsertionSlot_<paneId>_<index>`), independent of the pane id.
Finder _insertionSlot(int index) => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> &&
      key.value.startsWith('tabInsertionSlot_') &&
      key.value.endsWith('_$index');
});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  setUp(() async {
    await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
  });

  tearDown(() async {
    await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
  });

  // ── helper: boot the app with two tabs open ─────────────────────────────

  Future<void> bootWithTwoTabs(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final firstPath = _fixturePath('vcd/scalar_basics.vcd');
    final secondPath = _fixturePath('vcd/vector_formats.vcd');

    await seedFirstLaunchAnswers();
    await bootstrap(args: [firstPath, secondPath]);
    await tester.pump();
    await pumpUntilWaveformReady(tester);

    // The second tab is opened from a post-frame callback in WaveCruxApp —
    // pump until both are present.
    final root = rootContainer(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (root.read(tabListProvider).length >= 2) break;
    }
    await tester.pumpAndSettle();
  }

  // ── test: drag first tab past second tab ────────────────────────────────

  testWidgets(
    'drag first tab past second tab reorders to [B, A]',
    (tester) async {
      await bootWithTwoTabs(tester);

      final root = rootContainer(tester);
      final tabs = root.read(tabListProvider);
      expect(tabs.length, equals(2));

      final idA = tabs[0].id; // scalar_basics
      final idB = tabs[1].id; // vector_formats

      final chipA = _chipByKey(idA);
      final chipB = _chipByKey(idB);
      expect(chipA, findsOneWidget);
      expect(chipB, findsOneWidget);

      // Drop onto the insertion slot after chip B (end slot) → reorder A after B.
      final target = tester.getCenter(_insertionSlot(2).first);
      await _dragChipToSlot(
        tester,
        chipA,
        target,
        orderReached: () {
          final t = root.read(tabListProvider);
          return t.length == 2 && t.first.id == idB;
        },
      );

      final after = root.read(tabListProvider);
      expect(
        after[0].id,
        equals(idB),
        reason: 'vector_formats should now be first',
      );
      expect(
        after[1].id,
        equals(idA),
        reason: 'scalar_basics should now be second',
      );
      expect(tester.takeException(), isNull);
    },
    skip: skipOnMobileDevice,
  );

  // ── test: drag second tab before first tab ──────────────────────────────

  testWidgets(
    'drag second tab before first tab reorders to [B, A]',
    (tester) async {
      await bootWithTwoTabs(tester);

      final root = rootContainer(tester);
      final tabs = root.read(tabListProvider);
      expect(tabs.length, equals(2));

      final idA = tabs[0].id; // scalar_basics
      final idB = tabs[1].id; // vector_formats

      final chipA = _chipByKey(idA);
      final chipB = _chipByKey(idB);
      expect(chipA, findsOneWidget);
      expect(chipB, findsOneWidget);

      // Drop onto the leading insertion slot (before chip A) → reorder B before
      // A. On the Linux frameless build this slot would sit under the window's
      // 8 dp left drag-to-resize border and be an unreachable drop target; the
      // tab strip insets past it (see ViewerTabBar / windowChromeLeftResizeEdge)
      // so this drop lands.
      final target = tester.getCenter(_insertionSlot(0).first);
      await _dragChipToSlot(
        tester,
        chipB,
        target,
        orderReached: () {
          final t = root.read(tabListProvider);
          return t.length == 2 && t.first.id == idB;
        },
      );

      final after = root.read(tabListProvider);
      expect(
        after[0].id,
        equals(idB),
        reason: 'vector_formats should now be first',
      );
      expect(
        after[1].id,
        equals(idA),
        reason: 'scalar_basics should now be second',
      );
      expect(tester.takeException(), isNull);
    },
    skip: skipOnMobileDevice,
  );

  // ── test: three tabs, drag middle tab to last position ──────────────────

  testWidgets(
    'drag middle tab to last position in a three-tab bar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final firstPath = _fixturePath('vcd/scalar_basics.vcd');
      final secondPath = _fixturePath('vcd/vector_formats.vcd');
      final thirdPath = _fixturePath('vcd/deep_hierarchy.vcd');

      await seedFirstLaunchAnswers();
      await bootstrap(args: [firstPath, secondPath, thirdPath]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (root.read(tabListProvider).length >= 3) break;
      }
      await tester.pumpAndSettle();

      final tabs = root.read(tabListProvider);
      expect(tabs.length, equals(3));

      final idA = tabs[0].id;
      final idB = tabs[1].id;
      final idC = tabs[2].id;

      final chipB = _chipByKey(idB);
      final chipC = _chipByKey(idC);
      expect(chipB, findsOneWidget);
      expect(chipC, findsOneWidget);

      // Drag B to slot after C (end slot, index 3) → [A, C, B].
      final target = tester.getCenter(_insertionSlot(3).first);
      await _dragChipToSlot(
        tester,
        chipB,
        target,
        orderReached: () {
          final t = root.read(tabListProvider);
          return t.length == 3 && t.last.id == idB;
        },
      );

      final after = root.read(tabListProvider);
      expect(after[0].id, equals(idA));
      expect(after[1].id, equals(idC));
      expect(after[2].id, equals(idB));
      expect(tester.takeException(), isNull);
    },
    skip: skipOnMobileDevice,
  );
}
