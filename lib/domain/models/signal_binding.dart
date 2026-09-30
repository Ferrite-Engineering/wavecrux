// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Declares one logical signal input that a protocol decoder expects to be
/// bound to an actual waveform signal.
///
/// For example, an SPI decoder declares bindings named `"mosi"`, `"miso"`,
/// `"sclk"`, and `"cs"`. The user maps each of these names to a real signal
/// path from the loaded waveform.
@immutable
class SignalBinding {
  const SignalBinding({
    required this.name,
    required this.description,
    this.bitWidth,
    this.visibleWhenKey,
    this.visibleWhenValue,
    this.visibleWhenValues,
  }) : assert(
         visibleWhenValue == null || visibleWhenValues == null,
         'set at most one of visibleWhenValue / visibleWhenValues',
       );

  /// Logical name used by the decoder (e.g. `"mosi"`, `"cs"`).
  final String name;

  /// Human-readable explanation of what this signal does in the protocol.
  final String description;

  /// Expected bit-width of the bound signal, or `null` to accept any width.
  final int? bitWidth;

  /// Conditional visibility, mirroring `ConfigParam.visibleWhenKey`: when set,
  /// a pin-enumerating surface (the Stage bindings pane) renders this pin only
  /// when the owning instance's `configuration[visibleWhenKey]` matches
  /// [visibleWhenValue] (single-value equality) or is a member of
  /// [visibleWhenValues] (OR-of-discrete-values), whichever is supplied.
  ///
  /// Exists so a widget whose pin count is itself configurable — the RISC-V
  /// Pipeline Diagram declares name / valid / stall / flush pins for up to
  /// eight stages — does not permanently show pins for stages the user has
  /// not enabled. A binding with no predicate is always visible, so every
  /// pre-existing widget is unaffected.
  ///
  /// Deliberately as limited and const-friendly as the `ConfigParam` contract
  /// it mirrors: discrete equality only, no comparisons and no cross-field
  /// boolean logic. A widget that needs richer predicates supplies a custom
  /// editor instead of growing this into an arbitrary predicate.
  final String? visibleWhenKey;

  /// Visibility comparison value paired with [visibleWhenKey]. Compared with
  /// `==` against the live config value. Mutually exclusive with
  /// [visibleWhenValues] — set at most one.
  final Object? visibleWhenValue;

  /// Visibility comparison set paired with [visibleWhenKey], for a pin that
  /// stays visible across more than one (but not all) values of a key — e.g.
  /// stage 5's pins are visible when the stage count is any of 5..8.
  /// Mutually exclusive with [visibleWhenValue] — set at most one.
  final Set<Object?>? visibleWhenValues;

  // ── computed ───────────────────────────────────────────────────────────────

  /// Whether [config] currently satisfies this pin's visibility predicate.
  /// Returns `true` when no predicate is set.
  bool isVisibleIn(Map<String, Object?> config) {
    if (visibleWhenKey == null) return true;
    final values = visibleWhenValues;
    if (values != null) return values.contains(config[visibleWhenKey]);
    return config[visibleWhenKey] == visibleWhenValue;
  }

  // ── copyWith ───────────────────────────────────────────────────────────────

  SignalBinding copyWith({
    String? name,
    String? description,
    int? bitWidth,
    bool clearBitWidth = false,
    String? visibleWhenKey,
    Object? visibleWhenValue,
    Set<Object?>? visibleWhenValues,
    bool clearVisibleWhen = false,
  }) => SignalBinding(
    name: name ?? this.name,
    description: description ?? this.description,
    bitWidth: clearBitWidth ? null : (bitWidth ?? this.bitWidth),
    visibleWhenKey: clearVisibleWhen
        ? null
        : (visibleWhenKey ?? this.visibleWhenKey),
    visibleWhenValue: clearVisibleWhen
        ? null
        : (visibleWhenValue ?? this.visibleWhenValue),
    visibleWhenValues: clearVisibleWhen
        ? null
        : (visibleWhenValues ?? this.visibleWhenValues),
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalBinding &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          description == other.description &&
          bitWidth == other.bitWidth &&
          visibleWhenKey == other.visibleWhenKey &&
          visibleWhenValue == other.visibleWhenValue &&
          _setEquals(visibleWhenValues, other.visibleWhenValues);

  @override
  int get hashCode => Object.hash(
    name,
    description,
    bitWidth,
    visibleWhenKey,
    visibleWhenValue,
    // Order-independent so two equal sets built in different insertion
    // orders still hash the same.
    visibleWhenValues?.fold<int>(0, (acc, v) => acc ^ v.hashCode),
  );

  @override
  String toString() => 'SignalBinding(name: $name, bitWidth: $bitWidth)';

  static bool _setEquals(Set<Object?>? a, Set<Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
