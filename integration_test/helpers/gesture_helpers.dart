// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/helpers/gesture_helpers.dart
//
// Touch gesture helpers for integration tests.
//
// These helpers simulate multi-touch gestures that cannot be replicated with
// [WidgetTester]'s single-pointer API. They are designed for testing gesture
// interactions on [WaveformCanvas] (pinch-zoom, two-finger pan) and
// [PlatformContextMenu]-wrapped rows.

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';

/// Performs a pinch gesture on [target] to scale the viewport by [scale].
///
/// A [scale] > 1 zooms in (fingers moving apart); [scale] < 1 zooms out
/// (fingers moving together). The gesture is centred on the widget's bounding
/// box, with each finger starting 50 logical pixels from the centre along the
/// horizontal axis.
///
/// Pumps a settle after the gesture completes.
Future<void> pinchZoom(
  WidgetTester tester,
  Finder target,
  double scale,
) async {
  final center = tester.getCenter(target);
  const startOffset = Offset(50, 0);
  final endOffset = startOffset * scale;

  final gesture1 = await tester.startGesture(center - startOffset);
  final gesture2 = await tester.startGesture(center + startOffset);
  await tester.pump();

  await gesture1.moveTo(center - endOffset);
  await gesture2.moveTo(center + endOffset);
  await tester.pump(const Duration(milliseconds: 50));

  await gesture1.up();
  await gesture2.up();
  await tester.pumpAndSettle();
}

/// Performs a two-finger pan gesture on [target], translating both contact
/// points by [delta] from their starting positions.
///
/// Both fingers start at the widget centre ± 20 logical pixels horizontally
/// so that a standard pan-gesture recogniser distinguishes this from a
/// single-finger scroll. The gesture finishes with both fingers lifted.
///
/// Pumps a settle after the gesture completes.
Future<void> twoFingerPan(
  WidgetTester tester,
  Finder target,
  Offset delta,
) async {
  final center = tester.getCenter(target);
  const fingerOffset = Offset(20, 0);

  final gesture1 = await tester.startGesture(center - fingerOffset);
  final gesture2 = await tester.startGesture(center + fingerOffset);
  await tester.pump();

  await gesture1.moveBy(delta);
  await gesture2.moveBy(delta);
  await tester.pump(const Duration(milliseconds: 50));

  await gesture1.up();
  await gesture2.up();
  await tester.pumpAndSettle();
}

/// Long-presses [target] and waits for any resulting overlay (context menu,
/// bottom sheet, dialog) to appear.
///
/// On touch device classes, long-press fires the [PlatformContextMenu]
/// equivalent of a desktop right-click. This wrapper documents intent and
/// pumps a settle after the gesture.
Future<void> longPress(WidgetTester tester, Finder target) async {
  await tester.longPress(target);
  await tester.pumpAndSettle();
}

/// Simulates a right-click (secondary mouse button tap) on [target] and waits
/// for any resulting overlay to appear.
///
/// [PlatformContextMenu] responds to secondary-button taps on desktop device
/// classes running macOS / Linux / Windows (where long-press is intentionally
/// disabled to avoid the 500 ms delay on pointer devices). Use this helper
/// whenever an integration test needs to open a context menu in the desktop
/// test environment.
Future<void> rightClick(WidgetTester tester, Finder target) async {
  await tester.tap(target, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}
