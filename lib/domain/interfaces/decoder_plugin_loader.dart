// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';

/// Discovers user-contributed decoder plugins and registers their decoders
/// with `DecoderRegistry.instance`.
///
/// Two implementations exist:
///
/// * **Desktop** (`FfiDecoderLoader`) — opens each discovered shared library
///   via `dart:ffi`, validates the ABI version, calls
///   `wavecrux_decoder_register`, and adapts every contributed decoder
///   into the existing registry shape.
/// * **Mobile / Web** (`StubDecoderPluginLoader`) — a no-op that returns
///   an empty plugin list. Runtime native code loading is unavailable
///   on those platforms; the Settings → Decoders → Plugins panel hides
///   itself there.
///
/// Production code obtains a loader through `decoderPluginLoaderProvider`,
/// which selects the platform-appropriate implementation via conditional
/// imports. Tests construct a desktop loader directly.
///
/// **Per-plugin failure isolation is mandatory.** A bad plugin
/// (mismatched ABI, missing entry point, malformed manifest, dlopen
/// crash) MUST log the failure to the `wavecrux.decoders.plugins`
/// `package:logging` Logger and proceed to the next plugin. Not
/// `dart:developer.log`: it emits nothing from a release build, where the
/// Logger reaches the issue reporter and, at SEVERE, stderr.
/// Implementations must never throw past [scan].
abstract class DecoderPluginLoader {
  /// Walks the configured plugin directories, attempts to load every
  /// shared library found, and contributes successfully loaded
  /// decoders to `DecoderRegistry.instance`.
  ///
  /// Returns one [DecoderPluginInfo] per discovered plugin,
  /// regardless of load outcome. The list is also exposed via
  /// `decoderPluginListProvider` so the Settings UI can render
  /// per-plugin status.
  ///
  /// Honors `AppSettings.pluginLoadingDisabled` (returns an empty list
  /// without touching the filesystem) and
  /// `AppSettings.perPluginDisabled` (skips registration for disabled
  /// plugins but still emits a `DecoderPluginInfo` with status
  /// `disabled`).
  ///
  /// Calling [scan] more than once unloads any previously loaded
  /// libraries and re-registers fresh decoder definitions, mirroring
  /// the "Reload plugins" action in the Settings panel.
  Future<List<DecoderPluginInfo>> scan();

  /// Releases every dynamically loaded library and unregisters every
  /// plugin-contributed decoder from `DecoderRegistry.instance`.
  ///
  /// Built-in decoders (registered before any plugins) are not
  /// affected. Safe to call when no plugins are loaded.
  void dispose();
}
