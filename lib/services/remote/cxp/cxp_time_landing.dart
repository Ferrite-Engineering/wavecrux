// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart' show CxpTime;
import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';

/// The CXP `metadata` key that carries a point in simulation time on a signal
/// highlight (CXP §9.3.2, specification revision 10): a non-negative integer
/// number of picoseconds from the start of the simulation.
const String kCxpTimePsMetadataKey = 'crux.time_ps';

/// What a `crux.time_ps` value resolves to against one open waveform.
@immutable
class CxpTimeResolution {
  /// The time lands at [tick] in the waveform's own time unit. [reason] is
  /// set when the time was moved to get there (clamped to the waveform).
  const CxpTimeResolution.placed(this.tick, {this.reason});

  /// The time could not be placed. The element is still honoured; [reason]
  /// says why the cursor did not move.
  const CxpTimeResolution.declined(String this.reason) : tick = null;

  /// The waveform tick to put the cursor on, or null when declined.
  final int? tick;

  /// What the sender is told about the time, if anything.
  final String? reason;
}

/// Converts the `time` field of a `request_highlight` (CXP §9.3.3) to a tick
/// of a waveform that declares [timescale] and spans `[startTime, endTime]`
/// ticks, or, when [time] is null, the `crux.time_ps` entry of [metadata]
/// ([resolveCxpTimePs]). `time` wins when both are present.
///
/// A bare tick count is already in the waveform's own unit and needs no
/// timescale; a time with a unit is converted with the timescale, rounding to
/// the nearest tick with a half tick up. Never throws and never refuses the
/// highlight: a time outside the waveform is clamped to the nearest end with a
/// reason, and a time with a unit on a waveform with no timescale is declined
/// with a reason.
CxpTimeResolution? resolveCxpTime(
  CxpTime? time,
  Map<String, Object?> metadata, {
  required Timescale? timescale,
  required int startTime,
  required int endTime,
}) {
  if (time == null) {
    return resolveCxpTimePs(
      metadata,
      timescale: timescale,
      startTime: startTime,
      endTime: endTime,
    );
  }
  final BigInt? ticks;
  if (time.isTicks) {
    ticks = time.mantissa;
  } else {
    final exponent = timescale?.unit.exponent;
    ticks = exponent == null || timescale == null
        ? null
        : time.toTicks(unitExponent: exponent, factor: timescale.factor);
  }
  if (ticks == null) {
    return const CxpTimeResolution.declined(
      'the time was not applied: the open waveform declares no timescale',
    );
  }
  if (ticks < BigInt.from(startTime)) {
    return CxpTimeResolution.placed(startTime, reason: _clamped);
  }
  if (ticks > BigInt.from(endTime)) {
    return CxpTimeResolution.placed(endTime, reason: _clamped);
  }
  return CxpTimeResolution.placed(ticks.toInt());
}

/// Converts the `crux.time_ps` entry of [metadata] to a tick of a waveform that
/// declares [timescale] and spans `[startTime, endTime]` ticks.
///
/// Returns null when the key is absent: nothing about time was asked.
///
/// Never throws and never refuses the highlight (CXP §12 item 28): a value
/// that is not a non-negative integer, or a waveform with no usable
/// timescale, is a [CxpTimeResolution.declined] with a reason, and a time
/// outside the waveform is clamped to the nearest end, with a reason saying
/// so (§9.3.2).
///
/// The conversion is integer arithmetic throughout and rounds to the nearest
/// tick, because a timescale of 10 ns or 1 fs must not pick up the error of a
/// floating-point seconds-per-tick.
CxpTimeResolution? resolveCxpTimePs(
  Map<String, Object?> metadata, {
  required Timescale? timescale,
  required int startTime,
  required int endTime,
}) {
  if (!metadata.containsKey(kCxpTimePsMetadataKey)) return null;
  final ps = metadata[kCxpTimePsMetadataKey];
  if (ps is! int || ps < 0) {
    return const CxpTimeResolution.declined(
      'the time was not applied: it is not a non-negative integer number '
      'of picoseconds',
    );
  }
  final tickFs = _femtosecondsPerTick(timescale);
  if (tickFs == null) {
    return const CxpTimeResolution.declined(
      'the time was not applied: the open waveform declares no timescale',
    );
  }

  final int tick;
  if (tickFs % 1000 == 0) {
    final tickPs = tickFs ~/ 1000;
    tick = ps ~/ tickPs + ((ps % tickPs) * 2 >= tickPs ? 1 : 0);
  } else if (ps > _maxSubPicosecondPs) {
    // A sub-picosecond tick this far out would overflow a web integer, and
    // no waveform is that long: it is past the end.
    return CxpTimeResolution.placed(endTime, reason: _clamped);
  } else {
    tick = (ps * 1000 + tickFs ~/ 2) ~/ tickFs;
  }

  if (tick < startTime) {
    return CxpTimeResolution.placed(startTime, reason: _clamped);
  }
  if (tick > endTime) {
    return CxpTimeResolution.placed(endTime, reason: _clamped);
  }
  return CxpTimeResolution.placed(tick);
}

const String _clamped =
    'the time is outside the open waveform, so the cursor was placed at the '
    'nearest end of it';

/// The largest picosecond count a sub-picosecond timescale converts without
/// leaving the integers a web build holds exactly (2^53 / 1000).
const int _maxSubPicosecondPs = 9007199254740;

const Map<TimescaleUnit, int> _femtosecondsPerUnit = <TimescaleUnit, int>{
  TimescaleUnit.femtoSeconds: 1,
  TimescaleUnit.picoSeconds: 1000,
  TimescaleUnit.nanoSeconds: 1000000,
  TimescaleUnit.microSeconds: 1000000000,
  TimescaleUnit.milliSeconds: 1000000000000,
  TimescaleUnit.seconds: 1000000000000000,
};

/// How many femtoseconds one tick of [timescale] lasts, or null when it
/// declares none (or a nonsensical one).
int? _femtosecondsPerTick(Timescale? timescale) {
  if (timescale == null || timescale.factor <= 0) return null;
  final unit = _femtosecondsPerUnit[timescale.unit];
  if (unit == null) return null;
  return timescale.factor * unit;
}
