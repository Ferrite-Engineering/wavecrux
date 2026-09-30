// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One sample of a raw waveform signal at a specific simulation time, fed
/// into a [ValueNormalizer] to produce an animation-ready
/// [NormalizedValue].
///
/// The Stage Pro normalization framework operates on this lightweight,
/// pure-Dart representation rather than reaching into the open-core
/// `SignalValue`/`WaveformDataSource` types directly. The decoupling lets
/// the framework be unit-tested without a `WidgetTester`, a Riverpod
/// container, or an FFI-loaded waveform — fixtures can simply construct
/// instances inline.
///
/// **Field semantics:**
/// - [rawValue] is the raw VCD bit-string for vectors and scalars
///   (e.g. `"11110000"`, `"x"`, `"z"`, `"10x101"`). For real-valued analog
///   signals it is the textual representation of the double, matching
///   `WaveformDataSource.valueAt`. Case-insensitive `x`/`z`/`X`/`Z` are
///   accepted.
/// - [bitWidth] is the declared bit-width of the underlying variable. For
///   scalars this is `1`; for analog/real signals callers may pass `0` to
///   mean "real-valued, width is irrelevant".
/// - [timeTicks] is the simulation time in raw timescale ticks (the same
///   integer the cursor providers use). Normalizers that do not depend on
///   time (the common case) ignore it; sliding-window or
///   time-derivative normalizers consume it.
/// - [isAnalog] hints to numeric normalizers that [rawValue] should be
///   parsed as a double rather than a bit string. Bit-field normalizers
///   reject analog samples explicitly.
///
/// Pure data class. Immutable. No Flutter imports.
@immutable
class RawSignalSample {
  /// Creates a sample bound to the given [rawValue] / [bitWidth] /
  /// [timeTicks].
  ///
  /// [bitWidth] must be `>= 0`; passing `0` flags an analog/real-valued
  /// sample where bit-width is meaningless.
  const RawSignalSample({
    required this.rawValue,
    required this.bitWidth,
    this.timeTicks = 0,
    this.isAnalog = false,
  }) : assert(bitWidth >= 0, 'bitWidth must be non-negative');

  /// Raw VCD bit-string (or numeric text for analog samples).
  final String rawValue;

  /// Declared bit width of the underlying variable (`0` for analog / real).
  final int bitWidth;

  /// Simulation time in raw ticks. Defaults to `0` for time-agnostic
  /// callers / fixtures.
  final int timeTicks;

  /// True if the sample's [rawValue] should be parsed as a real-number
  /// double instead of a VCD bit-string.
  final bool isAnalog;

  /// True if any character in [rawValue] is `x` or `X`.
  bool get hasX => rawValue.contains(RegExp('[xX]'));

  /// True if any character in [rawValue] is `z` or `Z` and there are no
  /// `x` characters. Mirrors the "X dominates Z" precedence used by
  /// `SignalValue` in open-core.
  bool get hasZ => !hasX && rawValue.contains(RegExp('[zZ]'));

  RawSignalSample copyWith({
    String? rawValue,
    int? bitWidth,
    int? timeTicks,
    bool? isAnalog,
  }) => RawSignalSample(
    rawValue: rawValue ?? this.rawValue,
    bitWidth: bitWidth ?? this.bitWidth,
    timeTicks: timeTicks ?? this.timeTicks,
    isAnalog: isAnalog ?? this.isAnalog,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawSignalSample &&
          rawValue == other.rawValue &&
          bitWidth == other.bitWidth &&
          timeTicks == other.timeTicks &&
          isAnalog == other.isAnalog;

  @override
  int get hashCode => Object.hash(rawValue, bitWidth, timeTicks, isAnalog);

  @override
  String toString() =>
      'RawSignalSample(rawValue: $rawValue, bitWidth: $bitWidth, '
      'timeTicks: $timeTicks, isAnalog: $isAnalog)';
}
