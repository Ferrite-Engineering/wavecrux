// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_stage_widget.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

/// Tachometer is the open-core Rive reference widget. These tests assert the
/// registration shape
/// and tier gating that the Stage picker relies on.
void main() {
  group('TachometerStageWidget — open-core registration', () {
    test(
      'declares requiredTier = LicenseTier.openCore so any tier can '
      'instantiate it',
      () {
        const widget = TachometerStageWidget();
        expect(widget.requiredTier, LicenseTier.openCore);
      },
    );

    test(
      'is reachable through StageRegistry.instance once registered '
      '(bootstrap path; tests register defensively to avoid suite-order '
      'coupling)',
      () {
        final registry = StageRegistry.instance;
        if (!registry.isRegistered(TachometerStageWidget.widgetId)) {
          registry.register(const TachometerStageWidget());
        }
        expect(registry.isRegistered(TachometerStageWidget.widgetId), isTrue);
      },
    );

    test(
      'FeatureGate.isAvailable allows the Tachometer for every tier '
      '(open-core gate, post-beta)',
      () {
        for (final tier in LicenseTier.values) {
          final container = ProviderContainer(
            overrides: [
              licenseTierProvider.overrideWith((_) => tier),
              betaPeriodProvider.overrideWith((_) => false),
            ],
          );
          addTearDown(container.dispose);
          final currentTier = container.read(licenseTierProvider);
          expect(
            FeatureGate.isAvailable(LicenseTier.openCore, currentTier),
            isTrue,
            reason:
                'Open-core gate must pass for tier=$tier '
                '(post-beta semantics)',
          );
        }
      },
    );
  });
}
