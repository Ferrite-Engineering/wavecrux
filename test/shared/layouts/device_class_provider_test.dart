// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

void main() {
  group('displaySizeProvider', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(displaySizeProvider), isNull);
    });

    test('set updates the state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(800, 600));
      expect(container.read(displaySizeProvider), const Size(800, 600));
    });

    test('set is idempotent — same size is a no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var notifications = 0;
      container.listen(
        displaySizeProvider,
        (_, _) => notifications++,
      );

      const size = Size(900, 700);
      container.read(displaySizeProvider.notifier).set(size);
      container.read(displaySizeProvider.notifier).set(size);
      container.read(displaySizeProvider.notifier).set(size);

      expect(notifications, 1);
    });

    test('different sizes produce separate notifications', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var notifications = 0;
      container.listen(
        displaySizeProvider,
        (_, _) => notifications++,
      );

      container.read(displaySizeProvider.notifier).set(const Size(400, 800));
      container.read(displaySizeProvider.notifier).set(const Size(800, 1100));
      container.read(displaySizeProvider.notifier).set(const Size(1400, 900));

      expect(notifications, 3);
    });
  });

  group('deviceClassProvider', () {
    test('defaults to desktop when size is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(deviceClassProvider), DeviceClass.desktop);
    });

    test('phone width → DeviceClass.phone', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(400, 800));
      expect(container.read(deviceClassProvider), DeviceClass.phone);
    });

    test('phone-landscape (width ≥ 600 but height < 500) → phoneLandscape', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(700, 380));
      expect(container.read(deviceClassProvider), DeviceClass.phoneLandscape);
    });

    test('tablet width → DeviceClass.tablet', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(900, 800));
      expect(container.read(deviceClassProvider), DeviceClass.tablet);
    });

    test('desktop width → DeviceClass.desktop', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(1400, 900));
      expect(container.read(deviceClassProvider), DeviceClass.desktop);
    });

    test('re-evaluates when size changes (resize / orientation change)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(400, 800));
      expect(container.read(deviceClassProvider), DeviceClass.phone);

      // Rotate to landscape — phone becomes phoneLandscape (cross-class).
      container.read(displaySizeProvider.notifier).set(const Size(800, 400));
      expect(container.read(deviceClassProvider), DeviceClass.phoneLandscape);

      // Resize to a window/display of tablet dimensions.
      container.read(displaySizeProvider.notifier).set(const Size(900, 1100));
      expect(container.read(deviceClassProvider), DeviceClass.tablet);

      // Resize to desktop.
      container.read(displaySizeProvider.notifier).set(const Size(1500, 1000));
      expect(container.read(deviceClassProvider), DeviceClass.desktop);
    });

    test('boundary widths classify as expected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(displaySizeProvider.notifier).set(const Size(599, 800));
      expect(container.read(deviceClassProvider), DeviceClass.phone);

      container.read(displaySizeProvider.notifier).set(const Size(600, 800));
      expect(container.read(deviceClassProvider), DeviceClass.tablet);

      container.read(displaySizeProvider.notifier).set(const Size(1199, 800));
      expect(container.read(deviceClassProvider), DeviceClass.tablet);

      container.read(displaySizeProvider.notifier).set(const Size(1200, 800));
      expect(container.read(deviceClassProvider), DeviceClass.desktop);
    });
  });

  group('deviceClassForSize — native-desktop-host flooring', () {
    // flutter_test defaults defaultTargetPlatform to android, so the size-based
    // tests above exercise the web/mobile path. These override the platform to
    // the native desktop OSes and assert the layout never reflows below
    // desktop — a small desktop window just shrinks, it does not go tablet.
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test('$platform floors every size to desktop', () {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        expect(isDesktopHostPlatform, isTrue);
        expect(deviceClassForSize(const Size(400, 800)), DeviceClass.desktop);
        expect(deviceClassForSize(const Size(700, 380)), DeviceClass.desktop);
        expect(deviceClassForSize(const Size(900, 800)), DeviceClass.desktop);
        expect(deviceClassForSize(null), DeviceClass.desktop);
      });
    }

    for (final platform in const [
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      test('$platform keeps the size-based classification', () {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        expect(isDesktopHostPlatform, isFalse);
        expect(deviceClassForSize(const Size(400, 800)), DeviceClass.phone);
        expect(deviceClassForSize(const Size(900, 800)), DeviceClass.tablet);
        expect(deviceClassForSize(const Size(1400, 900)), DeviceClass.desktop);
      });
    }

    test('deviceClassProvider floors a small window to desktop on a Mac', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // A 500-dp-wide window would be DeviceClass.phone by size alone.
      container.read(displaySizeProvider.notifier).set(const Size(500, 700));
      expect(container.read(deviceClassProvider), DeviceClass.desktop);
    });
  });
}
