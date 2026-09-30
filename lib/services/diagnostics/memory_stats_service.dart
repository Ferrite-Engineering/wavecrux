// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';

/// Collects memory and resource usage statistics from a loaded
/// [WaveformDataSource].
///
/// Stateless — call [collect] with the current source and optional native
/// memory estimate from the FFI layer.  All computations are synchronous.
class MemoryStatsService {
  const MemoryStatsService();

  /// Build a [MemoryStats] snapshot.
  ///
  /// [wellenMemoryBytes] is the approximate native heap used by the wellen
  /// signal database, supplied by the FFI layer.  Pass `null` when unavailable
  /// (e.g. on web, where the wellen-WASM linear-memory accounting is not
  /// exposed) — reported as 0.
  MemoryStats collect({
    required WaveformDataSource source,
    int? wellenMemoryBytes,
  }) {
    final variables = source.findVariables(const SignalFilter());
    final totalSignalCount = variables.length;

    var loadedSignalCount = 0;
    for (final v in variables) {
      if (source.isSignalLoaded(v.signalRef)) loadedSignalCount++;
    }

    return MemoryStats(
      wellenEstimateBytes: wellenMemoryBytes ?? 0,
      loadedSignalCount: loadedSignalCount,
      totalSignalCount: totalSignalCount,
      dartProcessRssBytes: _readProcessRss(),
    );
  }

  static int _readProcessRss() {
    if (kIsWeb) return 0;
    try {
      return ProcessInfo.currentRss;
    } on Object catch (_) {
      return 0;
    }
  }
}
