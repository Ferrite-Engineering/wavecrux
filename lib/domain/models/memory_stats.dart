// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Snapshot of memory and resource usage for the loaded waveform.
@immutable
class MemoryStats {
  const MemoryStats({
    required this.wellenEstimateBytes,
    required this.loadedSignalCount,
    required this.totalSignalCount,
    required this.dartProcessRssBytes,
  });

  /// Approximate bytes used by wellen's internal signal database.
  final int wellenEstimateBytes;

  /// Number of signals that have been lazily loaded into memory.
  final int loadedSignalCount;

  /// Total number of signals in the waveform (including unloaded).
  final int totalSignalCount;

  /// Total resident set size of the Dart process in bytes.
  final int dartProcessRssBytes;

  MemoryStats copyWith({
    int? wellenEstimateBytes,
    int? loadedSignalCount,
    int? totalSignalCount,
    int? dartProcessRssBytes,
  }) => MemoryStats(
    wellenEstimateBytes: wellenEstimateBytes ?? this.wellenEstimateBytes,
    loadedSignalCount: loadedSignalCount ?? this.loadedSignalCount,
    totalSignalCount: totalSignalCount ?? this.totalSignalCount,
    dartProcessRssBytes: dartProcessRssBytes ?? this.dartProcessRssBytes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryStats &&
          runtimeType == other.runtimeType &&
          wellenEstimateBytes == other.wellenEstimateBytes &&
          loadedSignalCount == other.loadedSignalCount &&
          totalSignalCount == other.totalSignalCount &&
          dartProcessRssBytes == other.dartProcessRssBytes;

  @override
  int get hashCode => Object.hash(
    wellenEstimateBytes,
    loadedSignalCount,
    totalSignalCount,
    dartProcessRssBytes,
  );

  @override
  String toString() =>
      'MemoryStats('
      'wellenEstimateBytes: $wellenEstimateBytes, '
      'loadedSignals: $loadedSignalCount/$totalSignalCount, '
      'dartRssBytes: $dartProcessRssBytes'
      ')';
}
