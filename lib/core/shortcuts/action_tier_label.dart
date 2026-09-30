// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Parenthetical license-tier suffix for a *native* menu-bar item's label —
/// e.g. `" (PRO)"` / `" (ENT)"`, or an empty string for open-core / edu.
///
/// The platform [PlatformMenuBar] can only render a `String` label (no badge
/// widget), so Pro/Enterprise menu items communicate their required tier with
/// this text suffix. The Flutter surfaces (overflow menu, command palette)
/// render a `WaveCruxFeatureTierBadge` widget instead and do not use this.
String tierLabelSuffix(LicenseTier tier, L10N l10n) => switch (tier) {
  LicenseTier.pro => l10n.menuItemTierSuffix(l10n.tierBadgePro),
  LicenseTier.enterprise => l10n.menuItemTierSuffix(l10n.tierBadgeEnterprise),
  LicenseTier.openCore || LicenseTier.edu => '',
};
