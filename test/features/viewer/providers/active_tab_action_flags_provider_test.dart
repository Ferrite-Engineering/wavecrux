// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests for the root-scope bridge that mirrors the ACTIVE tab's per-tab gating
// flags (cursor / markers / diff / cocotb / pattern) for the action-discovery
// surfaces that live outside any tab scope. Uses a REAL parent/child container
// pair from `TabContainerManager` so the per-tab providers are genuinely
// per-tab (overridden in `wavecruxTabOverrides`), exactly as in the app.
//
// Cursor + markers are exercised end-to-end via their notifiers (simple, sync
// mutations); the diff / cocotb / pattern flags share the identical
// `container.listen` mechanism and are covered for their default state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_action_flags_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

void main() {
  group('activeTabActionFlagsProvider', () {
    late TabContainerManager tcm;
    late ProviderContainer root;

    setUp(() {
      tcm = TabContainerManager();
      root = ProviderContainer(
        overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
      );
      tcm.init(root);
    });

    tearDown(() {
      tcm.dispose();
      root.dispose();
    });

    test('defaults to all-false', () {
      final flags = root.read(activeTabActionFlagsProvider);
      expect(flags.cursorPresent, isFalse);
      expect(flags.markersPresent, isFalse);
      expect(flags.diffActive, isFalse);
      expect(flags.cocotbLogLoaded, isFalse);
      expect(flags.patternMatchesPresent, isFalse);
      // …except the zoom bounds, which are *headroom* flags: with no file the
      // mapper is empty and neither direction can move.
      expect(flags.canZoomOut, isFalse);
      expect(flags.canZoomIn, isFalse);
    });

    test('mirrors the active tab zoom headroom', () {
      // The gate behind the greyed-out Zoom Out button. Both bounds are
      // per-tab state and the toolbar lives at the root scope, so this bridge
      // is the only thing that can tell it the viewport is already at fit-all.
      final sub = root.listen(activeTabActionFlagsProvider, (_, _) {});
      addTearDown(sub.close);

      final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
      activeTab
          .read(timeMapperProvider.notifier)
          .initialize(startTime: 0, endTime: 70, viewportWidth: 1400);

      // `initialize` fits all — the most zoomed-out state there is.
      expect(root.read(activeTabActionFlagsProvider).canZoomOut, isFalse);
      expect(root.read(activeTabActionFlagsProvider).canZoomIn, isTrue);

      activeTab.read(timeMapperProvider.notifier).zoomIn(focalPixel: 700);
      expect(root.read(activeTabActionFlagsProvider).canZoomOut, isTrue);

      activeTab.read(timeMapperProvider.notifier).fitAll();
      expect(root.read(activeTabActionFlagsProvider).canZoomOut, isFalse);
    });

    test('mirrors the active tab cursor + markers and re-emits on change', () {
      // Keep the bridge alive so its imperative `container.listen` stays armed.
      final sub = root.listen(activeTabActionFlagsProvider, (_, _) {});
      addTearDown(sub.close);

      final activeId = root.read(activeTabIdProvider);
      final activeTab = tcm.containerFor(activeId);

      activeTab.read(cursorStateProvider.notifier).placePrimary(100);
      expect(root.read(activeTabActionFlagsProvider).cursorPresent, isTrue);
      expect(root.read(activeTabActionFlagsProvider).markersPresent, isFalse);

      activeTab.read(markerStateProvider.notifier).setMarker('k', 100);
      expect(root.read(activeTabActionFlagsProvider).markersPresent, isTrue);

      activeTab.read(markerStateProvider.notifier).removeMarker('k');
      expect(root.read(activeTabActionFlagsProvider).markersPresent, isFalse);

      activeTab.read(cursorStateProvider.notifier).clearAll();
      expect(root.read(activeTabActionFlagsProvider).cursorPresent, isFalse);
    });

    test('mirrors whether the active tab has rows on its canvas', () {
      // Gates Clear Canvas, which lives in the root-scope menu bar.
      final sub = root.listen(activeTabActionFlagsProvider, (_, _) {});
      addTearDown(sub.close);
      expect(root.read(activeTabActionFlagsProvider).signalsDisplayed, isFalse);

      final activeTab = tcm.containerFor(root.read(activeTabIdProvider));
      activeTab.read(signalGroupsProvider.notifier).addGroup('bus');
      expect(root.read(activeTabActionFlagsProvider).signalsDisplayed, isTrue);

      activeTab.read(signalGroupsProvider.notifier).clearCanvas();
      expect(root.read(activeTabActionFlagsProvider).signalsDisplayed, isFalse);
    });

    test('tracks only the active tab — a different tab does not bleed in', () {
      final sub = root.listen(activeTabActionFlagsProvider, (_, _) {});
      addTearDown(sub.close);

      // A DIFFERENT (non-active) tab places a cursor and a marker.
      final otherTab = tcm.containerFor(TabId.generate());
      otherTab.read(cursorStateProvider.notifier).placePrimary(50);
      otherTab.read(markerStateProvider.notifier).setMarker('a', 50);

      final flags = root.read(activeTabActionFlagsProvider);
      expect(flags.cursorPresent, isFalse);
      expect(flags.markersPresent, isFalse);
    });
  });

  group('ActiveTabActionFlags value semantics', () {
    test('copyWith replaces only the named field', () {
      const base = ActiveTabActionFlags();
      final cursor = base.copyWith(cursorPresent: true);
      expect(cursor.cursorPresent, isTrue);
      expect(cursor.markersPresent, isFalse);
      expect(cursor, isNot(equals(base)));
    });

    test('equality and hashCode are value-based', () {
      const a = ActiveTabActionFlags(cursorPresent: true, diffActive: true);
      const b = ActiveTabActionFlags(cursorPresent: true, diffActive: true);
      const c = ActiveTabActionFlags(cursorPresent: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
