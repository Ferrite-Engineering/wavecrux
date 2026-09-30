// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

/// Standalone FeatureGate verification for the Custom Widgets panel.
///
/// [FeatureGate.isAvailable] short-circuits to true regardless of
/// [LicenseTier] in a beta build (`kBetaPeriod`, a compile-time constant), so
/// these tests assert the gate semantics the panel relies on directly.
void main() {
  group('FeatureGate semantics for the Custom Widgets panel', () {
    test('Pro tier satisfies the Pro gate', () {
      expect(
        FeatureGate.isAvailable(LicenseTier.pro, LicenseTier.pro),
        isTrue,
      );
    });

    test('Enterprise tier satisfies the Pro gate', () {
      expect(
        FeatureGate.isAvailable(LicenseTier.pro, LicenseTier.enterprise),
        isTrue,
      );
    });

    test('EDU tier satisfies the Pro gate (featureEquivalent maps to Pro)', () {
      expect(
        FeatureGate.isAvailable(LicenseTier.pro, LicenseTier.edu),
        isTrue,
      );
    });

    test('Open Core tier satisfies the Pro gate only in a beta build', () {
      // The beta has ended, so a default build is tier-strict and Open Core
      // is refused. A BETA_PERIOD=true build short-circuits the gate open
      // regardless of tier, and the panel's data branch is then reachable
      // at every tier.
      expect(
        FeatureGate.isAvailable(LicenseTier.pro, LicenseTier.openCore),
        kBetaPeriod,
        reason: kBetaPeriod
            ? 'a beta build opens every gate'
            : 'after the beta, Open Core does not satisfy a Pro gate',
      );
    });

    test('Open Core tier never satisfies an Enterprise-only gate '
        'in featureEquivalent terms (used by the Custom Widgets panel '
        'under Enterprise plugin governance)', () {
      // featureEquivalent for openCore is openCore (index 0), which is
      // strictly less than Enterprise (index 3), so the tier-strict
      // semantics reject openCore for any Enterprise gate. Only a beta
      // build's short-circuit would open it.
      expect(
        LicenseTier.openCore.featureEquivalent.index <
            LicenseTier.enterprise.index,
        isTrue,
      );
    });
  });
}
