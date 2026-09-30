// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/services.dart';

/// Applies an [OrientationLockMode] using
/// [SystemChrome.setPreferredOrientations].
///
/// No-op on desktop platforms — the OS does not honour preferred-orientation
/// hints there, and the corresponding SystemChrome call still succeeds. Tests
/// can inject a [SetPreferredOrientations] override to capture the values
/// without touching real system services.
typedef SetPreferredOrientations =
    Future<void> Function(
      List<DeviceOrientation> orientations,
    );

class OrientationLockService {
  const OrientationLockService({SetPreferredOrientations? setOrientations})
    : _setOrientations =
          setOrientations ?? SystemChrome.setPreferredOrientations;

  final SetPreferredOrientations _setOrientations;

  /// Returns the [DeviceOrientation] list that corresponds to [mode].
  static List<DeviceOrientation> orientationsFor(OrientationLockMode mode) {
    switch (mode) {
      case OrientationLockMode.auto:
      case OrientationLockMode.sensor:
        return const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case OrientationLockMode.landscapeLock:
        return const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case OrientationLockMode.portraitLock:
        return const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ];
    }
  }

  /// Applies [mode] to the system. Always returns a future even when the
  /// platform call is synchronous.
  Future<void> apply(OrientationLockMode mode) =>
      _setOrientations(orientationsFor(mode));
}
