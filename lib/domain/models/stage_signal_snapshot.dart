// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Lifecycle state of a [StageSignalSnapshot].
enum StageSignalSnapshotKind {
  /// The user has not bound this pin to a waveform signal.
  unbound,

  /// No waveform file is loaded.
  noFile,

  /// Signal data is being lazily loaded.
  loading,

  /// The signal is loaded but has no recorded value at or before cursor time.
  unknown,

  /// The bound signal could not be loaded — e.g. the binding references a
  /// signal that is not present in the current waveform, or the data source
  /// rejected the ref. Distinct from [unknown] (loaded, but no value yet) and
  /// from [noFile] (nothing loaded at all): the file is open, but *this* pin's
  /// load failed. Renderers treat it as a non-value state.
  error,

  /// A raw value is available.
  value,
}

/// Snapshot of one bound Stage-widget pin at the current cursor time.
///
/// Stage widgets receive a [StageSignalSnapshot] for each of their declared
/// [SignalBinding]s. The snapshot exposes the raw VCD bit-string, the parsed
/// numeric interpretation, and explicit X/Z flags so that renderers can show
/// distinct visuals for unknown / high-impedance values without re-parsing.
///
/// Pure Dart — no Flutter imports.
@immutable
class StageSignalSnapshot {
  const StageSignalSnapshot._(
    this.kind, {
    this.rawValue = '',
    this.bitWidth = 0,
    this.isReal = false,
    this.errorMessage = '',
  });

  /// The pin is unbound.
  const StageSignalSnapshot.unbound() : this._(StageSignalSnapshotKind.unbound);

  /// No waveform file is open.
  const StageSignalSnapshot.noFile() : this._(StageSignalSnapshotKind.noFile);

  /// Signal data is loading asynchronously.
  const StageSignalSnapshot.loading() : this._(StageSignalSnapshotKind.loading);

  /// Signal is loaded but has no value at or before cursor time.
  const StageSignalSnapshot.unknown() : this._(StageSignalSnapshotKind.unknown);

  /// The bound signal could not be loaded. [message] is a diagnostic string
  /// (e.g. the data-source error) for tooltips / logs; renderers key off
  /// [kind] / [isError], not the message text.
  const StageSignalSnapshot.error([String message = ''])
    : this._(StageSignalSnapshotKind.error, errorMessage: message);

  /// A concrete value is available.
  const StageSignalSnapshot.value({
    required String rawValue,
    required int bitWidth,
    bool isReal = false,
  }) : this._(
         StageSignalSnapshotKind.value,
         rawValue: rawValue,
         bitWidth: bitWidth,
         isReal: isReal,
       );

  /// Lifecycle state.
  final StageSignalSnapshotKind kind;

  /// Raw VCD bit-string (e.g. `"1010xz"`, `"b0101"`, `"r3.14"`). Empty when
  /// [kind] is not [StageSignalSnapshotKind.value].
  final String rawValue;

  /// Declared signal width, or `0` for real-typed signals.
  final int bitWidth;

  /// True for real / floating-point signals (`$var real`, etc.).
  final bool isReal;

  /// Diagnostic message when [kind] is [StageSignalSnapshotKind.error]; empty
  /// otherwise.
  final String errorMessage;

  /// True when this snapshot represents a pin that has been bound to a signal,
  /// regardless of whether a value is yet available.
  bool get isBound => kind != StageSignalSnapshotKind.unbound;

  /// True when the bound signal failed to load.
  bool get isError => kind == StageSignalSnapshotKind.error;

  /// True when [rawValue] is populated.
  bool get hasValue => kind == StageSignalSnapshotKind.value;

  /// Lower-cased bit-string with the VCD `b` / `r` prefix stripped.
  String get cleanBits {
    if (!hasValue) return '';
    var s = rawValue.toLowerCase();
    if (s.startsWith('b')) s = s.substring(1);
    if (s.startsWith('r')) s = s.substring(1);
    return s;
  }

  /// True when any bit is unknown (`x`).
  bool get hasX => hasValue && cleanBits.contains('x');

  /// True when any bit is high-impedance (`z`) and no bits are unknown.
  bool get hasZ => hasValue && !hasX && cleanBits.contains('z');

  /// Parsed unsigned integer interpretation. Null when [hasX], [hasZ],
  /// [isReal], or no value is available. Pure binary parse — no sign
  /// extension. For 1-bit scalars this returns `0` or `1`.
  BigInt? get intValue {
    if (!hasValue || hasX || hasZ || isReal) return null;
    final bits = cleanBits;
    if (bits.isEmpty) return null;
    // Reject any non-bit characters (real numbers slip through here when the
    // signal type is mis-declared upstream).
    for (final code in bits.codeUnits) {
      if (code != 0x30 && code != 0x31) return null;
    }
    return BigInt.parse(bits, radix: 2);
  }

  /// Parsed numeric value as `double` for renderers that work in real space
  /// (gauges, signal graphs). Returns null on X/Z values.
  ///
  /// For real-typed signals this parses the float string. For integer
  /// signals this converts [intValue] to `double` (loses precision above
  /// 2⁵³).
  double? get realValue {
    if (!hasValue || hasX || hasZ) return null;
    if (isReal) {
      final s = rawValue.toLowerCase().startsWith('r')
          ? rawValue.substring(1)
          : rawValue;
      return double.tryParse(s);
    }
    final iv = intValue;
    return iv?.toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageSignalSnapshot &&
          kind == other.kind &&
          rawValue == other.rawValue &&
          bitWidth == other.bitWidth &&
          isReal == other.isReal &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      Object.hash(kind, rawValue, bitWidth, isReal, errorMessage);

  @override
  String toString() =>
      'StageSignalSnapshot($kind, raw: "$rawValue", w: $bitWidth, '
      'real: $isReal, error: "$errorMessage")';
}
