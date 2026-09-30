// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/keymap_presets.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';

void main() {
  // SingleActivator has no value equality, so assert on its properties.
  void expectActivator(
    ShortcutActivator? actual, {
    required LogicalKeyboardKey key,
    bool control = false,
    bool meta = false,
    bool shift = false,
    bool alt = false,
  }) {
    expect(actual, isA<SingleActivator>());
    final a = actual! as SingleActivator;
    expect(a.trigger, key);
    expect(a.control, control);
    expect(a.meta, meta);
    expect(a.shift, shift);
    expect(a.alt, alt);
  }

  String sig(SingleActivator a) =>
      '${a.trigger.keyLabel}|c=${a.control}|m=${a.meta}|s=${a.shift}|a=${a.alt}';

  /// The actions whose binding the GTKWave preset changes from the default.
  const expectedOverrides = {
    ShortcutAction.openSearch,
    ShortcutAction.exportWaveform,
    ShortcutAction.setFormatHexadecimal,
    ShortcutAction.setFormatUnsignedDecimal,
    ShortcutAction.setFormatBinary,
    ShortcutAction.setFormatOctal,
  };

  group('bindingsForPreset', () {
    test('waveCrux preset round-trips through presetForBindings', () {
      // Can't use `equals(defaultBindings())` — SingleActivator has no ==.
      expect(presetForBindings(defaultBindings()), KeymapPreset.waveCrux);
    });

    test('gtkwave preset binds the GTKWave accelerators', () {
      final g = bindingsForPreset(KeymapPreset.gtkwave);
      expectActivator(
        g[ShortcutAction.openSearch],
        key: LogicalKeyboardKey.keyS,
        alt: true,
      );
      expectActivator(
        g[ShortcutAction.setFormatHexadecimal],
        key: LogicalKeyboardKey.keyX,
        alt: true,
      );
      expectActivator(
        g[ShortcutAction.setFormatUnsignedDecimal],
        key: LogicalKeyboardKey.keyD,
        alt: true,
      );
      expectActivator(
        g[ShortcutAction.setFormatBinary],
        key: LogicalKeyboardKey.keyB,
        alt: true,
      );
      expectActivator(
        g[ShortcutAction.setFormatOctal],
        key: LogicalKeyboardKey.keyO,
        alt: true,
      );
      // exportWaveform → primary-accelerator+P. On the test host (non-mac
      // default) that resolves to Ctrl+P.
      expectActivator(
        g[ShortcutAction.exportWaveform],
        key: LogicalKeyboardKey.keyP,
        control: true,
      );
    });

    test('gtkwave preset changes ONLY the documented actions', () {
      final defaults = defaultBindings();
      final g = bindingsForPreset(KeymapPreset.gtkwave);
      final changed = <ShortcutAction>{
        for (final a in ShortcutAction.values)
          if (!KeyBindingResolver.activatorsEqual(defaults[a], g[a])) a,
      };
      expect(changed, equals(expectedOverrides));
    });

    test(
      'gtkwave preset inherits unrelated defaults (quit, fitAll)',
      () {
        final defaults = defaultBindings();
        final g = bindingsForPreset(KeymapPreset.gtkwave);
        for (final a in [
          ShortcutAction.quit,
          ShortcutAction.fitAll,
        ]) {
          expect(
            KeyBindingResolver.activatorsEqual(g[a], defaults[a]),
            isTrue,
            reason: '${a.name} should be inherited unchanged',
          );
        }
      },
    );

    test('gtkwave preset has no chord collisions', () {
      final g = bindingsForPreset(KeymapPreset.gtkwave);
      final bySig = <String, List<ShortcutAction>>{};
      g.forEach((action, activator) {
        bySig
            .putIfAbsent(sig(activator as SingleActivator), () => [])
            .add(action);
      });
      final collisions = [
        for (final e in bySig.entries)
          if (e.value.length > 1)
            '${e.key} → ${e.value.map((a) => a.name).join(', ')}',
      ];
      expect(collisions, isEmpty, reason: collisions.join('\n'));
    });
  });

  group('presetForBindings', () {
    test('identifies the GTKWave map', () {
      expect(
        presetForBindings(bindingsForPreset(KeymapPreset.gtkwave)),
        KeymapPreset.gtkwave,
      );
    });

    test('returns null (Custom) for a hand-edited map', () {
      final custom =
          Map<ShortcutAction, ShortcutActivator>.of(defaultBindings())
            ..[ShortcutAction.openSearch] = const SingleActivator(
              LogicalKeyboardKey.keyJ,
              control: true,
            );
      expect(presetForBindings(custom), isNull);
    });
  });
}
