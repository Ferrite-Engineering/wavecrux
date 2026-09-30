// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/platform_utils.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('isDesktopPlatform', () {
    test('is true for the three desktop OSes', () {
      for (final platform in const [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(isDesktopPlatform, isTrue, reason: '$platform');
      }
    });

    test('is false on mobile', () {
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(isDesktopPlatform, isFalse, reason: '$platform');
      }
    });
  });

  group('isMobileHostPlatform', () {
    test('is true on iOS and Android', () {
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(isMobileHostPlatform, isTrue, reason: '$platform');
      }
    });

    test('is false on desktop and fuchsia', () {
      for (final platform in const [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(isMobileHostPlatform, isFalse, reason: '$platform');
      }
    });

    test('is disjoint from isDesktopPlatform on every real host', () {
      // The two predicates gate opposite sides of several app-store rules
      // (tier-badged actions, the update banner, the RGB LED wording). If a
      // platform ever satisfied both, those gates would contradict.
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          isMobileHostPlatform && isDesktopPlatform,
          isFalse,
          reason: '$platform',
        );
      }
    });
  });
}
