// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/platform/orientation_lock_service.dart';

part 'orientation_lock_provider.g.dart';

/// Provides the [OrientationLockService] used by [orientationLockSync] to
/// apply preference changes via `SystemChrome.setPreferredOrientations`.
///
/// Override in tests to capture the orientations without touching real
/// platform channels.
@Riverpod(keepAlive: true)
OrientationLockService orientationLockService(
  Ref ref,
) => const OrientationLockService();

/// Watches [appSettingsProvider] and pushes the selected
/// [OrientationLockMode] into [OrientationLockService.apply] whenever the
/// preference changes.
///
/// No-op on desktop (Linux, macOS, Windows) and on web — those platforms
/// don't honour preferred-orientation hints. Returns the most recently
/// applied mode (or `null` while the settings async value is still loading)
/// so `ref.watch` can keep the provider alive.
@Riverpod(keepAlive: true)
OrientationLockMode? orientationLockSync(Ref ref) {
  if (kIsWeb || isDesktopPlatform) return null;
  final asyncSettings = ref.watch(appSettingsProvider);
  final mode = asyncSettings.value?.orientationLockMode;
  if (mode == null) return null;
  // Apply on the next microtask so the build cycle is not blocked by the
  // platform channel call.
  unawaited(
    Future.microtask(() {
      unawaited(ref.read(orientationLockServiceProvider).apply(mode));
    }),
  );
  return mode;
}
