// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

void main() {
  group('MobileMetrics', () {
    group('touch set', () {
      const m = MobileMetrics.touch();

      test(
        'exposes the binding mobile UI standards from ARCHITECTURE.md §3.1.8.1',
        () {
          expect(m.touchTarget, 44);
          expect(m.iconSize, 24);
          expect(m.toolbarButton, 48);
          expect(m.toolbarHeight, 48);
          expect(m.statusBarHeight, 40);
          expect(m.panelHeaderHeight, 44);
          expect(m.splitterHitWidth, 32);
          expect(m.splitterVisualWidth, 6);
          expect(m.laneResizeHandle, 16);
          expect(m.cursorMarkerSize, 18);
          expect(m.namedMarkerFlag, 16);
          expect(m.dragHandleHitArea, 44);
          expect(m.colorSwatch, 16);
          expect(m.bodyText, 14);
          expect(m.labelText, 12);
          expect(m.monoText, 13);
          expect(m.statusBarText, 13);
          expect(m.isTouch, isTrue);
        },
      );
    });

    group('desktop set', () {
      const m = MobileMetrics.desktop();

      test('matches the historical desktop sizing baseline', () {
        expect(m.touchTarget, 28);
        expect(m.iconSize, 18);
        expect(m.toolbarButton, 36);
        expect(m.toolbarHeight, 40);
        expect(m.statusBarHeight, 24);
        expect(m.panelHeaderHeight, 32);
        expect(m.splitterHitWidth, 12);
        expect(m.splitterVisualWidth, 6);
        expect(m.laneResizeHandle, 4);
        expect(m.cursorMarkerSize, 10);
        expect(m.namedMarkerFlag, 8);
        expect(m.dragHandleHitArea, 24);
        expect(m.colorSwatch, 12);
        expect(m.bodyText, 11);
        expect(m.labelText, 10);
        expect(m.monoText, 11);
        expect(m.statusBarText, 11);
        expect(m.isTouch, isFalse);
      });
    });

    group('resolve', () {
      test('phone class on any platform → touch', () {
        for (final p in TargetPlatform.values) {
          final m = MobileMetrics.resolve(DeviceClass.phone, p);
          expect(
            m.isTouch,
            isTrue,
            reason: 'phone class on $p should resolve to touch',
          );
        }
      });

      test('tablet class on any platform → touch', () {
        for (final p in TargetPlatform.values) {
          final m = MobileMetrics.resolve(DeviceClass.tablet, p);
          expect(
            m.isTouch,
            isTrue,
            reason: 'tablet class on $p should resolve to touch',
          );
        }
      });

      test('phoneLandscape class on any platform → touch', () {
        for (final p in TargetPlatform.values) {
          final m = MobileMetrics.resolve(DeviceClass.phoneLandscape, p);
          expect(m.isTouch, isTrue);
        }
      });

      test('desktop class on macOS/Linux/Windows → desktop', () {
        for (final p in [
          TargetPlatform.macOS,
          TargetPlatform.linux,
          TargetPlatform.windows,
        ]) {
          final m = MobileMetrics.resolve(DeviceClass.desktop, p);
          expect(
            m.isTouch,
            isFalse,
            reason: 'desktop class on $p should resolve to desktop',
          );
        }
      });

      test('desktop class on iOS (e.g. iPad Pro 12.9" landscape) → touch', () {
        final m = MobileMetrics.resolve(
          DeviceClass.desktop,
          TargetPlatform.iOS,
        );
        expect(m.isTouch, isTrue);
      });

      test('desktop class on Android → touch', () {
        final m = MobileMetrics.resolve(
          DeviceClass.desktop,
          TargetPlatform.android,
        );
        expect(m.isTouch, isTrue);
      });
    });

    group('of(context, deviceClass)', () {
      testWidgets('reads platform from Theme', (tester) async {
        late MobileMetrics observed;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Builder(
              builder: (context) {
                observed = MobileMetrics.of(context, DeviceClass.desktop);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(observed.isTouch, isTrue);
      });

      testWidgets('respects ThemeData(platform: macOS) at desktop class', (
        tester,
      ) async {
        late MobileMetrics observed;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Builder(
              builder: (context) {
                observed = MobileMetrics.of(context, DeviceClass.desktop);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(observed.isTouch, isFalse);
      });

      testWidgets('returns touch metrics on tablet regardless of host', (
        tester,
      ) async {
        late MobileMetrics observed;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Builder(
              builder: (context) {
                observed = MobileMetrics.of(context, DeviceClass.tablet);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(observed.isTouch, isTrue);
        expect(observed.touchTarget, 44);
      });
    });
  });
}
