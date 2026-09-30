// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

part 'application_edition_provider.g.dart';

/// Provides the localized edition label for the running WaveCrux build.
///
/// Derives the label from [licenseTierProvider] so the existing Pro overlay
/// override (`licenseTierProvider.overrideWith((_) => LicenseTier.pro)`)
/// automatically causes this provider to return `'Pro'` without a separate
/// override. Tier labels for Pro, EDU, and Enterprise are proper nouns and
/// do not require per-locale translation.
///
/// Usage in a widget:
/// ```dart
/// final edition = ref.watch(applicationEditionProvider(l10n));
/// ```
@Riverpod(keepAlive: true)
String applicationEdition(Ref ref, L10N l10n) {
  final tier = ref.watch(licenseTierProvider);
  return switch (tier) {
    LicenseTier.openCore => l10n.aboutEditionOpenCore,
    LicenseTier.edu => 'EDU',
    LicenseTier.pro => 'Pro',
    LicenseTier.enterprise => 'Enterprise',
  };
}
