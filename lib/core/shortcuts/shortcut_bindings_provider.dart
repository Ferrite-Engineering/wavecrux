// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';

part 'shortcut_bindings_provider.g.dart';

final _log = Logger('wavecrux.shortcuts');

/// Provides the [KeyBindingsStore] used to persist customizations, configured
/// with WaveCrux's action set + schema (`waveCruxKeymapCodec`).
///
/// Override in tests to inject a `SharedPreferences`-backed store (constructed
/// with `prefsOverride`).
@Riverpod(keepAlive: true)
KeyBindingsStore<ShortcutAction> shortcutBindingsStore(Ref ref) =>
    KeyBindingsStore<ShortcutAction>(codec: waveCruxKeymapCodec);

/// Manages the active key bindings for all [ShortcutAction]s.
///
/// The state is the fully-resolved map of [ShortcutActivator]s the rest of the
/// app consumes (command palette, menu bar, `ShortcutManagerWidget`). It is
/// seeded synchronously from [defaultBindings] so consumers never see a null
/// map, then persisted customizations are overlaid asynchronously once they
/// load from [ShortcutBindingsStore].
///
/// Customizations are stored as **diffs from default** (see [currentDiffs]):
/// only actions the user actually changed are persisted, so a new action added
/// in a later release inherits its fresh default instead of being orphaned.
@Riverpod(keepAlive: true)
class ShortcutBindingsNotifier extends _$ShortcutBindingsNotifier {
  bool _disposed = false;

  /// Set when the stored keymap was written by a newer build. Every save is
  /// then skipped for the rest of the session: this build's diffs would
  /// replace a keymap it cannot read, wiping the user's bindings for the day
  /// they upgrade again.
  bool _storedKeymapIsNewer = false;

  @override
  Map<ShortcutAction, ShortcutActivator> build() {
    ref.onDispose(() => _disposed = true);
    // Overlay persisted customizations once they load; defaults render now.
    unawaited(_restore());
    return defaultBindings();
  }

  Future<void> _restore() async {
    final Map<ShortcutAction, KeyBinding?> diffs;
    try {
      diffs = await ref.read(shortcutBindingsStoreProvider).load();
    } on KeymapSchemaVersionException catch (e) {
      // The store answers every other failure with "no customizations"; this
      // one it refuses loudly so the caller can decline to overwrite it.
      _storedKeymapIsNewer = true;
      _log.warning(
        'Stored keyboard shortcuts come from a newer WaveCrux (${e.message}); '
        'running on defaults and leaving them unsaved this session',
      );
      return;
    }
    if (_disposed || diffs.isEmpty) return;
    state = KeyBindingResolver.resolve(defaultBindings(), diffs);
  }

  /// The current customizations as diffs against the platform defaults,
  /// including explicit unbinds (`null` values). This is what is persisted and
  /// what keymap Export writes.
  Map<ShortcutAction, KeyBinding?> currentDiffs() => KeyBindingResolver.diff(
    ShortcutAction.values,
    state,
    defaultBindings(),
  );

  void _persist() {
    if (_storedKeymapIsNewer) return;
    unawaited(ref.read(shortcutBindingsStoreProvider).save(currentDiffs()));
  }

  /// Sets a custom binding for [action], replacing the current activator.
  void setBinding(ShortcutAction action, ShortcutActivator activator) {
    state = Map<ShortcutAction, ShortcutActivator>.of(state)
      ..[action] = activator;
    _persist();
  }

  /// Removes any binding for [action] (an explicit unbind). No-op when the
  /// action is already unbound.
  void unbind(ShortcutAction action) {
    if (!state.containsKey(action)) return;
    state = Map<ShortcutAction, ShortcutActivator>.of(state)..remove(action);
    _persist();
  }

  /// Resets [action] to its platform default.
  ///
  /// Some actions are intentionally unbound (palette/menu-only, or the
  /// removeMarker picker) and have no entry in [defaultBindings]. Resetting
  /// such an action removes any custom binding rather than throwing on a
  /// missing default.
  void reset(ShortcutAction action) {
    final updated = Map<ShortcutAction, ShortcutActivator>.of(state);
    final defaultActivator = defaultBindings()[action];
    if (defaultActivator == null) {
      updated.remove(action);
    } else {
      updated[action] = defaultActivator;
    }
    state = updated;
    _persist();
  }

  /// Resets all bindings to platform defaults and clears persisted overrides.
  void resetAll() {
    state = defaultBindings();
    _persist();
  }

  /// Replaces all customizations with [diffs] (keymap Import). Actions absent
  /// from [diffs] return to their platform default; `null` values are explicit
  /// unbinds.
  void importDiffs(Map<ShortcutAction, KeyBinding?> diffs) {
    state = KeyBindingResolver.resolve(defaultBindings(), diffs);
    _persist();
  }

  /// Replaces all bindings with a named [preset]'s complete map (e.g. the
  /// GTKWave preset selected in Settings → Keyboard Shortcuts).
  ///
  /// The delta from the platform defaults is persisted via [currentDiffs], so a
  /// preset that equals the defaults stores nothing and one that diverges
  /// stores only its overrides — identical to the Import path. The user can
  /// still edit individual rows afterward.
  void applyPreset(Map<ShortcutAction, ShortcutActivator> preset) {
    state = Map<ShortcutAction, ShortcutActivator>.of(preset);
    _persist();
  }
}
