// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/menu_layout.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

const ShortcutAction _action = ShortcutAction.aiAdvisorTogglePanel;

ActionContext _ctx({bool aiAvailable = false, bool fileLoaded = true}) =>
    ActionContext(
      fileLoaded: fileLoaded,
      deviceClass: DeviceClass.desktop,
      aiAvailable: aiAvailable,
    );

void main() {
  group('AI Waveform Assistant action gating', () {
    test(
      'is Pro-tier (renders PRO badge) and lives in menu/overflow/palette',
      () {
        final d = descriptorFor(_action);
        expect(d.requiredTier, LicenseTier.pro);
        expect(d.surfaces, contains(ActionSurface.palette));
        expect(d.surfaces, contains(ActionSurface.menu));
        expect(d.surfaces, contains(ActionSurface.overflow));
        // No keyboard binding / toolbar slot — palette + menu only.
        expect(d.surfaces, isNot(contains(ActionSurface.toolbar)));
      },
    );

    test('hidden everywhere when experimental AI is off', () {
      final ctx = _ctx();
      expect(isActionVisibleIn(_action, ActionSurface.menu, ctx), isFalse);
      expect(isActionVisibleIn(_action, ActionSurface.palette, ctx), isFalse);
      expect(paletteActionsFor(ctx), isNot(contains(_action)));
    });

    test('visible (and enabled) when experimental AI is on', () {
      final ctx = _ctx(aiAvailable: true);
      expect(isActionVisibleIn(_action, ActionSurface.menu, ctx), isTrue);
      expect(isActionEnabled(_action, ctx), isTrue);
      expect(paletteActionsFor(ctx), contains(_action));
    });

    test('placed in the Tools menu group', () {
      final placed = <ShortcutAction>{
        for (final groups in kMenuLayout.values)
          for (final group in groups) ...group,
      };
      expect(placed, contains(_action));
      expect(_action.category, ActionCategory.tools);
    });
  });
}
