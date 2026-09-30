// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavecrux/services/platform/orientation_lock_service.dart';

void main() {
  group('OrientationLockService.orientationsFor', () {
    test('auto allows every orientation', () {
      final orientations = OrientationLockService.orientationsFor(
        OrientationLockMode.auto,
      );
      expect(orientations, contains(DeviceOrientation.portraitUp));
      expect(orientations, contains(DeviceOrientation.portraitDown));
      expect(orientations, contains(DeviceOrientation.landscapeLeft));
      expect(orientations, contains(DeviceOrientation.landscapeRight));
    });

    test('sensor allows every orientation', () {
      final orientations = OrientationLockService.orientationsFor(
        OrientationLockMode.sensor,
      );
      expect(orientations.length, 4);
    });

    test('landscapeLock returns only landscape orientations', () {
      final orientations = OrientationLockService.orientationsFor(
        OrientationLockMode.landscapeLock,
      );
      expect(
        orientations,
        unorderedEquals(<DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    });

    test('portraitLock returns only portrait orientations', () {
      final orientations = OrientationLockService.orientationsFor(
        OrientationLockMode.portraitLock,
      );
      expect(
        orientations,
        unorderedEquals(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]),
      );
    });
  });

  group('OrientationLockService.apply', () {
    test('forwards landscapeLock to the injected setter', () async {
      List<DeviceOrientation>? captured;
      final service = OrientationLockService(
        setOrientations: (orientations) async {
          captured = orientations;
        },
      );

      await service.apply(OrientationLockMode.landscapeLock);

      expect(
        captured,
        unorderedEquals(<DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    });

    test('forwards portraitLock to the injected setter', () async {
      List<DeviceOrientation>? captured;
      final service = OrientationLockService(
        setOrientations: (orientations) async {
          captured = orientations;
        },
      );

      await service.apply(OrientationLockMode.portraitLock);

      expect(captured, contains(DeviceOrientation.portraitUp));
      expect(captured, contains(DeviceOrientation.portraitDown));
      expect(captured, isNot(contains(DeviceOrientation.landscapeLeft)));
    });

    test('auto sends all four orientations', () async {
      List<DeviceOrientation>? captured;
      final service = OrientationLockService(
        setOrientations: (orientations) async {
          captured = orientations;
        },
      );

      await service.apply(OrientationLockMode.auto);

      expect(captured?.length, 4);
    });
  });
}
