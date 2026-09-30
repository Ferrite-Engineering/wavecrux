// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Whether a translated value is fully known, or carries unknown (`x`) or
/// high-impedance (`z`) bits.
///
/// The built-in translator surfaces this directly from the raw bit-string so
/// the UI no longer has to re-scan the formatted text to discover x/z state.
/// (Today that information is baked into the formatted string — e.g. `"X"` /
/// `"Z"` — which is preserved unchanged; this enum exposes it as structured
/// metadata alongside the text.)
enum ValueValidity {
  /// All bits known — a normal value.
  ok,

  /// At least one bit is unknown (`x`).
  hasX,

  /// At least one bit is high-impedance (`z`) and none are unknown.
  hasZ,
}
