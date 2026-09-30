// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrientationLockMode', () {
    test('has exactly four variants', () {
      expect(OrientationLockMode.values.length, 4);
    });

    test('contains auto, landscapeLock, portraitLock, sensor', () {
      expect(OrientationLockMode.values, contains(OrientationLockMode.auto));
      expect(
        OrientationLockMode.values,
        contains(OrientationLockMode.landscapeLock),
      );
      expect(
        OrientationLockMode.values,
        contains(OrientationLockMode.portraitLock),
      );
      expect(
        OrientationLockMode.values,
        contains(OrientationLockMode.sensor),
      );
    });

    test('enum index ordering is stable (used as persistence key)', () {
      // Persisted as `index` in SharedPreferences. Reordering breaks
      // forward-compatibility for users with existing stored preferences.
      expect(OrientationLockMode.auto.index, 0);
      expect(OrientationLockMode.landscapeLock.index, 1);
      expect(OrientationLockMode.portraitLock.index, 2);
      expect(OrientationLockMode.sensor.index, 3);
    });
  });
}
