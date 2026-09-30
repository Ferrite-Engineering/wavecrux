// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Thrown when a Rive-backed Stage widget fails to load: its asset is missing
/// or malformed, or its state machine lacks what the manifest binds to.
///
/// Every Rive renderer — the Tachometer, the community bundle renderer and the
/// Pro overlay's animated widgets — catches it and surfaces [userMessageKey]
/// through the localized "Widget failed to load" placeholder, with
/// [diagnostic] in the info-icon tooltip.
class StageWidgetRuntimeException implements Exception {
  const StageWidgetRuntimeException({
    required this.userMessageKey,
    required this.diagnostic,
  });

  /// Discriminator the renderer maps to a localized ARB string.
  final StageWidgetRuntimeFailureKind userMessageKey;

  /// Detailed diagnostic shown in the info-icon tooltip (and logged).
  final String diagnostic;

  @override
  String toString() =>
      'StageWidgetRuntimeException(kind: $userMessageKey, '
      'diagnostic: $diagnostic)';
}

/// Discriminator for the "Widget failed to load" placeholder's tooltip.
enum StageWidgetRuntimeFailureKind {
  /// Manifest or asset file is missing on disk.
  assetMissing,

  /// Manifest or asset file is present but cannot be parsed.
  assetMalformed,

  /// Manifest references a state machine that does not exist in the
  /// loaded `.riv` artboard.
  stateMachineMissing,

  /// Manifest declares an input that the underlying animation does not
  /// expose.
  inputUndeclared,

  /// Generic runtime error not covered by the more specific kinds.
  generic,
}
