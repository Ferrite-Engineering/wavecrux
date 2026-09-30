// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart' as kb;
import 'package:flutter/widgets.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';

/// WaveCrux-flavored conflict *resolution*: delegates to the cross-suite
/// `resolveShortcutConflicts`, injecting WaveCrux's [defaultBindings] and
/// [ShortcutAction] declaration order (for the deterministic tiebreak).
///
/// Returns both the deterministic runtime activator map
/// ([kb.ShortcutConflictResolution.effectiveBindings] — fed to
/// `ShortcutManagerWidget` so a user-remapped binding wins its chord instead of
/// the enum-declaration-order accident) and the editor's owner/shadowed view.
kb.ShortcutConflictResolution<ShortcutAction> resolveShortcutConflicts(
  Map<ShortcutAction, ShortcutActivator> bindings,
) => kb.resolveShortcutConflicts(
  bindings,
  defaultBindings(),
  order: ShortcutAction.values,
);
