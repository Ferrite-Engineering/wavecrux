// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';

/// A selectable keyboard-binding preset.
///
/// A preset is a *named, complete* binding map the user can load wholesale from
/// Settings → Keyboard Shortcuts. Loading one replaces all bindings (persisted
/// as the usual diff-from-default), after which the user can still tweak
/// individual rows — at which point the active preset reads as "Custom".
///
/// Presets are an additive convenience layered on the existing
/// `.crux-keymap` import/export: [waveCrux] is the shipped default, and
/// [gtkwave] eases migration for engineers coming from GTKWave by honoring the
/// GTKWave accelerators that map onto an existing WaveCrux action.
enum KeymapPreset {
  /// WaveCrux's own platform-aware defaults ([defaultBindings]).
  waveCrux,

  /// GTKWave-flavored bindings for migrating users. See [_gtkwaveBindings] for
  /// the exact delta and the rationale for what is and isn't remapped.
  gtkwave,
}

/// Returns the complete resolved binding map for [preset].
///
/// The result is a full `ShortcutAction → ShortcutActivator` map (same shape as
/// [defaultBindings]); apply it via `ShortcutBindingsNotifier.applyPreset`.
Map<ShortcutAction, ShortcutActivator> bindingsForPreset(KeymapPreset preset) {
  switch (preset) {
    case KeymapPreset.waveCrux:
      return defaultBindings();
    case KeymapPreset.gtkwave:
      return _gtkwaveBindings();
  }
}

/// Identifies which preset [bindings] exactly matches, or `null` ("Custom")
/// when the user has diverged from every shipped preset.
///
/// Compares activators *by value* via [KeyBindingResolver.activatorsEqual] —
/// Flutter's [SingleActivator] has no `==`, so identity/`mapEquals` comparison
/// would never match two independently-built default maps.
KeymapPreset? presetForBindings(
  Map<ShortcutAction, ShortcutActivator> bindings,
) {
  for (final preset in KeymapPreset.values) {
    if (_bindingsEqual(bindingsForPreset(preset), bindings)) return preset;
  }
  return null;
}

/// Value equality for two resolved binding maps (same keys, activators equal by
/// trigger + modifiers).
bool _bindingsEqual(
  Map<ShortcutAction, ShortcutActivator> a,
  Map<ShortcutAction, ShortcutActivator> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (!KeyBindingResolver.activatorsEqual(entry.value, b[entry.key])) {
      return false;
    }
  }
  return true;
}

/// GTKWave-compatible bindings.
///
/// WaveCrux and GTKWave already share the standard-desktop "spine" by
/// convention — Open (Ctrl+O), Save (Ctrl+S), Save As (Ctrl+Shift+S), New Tab
/// (Ctrl+T), Close (Ctrl+W), Quit (Ctrl+Q), Zoom In/Out (Ctrl+= / Ctrl+−),
/// Zoom Full (Ctrl+0), Jump to End (End). Those need no remap and are inherited
/// from [defaultBindings] unchanged.
///
/// This preset therefore only overrides the genuine GTKWave-isms that land on
/// an existing, globally-handled WaveCrux action (verified against
/// `gtkwave/src/menu.c`):
///
/// | Action                  | GTKWave menu             | Key    |
/// |-------------------------|--------------------------|--------|
/// | openSearch              | Signal Search Regexp     | Alt+S  |
/// | exportWaveform          | Print To File            | Ctrl+P |
/// | setFormatHexadecimal    | Data Format / Hex        | Alt+X  |
/// | setFormatUnsignedDecimal| Data Format / Decimal    | Alt+D  |
/// | setFormatBinary         | Data Format / Binary     | Alt+B  |
/// | setFormatOctal          | Data Format / Octal      | Alt+O  |
///
/// Deliberately NOT remapped:
/// - **Markers** (GTKWave Alt+M / Alt+N): GTKWave drops a marker immediately;
///   WaveCrux's `M` / `⇧M` are two-key chord arms (the next a–z names it). The
///   mechanics differ, so WaveCrux's marker keys are kept.
/// - **Paging** (GTKWave Alt+7 / Alt+8): GTKWave navigation is overwhelmingly
///   mouse-wheel driven; the "mouse wheel navigates time" setting
///   (`wheelNavigatesTime`) replicates that reflex far better than a key.
/// - **Reload** (GTKWave Shift+Ctrl+R): WaveCrux auto-reloads on file change,
///   so there is no reload action to bind.
/// - **Ctrl+F**: GTKWave binds it to "Show-Change First Highlighted" (no
///   WaveCrux equivalent). Moving search to Alt+S frees Ctrl+F rather than
///   colliding with it.
Map<ShortcutAction, ShortcutActivator> _gtkwaveBindings() {
  final isMac =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return Map<ShortcutAction, ShortcutActivator>.of(defaultBindings())..addAll({
    // Signal search — GTKWave "Signal Search Regexp" (Alt+S). Frees Ctrl+F.
    ShortcutAction.openSearch: const SingleActivator(
      LogicalKeyboardKey.keyS,
      alt: true,
    ),
    // Export — GTKWave "Print To File" (Ctrl+P). Frees Ctrl+E.
    ShortcutAction.exportWaveform: SingleActivator(
      LogicalKeyboardKey.keyP,
      meta: isMac,
      control: !isMac,
    ),
    // Data-format cycling on the selected signal(s) — GTKWave Alt+X/D/B/O.
    // These are unbound by default in WaveCrux (context-menu only); the
    // preset surfaces them on the GTKWave accelerators.
    ShortcutAction.setFormatHexadecimal: const SingleActivator(
      LogicalKeyboardKey.keyX,
      alt: true,
    ),
    ShortcutAction.setFormatUnsignedDecimal: const SingleActivator(
      LogicalKeyboardKey.keyD,
      alt: true,
    ),
    ShortcutAction.setFormatBinary: const SingleActivator(
      LogicalKeyboardKey.keyB,
      alt: true,
    ),
    ShortcutAction.setFormatOctal: const SingleActivator(
      LogicalKeyboardKey.keyO,
      alt: true,
    ),
  });
}
