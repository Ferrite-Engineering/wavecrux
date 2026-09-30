// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Enumerations referenced by [StageWidgetManifest] and its sub-models.
///
/// The Stage Pro manifest format speaks declarative YAML; these enums are
/// the strongly-typed Dart parallel of the string discriminators that
/// appear in the YAML on disk. Each has a `wireName` getter (the canonical
/// spelling that appears in YAML) and a static `fromWire` lookup that the
/// parser uses when validating manifest input.
library;

/// Direction of a manifest signal binding. Almost always [input] for
/// rendering widgets; [output] is reserved for future bidirectional
/// widgets (e.g. a touch overlay that injects events back into a
/// streaming VCD).
enum BindingDirection {
  input,
  output;

  String get wireName => name;

  static BindingDirection? fromWire(String value) {
    for (final v in values) {
      if (v.wireName == value) return v;
    }
    return null;
  }
}

/// Logical type of a manifest signal binding. Drives parser validation
/// (bit-width hints), normalizer applicability, and Stage-panel binding-
/// dialog UX.
enum SignalType {
  /// 1-bit logical signal.
  scalar,

  /// Multi-bit bus with declared bit-width.
  vector,

  /// Real-valued numeric signal (`$var real`). Cannot be sliced by
  /// [BitFieldNormalizer].
  analog,

  /// A named group of signals treated as a single binding (e.g. an SPI
  /// `{mosi, miso, sclk, cs}` quad). The binding consumer iterates the
  /// member signals at render time.
  busGroup;

  /// Wire name in YAML matches the snake-case form
  /// (`scalar`, `vector`, `analog`, `bus_group`).
  String get wireName {
    switch (this) {
      case SignalType.busGroup:
        return 'bus_group';
      case SignalType.scalar:
      case SignalType.vector:
      case SignalType.analog:
        return name;
    }
  }

  static SignalType? fromWire(String value) {
    for (final v in values) {
      if (v.wireName == value) return v;
    }
    return null;
  }
}

/// What the runtime should do with a [ManifestSignalBinding] that the
/// user has not bound to an actual waveform signal at render time.
enum DefaultPolicy {
  /// Hold the previously sampled value (default for most analog widgets).
  holdLast,

  /// Treat unbound samples as `0` / `false`.
  treatAsZero,

  /// Treat unbound samples as `X` (renders as hatched / indeterminate).
  treatAsX;

  String get wireName {
    switch (this) {
      case DefaultPolicy.holdLast:
        return 'hold_last';
      case DefaultPolicy.treatAsZero:
        return 'treat_as_zero';
      case DefaultPolicy.treatAsX:
        return 'treat_as_x';
    }
  }

  static DefaultPolicy? fromWire(String value) {
    for (final v in values) {
      if (v.wireName == value) return v;
    }
    return null;
  }
}

/// Animation runtime declared by a manifest. Picked at load time to
/// route into the matching renderer adapter.
enum ManifestRuntime {
  /// Rive (.riv) animation bundle.
  rive,

  /// Custom Flutter `CustomPainter` registered by the bundle code.
  painter;

  String get wireName => name;

  static ManifestRuntime? fromWire(String value) {
    for (final v in values) {
      if (v.wireName == value) return v;
    }
    return null;
  }
}
