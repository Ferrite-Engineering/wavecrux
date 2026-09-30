// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';

/// A variable (signal) in the design hierarchy.
///
/// [signalRef] is an opaque identifier used to load and query this variable's
/// waveform data through [WaveformDataSource]. For the FFI backend it is the
/// stringified `u32` signal handle; for the pure-Dart parser it is the VCD
/// identifier code.
@immutable
class Variable {
  const Variable({
    required this.name,
    required this.varType,
    required this.direction,
    required this.signalRef,
    required this.scopePath,
    this.bitWidth,
  });

  /// Local (unqualified) signal name, e.g. `"clk"`.
  final String name;

  /// HDL variable type (wire, reg, logic, std_logic, …).
  final VarType varType;

  /// Port direction (`unknown` for signals without direction info, e.g. VCD).
  final VarDirection direction;

  /// Opaque signal reference used for [WaveformDataSource] load/query calls.
  final String signalRef;

  /// Full hierarchical path of the containing scope, e.g. `"top.cpu"`.
  ///
  /// Empty string for variables at the top level.
  final String scopePath;

  /// Bit-width of the variable, or `null` for real-valued / string signals.
  final int? bitWidth;

  // ── computed ───────────────────────────────────────────────────────────────

  /// Full hierarchical path including this variable's name,
  /// e.g. `"top.cpu.clk"`.
  String get fullPath => scopePath.isEmpty ? name : '$scopePath.$name';

  /// Whether this variable is a bit-vector (has a defined [bitWidth]).
  bool get isBitVector => bitWidth != null;

  /// Whether this variable holds a real (floating-point) value.
  bool get isReal =>
      varType == VarType.real ||
      varType == VarType.realTime ||
      varType == VarType.svShortReal ||
      varType == VarType.realParameter;

  // ── copyWith ───────────────────────────────────────────────────────────────

  Variable copyWith({
    String? name,
    VarType? varType,
    VarDirection? direction,
    String? signalRef,
    String? scopePath,
    int? bitWidth,
    bool clearBitWidth = false,
  }) => Variable(
    name: name ?? this.name,
    varType: varType ?? this.varType,
    direction: direction ?? this.direction,
    signalRef: signalRef ?? this.signalRef,
    scopePath: scopePath ?? this.scopePath,
    bitWidth: clearBitWidth ? null : (bitWidth ?? this.bitWidth),
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Variable &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          varType == other.varType &&
          direction == other.direction &&
          signalRef == other.signalRef &&
          scopePath == other.scopePath &&
          bitWidth == other.bitWidth;

  /// Hash on the fields that uniquely identify a variable within a waveform.
  @override
  int get hashCode => Object.hash(name, scopePath, signalRef);

  @override
  String toString() =>
      'Variable(fullPath: $fullPath, varType: $varType, bitWidth: $bitWidth)';
}
