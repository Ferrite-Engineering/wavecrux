// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'waveform_data_revision_provider.g.dart';

/// Monotonic counter bumped whenever the set of **loaded signal data** changes
/// for the current waveform.
///
/// Exists because signal *data* arrives after the signal *list* does. The
/// canvas loads lanes lazily through a bounded-concurrency pipeline, so between
/// a file opening and its samples being decompressed there is a window where
/// `WaveformDataSource.valueAt` answers `null` for a signal that is displayed
/// and perfectly real.
///
/// Anything deriving a *value* from the source — rather than a shape, a name or
/// a count — has to recompute when that window closes, and no other provider
/// changes at that moment: the source instance is the same object, and the
/// signal list settled earlier. Without this, such a provider memoizes an
/// answer computed against data that had not loaded yet and never revisits it.
///
/// The concrete failure that produced this: after an in-place reload of a
/// re-simulated dump, annotation drift statuses were computed while `valueAt`
/// still returned `null`, resolved to "no drift", and stayed that way. The
/// notes survived the reload and kept asserting the previous run's answer,
/// which reads as correct and is the worst way to be wrong.
@riverpod
class WaveformDataRevision extends _$WaveformDataRevision {
  @override
  int build() => 0;

  /// Signals that loaded sample data changed. Cheap and idempotent-safe to
  /// call more often than strictly necessary — consumers are memoized on the
  /// value, so a redundant bump costs one recompute, while a missing one costs
  /// a silently stale answer.
  void bump() => state = state + 1;
}
