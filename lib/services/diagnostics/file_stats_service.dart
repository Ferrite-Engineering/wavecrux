// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';

/// Collects file and parser statistics from a loaded [WaveformDataSource].
///
/// Stateless — call [collect] after a successful file open. All computations
/// are synchronous and run on the calling isolate.
class FileStatsService {
  const FileStatsService();

  /// Build a [FileStats] snapshot from [source] and supplementary inputs.
  ///
  /// [filePath] is the on-disk path used to read file size.  On web, or when
  /// the path is empty, size is reported as 0.
  ///
  /// [parseTime] is the wall-clock duration of the parse operation as measured
  /// by [WaveformSourceNotifier].
  ///
  /// [formatOverride] lets the FFI layer supply the format string directly
  /// (e.g. "VCD", "FST", "GHW") rather than inferring it from the extension.
  ///
  /// [totalTransitionsOverride] lets the FFI layer supply the total transition
  /// count.  When null, the value defaults to 0 and the UI shows "N/A".
  FileStats collect({
    required WaveformDataSource source,
    required String filePath,
    required Duration parseTime,
    String? formatOverride,
    int? totalTransitionsOverride,
    WaveformFormat? originalFormat,
    DateTime? convertedAt,
  }) {
    final fileSizeBytes = _readFileSize(filePath);
    final formatName = formatOverride ?? _inferFormat(filePath);

    final variables = source.findVariables(const SignalFilter());
    var scalarCount = 0;
    var vectorCount = 0;
    var realCount = 0;
    var inputCount = 0;
    var outputCount = 0;
    var inoutCount = 0;
    var unknownDirectionCount = 0;

    for (final v in variables) {
      if (v.isReal) {
        realCount++;
      } else if ((v.bitWidth ?? 1) > 1) {
        vectorCount++;
      } else {
        scalarCount++;
      }

      switch (v.direction) {
        case VarDirection.input:
          inputCount++;
        case VarDirection.output:
          outputCount++;
        case VarDirection.inout:
          inoutCount++;
        case VarDirection.unknown:
        case VarDirection.implicit:
        case VarDirection.buffer:
        case VarDirection.linkage:
          unknownDirectionCount++;
      }
    }

    var hierarchyDepth = 0;
    var scopeCount = 0;
    for (final scope in source.rootScopes) {
      final (depth, count) = _traverseScope(scope, 1);
      if (depth > hierarchyDepth) hierarchyDepth = depth;
      scopeCount += count;
    }

    return FileStats(
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      formatName: formatName,
      parseTimeMs: parseTime.inMicroseconds / 1000.0,
      totalSignals: variables.length,
      scalarCount: scalarCount,
      vectorCount: vectorCount,
      realCount: realCount,
      inputCount: inputCount,
      outputCount: outputCount,
      inoutCount: inoutCount,
      unknownDirectionCount: unknownDirectionCount,
      totalTransitions: totalTransitionsOverride ?? 0,
      hierarchyDepth: hierarchyDepth,
      scopeCount: scopeCount,
      startTime: source.startTime,
      endTime: source.endTime,
      timescaleDisplay: source.timescale?.displayString,
      simulationDate: source.date,
      simulatorVersion: source.version,
      originalFormat: originalFormat,
      convertedAt: convertedAt,
    );
  }

  // ── private helpers ────────────────────────────────────────────────────────

  static int _readFileSize(String path) {
    if (kIsWeb || path.isEmpty) return 0;
    try {
      return File(path).lengthSync();
    } on Object catch (_) {
      return 0;
    }
  }

  static String _inferFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.vcd')) return 'VCD';
    if (lower.endsWith('.fst')) return 'FST';
    if (lower.endsWith('.ghw')) return 'GHW';
    return 'Unknown';
  }

  /// Returns `(maxDepth, totalScopeCount)` for [scope] and all descendants.
  static (int, int) _traverseScope(Scope scope, int depth) {
    var maxDepth = depth;
    var count = 1;
    for (final child in scope.childScopes) {
      final (d, c) = _traverseScope(child, depth + 1);
      if (d > maxDepth) maxDepth = d;
      count += c;
    }
    return (maxDepth, count);
  }
}
