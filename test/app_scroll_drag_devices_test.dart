// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/app.dart' show kAppScrollDragDevices;
import 'package:wavecrux/shared/widgets/trackpad_scroll_listener.dart'
    show kTrackpadOwnedDragDevices;

/// Guards the app-wide scroll `dragDevices` configuration.
///
/// Regression guard for the bug where the root [kAppScrollDragDevices] was
/// narrowed to `{ touch }`, which dropped `trackpad` and silently killed
/// two-finger trackpad scrolling in every list/panel/dialog on macOS/iPad. A
/// two-finger trackpad scroll arrives as PointerPanZoom, which a Scrollable
/// only treats as a scroll when `trackpad` is in `dragDevices`.
void main() {
  group('kAppScrollDragDevices', () {
    test('includes trackpad so two-finger scroll works app-wide', () {
      expect(kAppScrollDragDevices, contains(PointerDeviceKind.trackpad));
    });

    test('includes touch and stylus', () {
      expect(kAppScrollDragDevices, contains(PointerDeviceKind.touch));
      expect(kAppScrollDragDevices, contains(PointerDeviceKind.stylus));
    });

    test('excludes mouse so a click-drift never steals a tap', () {
      expect(
        kAppScrollDragDevices,
        isNot(contains(PointerDeviceKind.mouse)),
      );
    });
  });

  group('kTrackpadOwnedDragDevices', () {
    test('excludes trackpad (owned by the widgets own gesture handler)', () {
      expect(
        kTrackpadOwnedDragDevices,
        isNot(contains(PointerDeviceKind.trackpad)),
      );
    });

    test('excludes mouse, keeps touch', () {
      expect(
        kTrackpadOwnedDragDevices,
        isNot(contains(PointerDeviceKind.mouse)),
      );
      expect(kTrackpadOwnedDragDevices, contains(PointerDeviceKind.touch));
    });
  });
}
