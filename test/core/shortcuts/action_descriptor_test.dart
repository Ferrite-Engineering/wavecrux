// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_requirement.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

void main() {
  group('ActionDescriptor', () {
    const ctx = ActionContext(fileLoaded: true, deviceClass: DeviceClass.phone);

    test('defaults: no surfaces, open-core, always visible and enabled', () {
      const d = ActionDescriptor();
      expect(d.surfaces, isEmpty);
      expect(d.requiredTier, LicenseTier.openCore);
      expect(d.isVisible(ctx), isTrue);
      expect(d.isEnabled(ctx), isTrue);
      expect(d.requires, isEmpty);
      expect(d.unmetRequirement(ctx), isNull);
    });

    test('surfaces and predicates are honored', () {
      final d = ActionDescriptor(
        surfaces: const {ActionSurface.menu, ActionSurface.palette},
        requiredTier: LicenseTier.pro,
        isVisible: (c) => !c.isPhoneClass,
        requires: const [ActionRequirement.fileLoaded],
      );
      expect(d.surfaces, {ActionSurface.menu, ActionSurface.palette});
      expect(d.requiredTier, LicenseTier.pro);
      expect(
        d.isVisible(
          const ActionContext(fileLoaded: true, deviceClass: DeviceClass.phone),
        ),
        isFalse,
      );
      expect(
        d.isVisible(
          const ActionContext(
            fileLoaded: true,
            deviceClass: DeviceClass.desktop,
          ),
        ),
        isTrue,
      );
      expect(d.isEnabled(ctx), isTrue);
      expect(d.unmetRequirement(ctx), isNull);
      expect(
        d.unmetRequirement(
          const ActionContext(
            fileLoaded: false,
            deviceClass: DeviceClass.desktop,
          ),
        ),
        ActionRequirement.fileLoaded,
        reason: 'the unmet requirement is what the keyboard hint is built from',
      );
    });
  });
}
