// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/time_range.dart';

/// One matched signal pair from two waveform files.
///
/// [pathA] and [pathB] are the full hierarchical paths of the corresponding
/// variables in files A and B respectively.  They may differ when signals are
/// matched by leaf name across different top-level scope names.
///
/// [signalRefA] and [signalRefB] are the opaque identifiers used to query
/// [WaveformDataSource] for each side.  They default to [pathA] and [pathB]
/// but differ in practice because most backends index by an internal id code
/// (VCD idcode or wellen u32 handle), not by the hierarchical path.
///
/// [isDifferent] is false until [WaveformDiffService.computeDiff] populates
/// [divergenceRegions].
@immutable
class SignalMatch {
  const SignalMatch({
    required this.pathA,
    required this.pathB,
    String? signalRefA,
    String? signalRefB,
    this.isDifferent = false,
    this.divergenceRegions = const [],
  }) : signalRefA = signalRefA ?? pathA,
       signalRefB = signalRefB ?? pathB;

  final String pathA;
  final String pathB;

  /// Opaque signal reference used for [WaveformDataSource] calls against file A.
  ///
  /// Defaults to [pathA] when not supplied.  May differ from [pathA] when the
  /// data-source backend indexes by identifier code (VCD idcode, wellen u32
  /// handle) rather than hierarchical path.
  final String signalRefA;

  /// Opaque signal reference used for [WaveformDataSource] calls against file B.
  ///
  /// Defaults to [pathB] when not supplied.
  final String signalRefB;

  /// True when at least one [divergenceRegions] entry exists.
  final bool isDifferent;

  /// Time ranges where the two signals have different values.
  ///
  /// Regions are non-overlapping and sorted by [TimeRange.start].
  final List<TimeRange> divergenceRegions;

  /// Simulation tick of the first divergence, or null when signals are identical.
  int? get firstDivergenceTime =>
      divergenceRegions.isEmpty ? null : divergenceRegions.first.start;

  SignalMatch copyWith({
    String? pathA,
    String? pathB,
    String? signalRefA,
    String? signalRefB,
    bool? isDifferent,
    List<TimeRange>? divergenceRegions,
  }) => SignalMatch(
    pathA: pathA ?? this.pathA,
    pathB: pathB ?? this.pathB,
    signalRefA: signalRefA ?? this.signalRefA,
    signalRefB: signalRefB ?? this.signalRefB,
    isDifferent: isDifferent ?? this.isDifferent,
    divergenceRegions: divergenceRegions ?? this.divergenceRegions,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalMatch &&
          runtimeType == other.runtimeType &&
          pathA == other.pathA &&
          pathB == other.pathB &&
          signalRefA == other.signalRefA &&
          signalRefB == other.signalRefB &&
          isDifferent == other.isDifferent &&
          _listEqual(divergenceRegions, other.divergenceRegions);

  @override
  int get hashCode =>
      Object.hash(pathA, pathB, signalRefA, signalRefB, isDifferent);

  @override
  String toString() =>
      'SignalMatch(pathA: $pathA, pathB: $pathB, '
      'signalRefA: $signalRefA, signalRefB: $signalRefB, '
      'isDifferent: $isDifferent, regions: ${divergenceRegions.length})';

  static bool _listEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
