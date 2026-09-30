// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single signal binding on a Stage widget instance.
///
/// Pairs a waveform signal reference with an optional bit slice for
/// the case where a multi-bit signal is being bound to a sub-slot.
///
/// Three modes:
///
/// - **Whole signal**: [bitIndex] and [bitWidth] both `null`. The
///   bound signal's full value is used as-is. Common case for
///   vector-valued slots (bus readouts, seven-segment hex displays,
///   level bars) and naturally 1-bit signals bound to 1-bit slots.
/// - **Single bit**: [bitIndex] non-null, [bitWidth] `null` (or 1).
///   The slot represents a single bit of the bound vector signal at
///   the given index. Index 0 is the LSB. Used for 16-bit-bus to
///   per-LED fan-outs (`led3` ← bit 3 of `top.dut.led[15:0]`).
/// - **Multi-bit slice**: both [bitIndex] and [bitWidth] non-null
///   with [bitWidth] > 1. The slot consumes a [bitWidth]-wide chunk
///   of the bound vector signal starting at [bitIndex] (LSB).
///   Equivalent Verilog notation: `signalRef[bitIndex+bitWidth-1:bitIndex]`.
///   Used for packed-vector fan-outs like the DE10-Nano's 96-bit
///   `adc_ch` bus split across 8 ADC channel slots, 12 bits each
///   (`adc_ch0` ← `adc_ch[11:0]`, `adc_ch1` ← `adc_ch[23:12]`, …).
///
/// Pure Dart — no Flutter imports.
@immutable
class StageSignalBinding {
  const StageSignalBinding({
    required this.signalRef,
    this.bitIndex,
    this.bitWidth,
  });

  /// The hierarchical signal reference, identical to the path used by
  /// [WaveformDataSource].
  final String signalRef;

  /// Optional bit index into the bound signal. `null` means "use the
  /// whole signal value at this slot"; a non-null value means "start
  /// at this LSB and take [bitWidth] bits (or just one bit if
  /// [bitWidth] is null)" and is only meaningful when [signalRef]
  /// points at a multi-bit vector.
  ///
  /// Index 0 is the LSB. Out-of-range indices render as unknown.
  final int? bitIndex;

  /// Optional slice width. When non-null and > 1, the slot consumes
  /// the [bitWidth]-bit slice starting at [bitIndex] (LSB). When
  /// `null` or 1, [bitIndex] (if set) selects a single bit.
  ///
  /// Out-of-range slice ends render as unknown for the missing bits.
  final int? bitWidth;

  StageSignalBinding copyWith({
    String? signalRef,
    int? bitIndex,
    int? bitWidth,
    bool clearBitIndex = false,
    bool clearBitWidth = false,
  }) => StageSignalBinding(
    signalRef: signalRef ?? this.signalRef,
    bitIndex: clearBitIndex ? null : (bitIndex ?? this.bitIndex),
    bitWidth: clearBitWidth ? null : (bitWidth ?? this.bitWidth),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StageSignalBinding &&
        signalRef == other.signalRef &&
        bitIndex == other.bitIndex &&
        bitWidth == other.bitWidth;
  }

  @override
  int get hashCode => Object.hash(signalRef, bitIndex, bitWidth);

  @override
  String toString() {
    if (bitIndex == null) return 'StageSignalBinding($signalRef)';
    if (bitWidth == null || bitWidth == 1) {
      return 'StageSignalBinding($signalRef[$bitIndex])';
    }
    final msb = bitIndex! + bitWidth! - 1;
    return 'StageSignalBinding($signalRef[$msb:${bitIndex!}])';
  }
}
