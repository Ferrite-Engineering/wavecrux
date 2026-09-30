// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';

/// Snapshot of file and parser statistics collected after loading a waveform.
@immutable
class FileStats {
  const FileStats({
    required this.filePath,
    required this.fileSizeBytes,
    required this.formatName,
    required this.parseTimeMs,
    required this.totalSignals,
    required this.scalarCount,
    required this.vectorCount,
    required this.realCount,
    required this.inputCount,
    required this.outputCount,
    required this.inoutCount,
    required this.unknownDirectionCount,
    required this.totalTransitions,
    required this.hierarchyDepth,
    required this.scopeCount,
    required this.startTime,
    required this.endTime,
    this.timescaleDisplay,
    this.simulationDate,
    this.simulatorVersion,
    this.originalFormat,
    this.convertedAt,
  });

  final String filePath;
  final int fileSizeBytes;

  /// Human-readable format identifier, e.g. "VCD", "FST", "GHW".
  final String formatName;

  final double parseTimeMs;
  final int totalSignals;
  final int scalarCount;
  final int vectorCount;
  final int realCount;
  final int inputCount;
  final int outputCount;
  final int inoutCount;
  final int unknownDirectionCount;
  final int totalTransitions;
  final int hierarchyDepth;
  final int scopeCount;
  final int startTime;
  final int endTime;

  /// Formatted timescale string, e.g. "1 ns". Null when unavailable.
  final String? timescaleDisplay;

  /// Contents of the `$date` header, or null when absent.
  final String? simulationDate;

  /// Contents of the `$version` header, or null when absent.
  final String? simulatorVersion;

  /// The on-disk format of the file the user actually picked, before any
  /// convert-on-open routing. Differs from [formatName] only when the
  /// `lxt2fst` path ran: [formatName] is the in-memory backing
  /// format (always "FST" in that case) while [originalFormat] records the
  /// legacy origin (LXT / LXT2). Null for native FST/VCD/GHW opens. Used by
  /// the Diagnostics → File Info "Original Format" row.
  final WaveformFormat? originalFormat;

  /// Wall-clock time at which the `lxt2fst` convert-on-open path finished
  /// producing the cached FST for *this* open. Null when no conversion ran
  /// (native open, or cache hit without recording the timestamp). Surfaced
  /// in the File Info "Original Format" row as the date in
  /// "LXT2 (converted to FST on …)".
  final DateTime? convertedAt;

  FileStats copyWith({
    String? filePath,
    int? fileSizeBytes,
    String? formatName,
    double? parseTimeMs,
    int? totalSignals,
    int? scalarCount,
    int? vectorCount,
    int? realCount,
    int? inputCount,
    int? outputCount,
    int? inoutCount,
    int? unknownDirectionCount,
    int? totalTransitions,
    int? hierarchyDepth,
    int? scopeCount,
    int? startTime,
    int? endTime,
    Object? timescaleDisplay = _unset,
    Object? simulationDate = _unset,
    Object? simulatorVersion = _unset,
    Object? originalFormat = _unset,
    Object? convertedAt = _unset,
  }) => FileStats(
    filePath: filePath ?? this.filePath,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    formatName: formatName ?? this.formatName,
    parseTimeMs: parseTimeMs ?? this.parseTimeMs,
    totalSignals: totalSignals ?? this.totalSignals,
    scalarCount: scalarCount ?? this.scalarCount,
    vectorCount: vectorCount ?? this.vectorCount,
    realCount: realCount ?? this.realCount,
    inputCount: inputCount ?? this.inputCount,
    outputCount: outputCount ?? this.outputCount,
    inoutCount: inoutCount ?? this.inoutCount,
    unknownDirectionCount: unknownDirectionCount ?? this.unknownDirectionCount,
    totalTransitions: totalTransitions ?? this.totalTransitions,
    hierarchyDepth: hierarchyDepth ?? this.hierarchyDepth,
    scopeCount: scopeCount ?? this.scopeCount,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    timescaleDisplay: timescaleDisplay == _unset
        ? this.timescaleDisplay
        : timescaleDisplay as String?,
    simulationDate: simulationDate == _unset
        ? this.simulationDate
        : simulationDate as String?,
    simulatorVersion: simulatorVersion == _unset
        ? this.simulatorVersion
        : simulatorVersion as String?,
    originalFormat: originalFormat == _unset
        ? this.originalFormat
        : originalFormat as WaveformFormat?,
    convertedAt: convertedAt == _unset
        ? this.convertedAt
        : convertedAt as DateTime?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileStats &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          fileSizeBytes == other.fileSizeBytes &&
          formatName == other.formatName &&
          parseTimeMs == other.parseTimeMs &&
          totalSignals == other.totalSignals &&
          scalarCount == other.scalarCount &&
          vectorCount == other.vectorCount &&
          realCount == other.realCount &&
          inputCount == other.inputCount &&
          outputCount == other.outputCount &&
          inoutCount == other.inoutCount &&
          unknownDirectionCount == other.unknownDirectionCount &&
          totalTransitions == other.totalTransitions &&
          hierarchyDepth == other.hierarchyDepth &&
          scopeCount == other.scopeCount &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          timescaleDisplay == other.timescaleDisplay &&
          simulationDate == other.simulationDate &&
          simulatorVersion == other.simulatorVersion &&
          originalFormat == other.originalFormat &&
          convertedAt == other.convertedAt;

  @override
  int get hashCode => Object.hashAll([
    filePath,
    fileSizeBytes,
    formatName,
    parseTimeMs,
    totalSignals,
    scalarCount,
    vectorCount,
    realCount,
    inputCount,
    outputCount,
    inoutCount,
    unknownDirectionCount,
    totalTransitions,
    hierarchyDepth,
    scopeCount,
    startTime,
    endTime,
    timescaleDisplay,
    simulationDate,
    simulatorVersion,
    originalFormat,
    convertedAt,
  ]);

  @override
  String toString() =>
      'FileStats('
      'filePath: $filePath, '
      'format: $formatName, '
      'sizeBytes: $fileSizeBytes, '
      'parseTimeMs: $parseTimeMs, '
      'signals: $totalSignals, '
      'transitions: $totalTransitions'
      ')';
}

const _unset = Object();
