// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:wavecrux/core/router.dart' show rootNavigatorKey;
import 'package:wavecrux/features/settings/screens/settings_screen.dart';

/// Opens Settings at the License category.
///
/// The one way WaveCrux's licence surfaces reach Settings → License: the
/// licence-expiry strip and the status bar's EDU chip. The strip sits above
/// the root navigator, so this opens Settings from that navigator's context,
/// the same way the menu bar's actions find one. A no-op while no navigator
/// is mounted.
void openLicenseSettings() {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  unawaited(
    SettingsScreen.openAdaptive(
      context,
      initialCategoryId: kCruxLicenseCategoryId,
    ),
  );
}
