// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Index of the first of [changes] (ordered by time) that lands at or right
/// of pixel [xMin] under [timeMapper]; `changes.length` when none does.
///
/// The canvas hands the lane painters a change list that covers more than the
/// viewport — a band either side, so a pan inside it repaints without a data
/// refetch. A painter starts its walk here and takes the change just before
/// it (if any) as the value entering the viewport. Binary search, so the band
/// costs nothing per frame.
int firstChangeAtOrAfterPixel(
  List<SignalChange> changes,
  TimeMapper timeMapper,
  double xMin,
) {
  var lo = 0;
  var hi = changes.length;
  while (lo < hi) {
    final mid = (lo + hi) >>> 1;
    if (timeMapper.timeToPixel(changes[mid].time) < xMin) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// How many of [changes] (ordered by time) land in the pixel span
/// `[xMin, xMax)` under [timeMapper]: the visible part of a lane's change
/// list, without the band either side. Two binary searches.
int visibleChangeCount(
  List<SignalChange> changes,
  TimeMapper timeMapper,
  double xMin,
  double xMax,
) =>
    firstChangeAtOrAfterPixel(changes, timeMapper, xMax) -
    firstChangeAtOrAfterPixel(changes, timeMapper, xMin);
