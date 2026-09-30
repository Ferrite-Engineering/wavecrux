// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_stage_widget.dart';

void main() {
  group('TachometerStageWidget — identity / metadata', () {
    test('id is the stable Pro-tier identifier', () {
      const w = TachometerStageWidget();
      expect(w.id, 'wavecrux.pro.tachometer');
      expect(TachometerStageWidget.widgetId, 'wavecrux.pro.tachometer');
    });

    test('category is instrument (Pro pack — Engineering Instruments)', () {
      const w = TachometerStageWidget();
      expect(w.category, StageWidgetCategory.instrument);
    });

    test('requiredTier is LicenseTier.openCore', () {
      // The picker dialog reads `StageWidget.requiredTier` to route
      // activation through `FeatureGate.isAvailable`. The Tachometer is the
      // open-core Rive reference widget so anyone can author and run custom Stage
      // widgets; only its tier-gate semantics changed — it remains the
      // canonical example of the runtime + manifest + normalizer
      // pipeline that third-party `.wcrux-widget` bundles target.
      const w = TachometerStageWidget();
      expect(w.requiredTier, LicenseTier.openCore);
    });

    test('default + min size are sensible for a gauge widget', () {
      const w = TachometerStageWidget();
      final (defaultW, defaultH) = w.defaultSize;
      final (minW, minH) = w.minSize;
      expect(defaultW, greaterThan(0));
      expect(defaultH, greaterThan(0));
      expect(minW, lessThanOrEqualTo(defaultW));
      expect(minH, lessThanOrEqualTo(defaultH));
    });
  });

  group('TachometerStageWidget — signal binding contract', () {
    test('declares exactly three required signal bindings: '
        'rpm, redline, shift — verbatim names match Rive state-machine '
        'inputs', () {
      const w = TachometerStageWidget();
      final names = w.requiredSignals.map((b) => b.name).toList();
      expect(names, hasLength(3));
      expect(names, containsAll(['rpm', 'redline', 'shift']));
    });

    test('declares no optional signals', () {
      const w = TachometerStageWidget();
      expect(w.optionalSignals, isEmpty);
    });

    test('redline + shift bindings declare bitWidth=1 (boolean)', () {
      const w = TachometerStageWidget();
      for (final name in const ['redline', 'shift']) {
        final binding = w.requiredSignals.firstWhere((b) => b.name == name);
        expect(
          binding.bitWidth,
          1,
          reason:
              '$name maps to a Rive BooleanInput per the binding contract '
              'type-routing table; restricting to 1 bit prevents '
              'accidental wide-bus binding',
        );
      }
    });

    test(
      'rpm binding declares bitWidth=null so any width is allowed; '
      'per-instance config overrides the manifest range at render time',
      () {
        const w = TachometerStageWidget();
        final rpm = w.requiredSignals.firstWhere((b) => b.name == 'rpm');
        expect(rpm.bitWidth, isNull);
      },
    );
  });

  group('TachometerStageWidget — config schema', () {
    test('declares two ConfigParamGroups (range, zones)', () {
      const w = TachometerStageWidget();
      final groupIds = w.configGroups.map((g) => g.id).toList();
      expect(groupIds, ['tachometer.range', 'tachometer.zones']);
    });

    test('every configParam belongs to a declared group', () {
      const w = TachometerStageWidget();
      final declaredGroupIds = w.configGroups.map((g) => g.id).toSet();
      for (final p in w.configParams) {
        expect(
          declaredGroupIds,
          contains(p.groupId),
          reason: 'param ${p.id} has unknown groupId ${p.groupId}',
        );
      }
    });

    test('minRpm + maxRpm are bounded integers in the range group', () {
      const w = TachometerStageWidget();
      final minRpm = w.configParams.firstWhere((p) => p.id == 'minRpm');
      final maxRpm = w.configParams.firstWhere((p) => p.id == 'maxRpm');
      expect(minRpm.type, ConfigParamType.integer);
      expect(maxRpm.type, ConfigParamType.integer);
      expect(minRpm.groupId, 'tachometer.range');
      expect(maxRpm.groupId, 'tachometer.range');
      expect(minRpm.min, 0);
      expect(maxRpm.max, 30000);
    });

    test('warningRpm + redlineRpm sit in the zones group', () {
      const w = TachometerStageWidget();
      for (final id in const ['warningRpm', 'redlineRpm']) {
        final p = w.configParams.firstWhere((p) => p.id == id);
        expect(p.groupId, 'tachometer.zones');
        expect(p.type, ConfigParamType.integer);
      }
    });

    test('default values match the documented automotive modal defaults', () {
      const w = TachometerStageWidget();
      final byId = {for (final p in w.configParams) p.id: p};
      expect(byId['minRpm']!.defaultValue, 0);
      expect(byId['maxRpm']!.defaultValue, 8000);
      expect(byId['warningRpm']!.defaultValue, 6500);
      expect(byId['redlineRpm']!.defaultValue, 7500);
    });
  });
}
