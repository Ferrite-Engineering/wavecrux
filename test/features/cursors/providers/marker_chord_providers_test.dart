// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests the root-scope marker-chord coordinator that powers the focus-
// independent marker shortcuts. Snackbars require a mounted root messenger,
// which is absent in a unit container, so `_showSnackBar` no-ops here and we
// assert the underlying state transitions (arm → complete → set / jump)
// directly against the active tab's per-tab providers.

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/cursors/marker_chord_controller.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/marker_chord_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

void main() {
  // The coordinator resolves the root messenger via a GlobalKey, which touches
  // WidgetsBinding.instance; initialize the test binding so that lookup returns
  // null (no mounted messenger) instead of throwing, and snackbars no-op.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkerChordCoordinator', () {
    late TabContainerManager tcm;
    late ProviderContainer root;
    late MarkerChordCoordinator coordinator;
    late MarkerChordController controller;
    late ProviderContainer activeTab;

    setUp(() {
      tcm = TabContainerManager();
      root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
      coordinator = root.read(markerChordCoordinatorProvider);
      controller = root.read(markerChordControllerProvider);
      activeTab = tcm.containerFor(root.read(activeTabIdProvider));
    });

    tearDown(() {
      tcm.dispose();
      root.dispose();
    });

    test('arm(set) is rejected without a cursor', () {
      coordinator.arm(MarkerChordMode.set);
      expect(controller.isArmed, isFalse);
    });

    test('arm(set) + complete drops a marker at the cursor', () {
      activeTab.read(cursorStateProvider.notifier).placePrimary(420);
      coordinator.arm(MarkerChordMode.set);
      expect(controller.isArmed, isTrue);

      // Any letter completes — not just a/b/c in sequence (regression guard for
      // the reported "only sequential markers" symptom).
      final consumed = coordinator.handleCompletionKey(LogicalKeyboardKey.keyK);
      expect(consumed, isTrue);
      expect(controller.isArmed, isFalse);
      expect(activeTab.read(markerStateProvider).getMarker('k'), 420);
    });

    test('arm(jump) + complete moves the cursor to the named marker', () {
      activeTab.read(markerStateProvider.notifier).setMarker('m', 900);
      // Jump does not require a pre-existing cursor.
      coordinator.arm(MarkerChordMode.jump);
      expect(controller.isArmed, isTrue);

      final consumed = coordinator.handleCompletionKey(LogicalKeyboardKey.keyM);
      expect(consumed, isTrue);
      expect(activeTab.read(cursorStateProvider).primaryCursorTime, 900);
    });

    test('completion key is ignored (not consumed) when nothing is armed', () {
      expect(
        coordinator.handleCompletionKey(LogicalKeyboardKey.keyA),
        isFalse,
      );
    });

    test(
      'a non-letter key cancels an armed chord without setting a marker',
      () {
        activeTab.read(cursorStateProvider.notifier).placePrimary(10);
        coordinator.arm(MarkerChordMode.set);

        final consumed = coordinator.handleCompletionKey(
          LogicalKeyboardKey.digit1,
        );
        expect(consumed, isTrue); // armed → swallowed
        expect(controller.isArmed, isFalse); // but cancelled
        expect(activeTab.read(markerStateProvider).markers, isEmpty);
      },
    );
  });
}
