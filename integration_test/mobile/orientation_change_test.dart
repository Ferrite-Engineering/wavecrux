// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/orientation_change_test.dart
//
// Orientation change state preservation. 📱 iOS/Android only.
//
// Per ARCHITECTURE.md §3.1.7, orientation changes must not lose state.
// Riverpod providers (cursor, zoom, signal arrangement, Stage config)
// survive widget rebuilds because they live in `ProviderScope` containers
// outside the layout widget tree.
//
// On a real iOS / Android simulator, an orientation change is delivered
// via the platform's `onMetricsChanged` callback. In the integration-test
// environment the same effect is produced by swapping the surface
// dimensions (portrait → landscape) via `tester.binding.setSurfaceSize`.
//
// Gated to iOS / Android via `defaultTargetPlatform`. On desktop the test
// is skipped.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';

import '../helpers/app_driver.dart';
import '_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'orientation change (portrait → landscape) preserves cursor',
    (tester) async {
      // Begin in portrait phone class.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      // Place the primary cursor at T=100 ticks.
      load.tabContainer.read(cursorStateProvider.notifier).placePrimary(100);
      await tester.pumpAndSettle();

      final cursorBefore = load.tabContainer
          .read(cursorStateProvider)
          .primaryCursorTime;
      expect(cursorBefore, 100);

      // Rotate to landscape — swap width / height.
      await tester.binding.setSurfaceSize(const Size(844, 390));
      await tester.pumpAndSettle();

      expect(
        load.tabContainer.read(cursorStateProvider).primaryCursorTime,
        cursorBefore,
        reason: 'primary cursor must survive the orientation change',
      );

      // Rotate back to portrait — still preserved.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      expect(
        load.tabContainer.read(cursorStateProvider).primaryCursorTime,
        cursorBefore,
        reason: 'cursor must survive round-trip rotation',
      );

      drainTransientLayoutExceptions(tester);
    },
    skip:
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android,
  );
}
