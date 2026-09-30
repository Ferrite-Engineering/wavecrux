// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Why the loader did or did not surface a discovered decoder plugin.
///
/// Reported per discovered shared library in
/// [DecoderPluginInfo.loadStatus]; the Settings → Decoders → Plugins
/// panel renders one row per discovered plugin with a colored chip
/// matching this state.
enum DecoderPluginLoadStatus {
  /// The plugin's ABI version matched, registration succeeded, and its
  /// decoders are live in the registry.
  loaded,

  /// The plugin reported an ABI version whose major component differs
  /// from the host's. The plugin is not loaded; the user is told to
  /// rebuild against the current header.
  abiMismatch,

  /// Loading the shared library succeeded but a required entry point
  /// (`wavecrux_decoder_abi_version` or `wavecrux_decoder_register`)
  /// could not be resolved.
  missingSymbol,

  /// The plugin registered, but its JSON manifest failed validation
  /// (malformed JSON, missing required keys, unknown signal kinds).
  manifestInvalid,

  /// `dlopen` / `LoadLibrary` failed outright, or the plugin threw
  /// during registration. The detailed cause is in
  /// [DecoderPluginInfo.errorMessage].
  loadError,

  /// The user explicitly disabled this plugin in Settings. The plugin
  /// was discovered but never loaded.
  disabled,

  /// The organization's policy file lists approved plugins by content hash,
  /// and this file's hash is not among them.
  ///
  /// **Distinct from [disabled], which is the user's own choice.** This one is
  /// the organization's, it cannot be overridden from Settings, and the UI has
  /// to say so — a refusal a user believes they can toggle is a support ticket
  /// that ends in "you cannot".
  notAllowlisted,
}
