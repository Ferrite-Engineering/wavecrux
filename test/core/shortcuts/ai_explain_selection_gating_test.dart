// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

const ShortcutAction _action = ShortcutAction.aiExplainSelection;

ActionContext _ctx({
  bool aiAvailable = false,
  bool aiModelConfigured = false,
  bool hasSelection = false,
  bool fileLoaded = true,
}) => ActionContext(
  fileLoaded: fileLoaded,
  deviceClass: DeviceClass.desktop,
  aiAvailable: aiAvailable,
  aiModelConfigured: aiModelConfigured,
  hasSelection: hasSelection,
);

void main() {
  group('Explain Selection action gating', () {
    test('is open-core (no tier badge) and lives in menu/overflow/palette', () {
      final d = descriptorFor(_action);
      expect(d.requiredTier.name, 'openCore');
      expect(d.surfaces, contains(ActionSurface.palette));
      expect(d.surfaces, contains(ActionSurface.menu));
    });

    test('hidden everywhere when experimental AI is off', () {
      final ctx = _ctx(
        aiModelConfigured: true,
        hasSelection: true,
      );
      expect(isActionVisibleIn(_action, ActionSurface.menu, ctx), isFalse);
      expect(isActionVisibleIn(_action, ActionSurface.palette, ctx), isFalse);
      expect(paletteActionsFor(ctx), isNot(contains(_action)));
    });

    test('visible but DISABLED when AI on but no model configured', () {
      final ctx = _ctx(aiAvailable: true, hasSelection: true);
      expect(isActionVisibleIn(_action, ActionSurface.menu, ctx), isTrue);
      expect(isActionEnabled(_action, ctx), isFalse);
      // The palette omits disabled actions.
      expect(paletteActionsFor(ctx), isNot(contains(_action)));
    });

    test('visible but DISABLED when AI on + model, but no selection', () {
      final ctx = _ctx(aiAvailable: true, aiModelConfigured: true);
      expect(isActionVisibleIn(_action, ActionSurface.menu, ctx), isTrue);
      expect(isActionEnabled(_action, ctx), isFalse);
    });

    test(
      'visible but DISABLED when AI on + model + selection, but no file',
      () {
        final ctx = _ctx(
          aiAvailable: true,
          aiModelConfigured: true,
          hasSelection: true,
          fileLoaded: false,
        );
        expect(isActionEnabled(_action, ctx), isFalse);
      },
    );

    test(
      'visible AND enabled (and in the palette) with all gates satisfied',
      () {
        final ctx = _ctx(
          aiAvailable: true,
          aiModelConfigured: true,
          hasSelection: true,
        );
        expect(isActionVisibleIn(_action, ActionSurface.menu, ctx), isTrue);
        expect(isActionEnabled(_action, ctx), isTrue);
        expect(paletteActionsFor(ctx), contains(_action));
      },
    );
  });
}
