// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Configuration for a VCD export operation.
@immutable
class VcdExportConfig {
  const VcdExportConfig({
    required this.signalRefs,
    required this.signalMap,
    required this.startTime,
    required this.endTime,
  });

  /// Extracts all signal refs recursively from [signalGroup] and builds a
  /// config covering [[startTime], [endTime]].
  factory VcdExportConfig.fromSignalGroup({
    required SignalGroup signalGroup,
    required Map<String, Variable> signalMap,
    required int startTime,
    required int endTime,
  }) {
    final refs = <String>[];
    void collect(List<SignalEntry> entries) {
      for (final e in entries) {
        if (e.kind == SignalEntryKind.signal && e.signalRef != null) {
          refs.add(e.signalRef!);
        } else if (e.kind == SignalEntryKind.group) {
          collect(e.children);
        }
      }
    }

    collect(signalGroup.entries);
    return VcdExportConfig(
      signalRefs: refs,
      signalMap: signalMap,
      startTime: startTime,
      endTime: endTime,
    );
  }

  /// Ordered list of signal references to include in the export.
  final List<String> signalRefs;

  /// Map from signal reference to its [Variable] metadata.
  final Map<String, Variable> signalMap;

  /// First tick to include in the export (inclusive).
  final int startTime;

  /// Last tick to include in the export (inclusive).
  final int endTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VcdExportConfig &&
          signalRefs.length == other.signalRefs.length &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode => Object.hash(signalRefs.length, startTime, endTime);
}

/// Writes a valid IEEE 1800-2023 VCD file from [WaveformDataSource] data.
///
/// Supports exporting a subset of signals over a specified time range.
/// Assigns fresh short identifier codes to the exported signals.
/// Preserves scope hierarchy from [Variable.scopePath].
///
/// The exported file is a self-contained VCD: it includes a `$dumpvars` block
/// with the initial state at [VcdExportConfig.startTime] followed by all
/// value changes up to [VcdExportConfig.endTime].
class VcdWriterService {
  const VcdWriterService();

  // 94 printable ASCII characters: ! (0x21) through ~ (0x7E).
  static const _idChars =
      r'''!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~''';

  /// Returns the VCD identifier code for [index].
  ///
  /// Uses the 94 printable-ASCII characters (! through ~). For indices beyond
  /// 93 the code becomes multi-character using a base-94 encoding.
  @visibleForTesting
  static String generateIdCode(int index) {
    assert(index >= 0, 'index must be non-negative');
    if (index < _idChars.length) return _idChars[index];
    var result = '';
    var i = index;
    do {
      result = _idChars[i % _idChars.length] + result;
      i = i ~/ _idChars.length - 1;
    } while (i >= 0);
    return result;
  }

  /// Generates a complete VCD file as a string.
  ///
  /// All signals in [config.signalRefs] are queried from [source].
  /// Only times in [[config.startTime], [config.endTime]] are included.
  /// Returns an empty string when [config.signalRefs] is empty.
  String generateVcd(WaveformDataSource source, VcdExportConfig config) {
    if (config.signalRefs.isEmpty) return '';

    final idCodes = <String, String>{};
    for (var i = 0; i < config.signalRefs.length; i++) {
      idCodes[config.signalRefs[i]] = generateIdCode(i);
    }

    final buf = StringBuffer()
      ..write(_buildHeader(source))
      ..write(_buildDeclarations(config, idCodes))
      ..writeln(r'$enddefinitions $end')
      ..write(_buildValueChanges(source, config, idCodes));
    return buf.toString();
  }

  /// Writes the VCD content to [outputPath].
  ///
  /// Throws [VcdWriteException] on I/O failure.
  Future<void> writeVcd(
    WaveformDataSource source,
    VcdExportConfig config,
    String outputPath,
  ) async {
    final content = generateVcd(source, config);
    try {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
    } on IOException catch (e) {
      throw VcdWriteException(outputPath, e.toString());
    }
  }

  // ── header ───────────────────────────────────────────────────────────────────

  String _buildHeader(WaveformDataSource source) {
    final ts = source.timescale;
    final timescaleStr = ts != null ? ts.displayString : '1ns';
    return '\$date ${DateTime.now()} \$end\n'
        '\$version WaveCrux \$end\n'
        '\$timescale $timescaleStr \$end\n';
  }

  // ── declarations ─────────────────────────────────────────────────────────────

  String _buildDeclarations(
    VcdExportConfig config,
    Map<String, String> idCodes,
  ) {
    // Group signal refs by their scope path.
    final scopeToRefs = <String, List<String>>{};
    for (final ref in config.signalRefs) {
      final variable = config.signalMap[ref];
      final scopePath = variable?.scopePath ?? '';
      (scopeToRefs[scopePath] ??= []).add(ref);
    }

    final buf = StringBuffer();

    // Emit root-level vars (scope path == "").
    for (final ref in scopeToRefs[''] ?? const <String>[]) {
      buf.write(_varLine(ref, config, idCodes));
    }

    // Find all unique top-level scope names and recurse.
    final topScopeNames = <String>{};
    for (final path in scopeToRefs.keys) {
      if (path.isNotEmpty) topScopeNames.add(path.split('.').first);
    }
    for (final name in topScopeNames.toList()..sort()) {
      buf.write(_buildScopeBlock(name, scopeToRefs, config, idCodes));
    }

    return buf.toString();
  }

  String _buildScopeBlock(
    String currentPath,
    Map<String, List<String>> scopeToRefs,
    VcdExportConfig config,
    Map<String, String> idCodes,
  ) {
    final scopeName = currentPath.split('.').last;
    final buf = StringBuffer()..writeln('\$scope module $scopeName \$end');

    // Emit vars whose scope path is exactly currentPath.
    for (final ref in scopeToRefs[currentPath] ?? const <String>[]) {
      buf.write(_varLine(ref, config, idCodes));
    }

    // Recurse one level deeper.
    final prefix = '$currentPath.';
    final childNames = <String>{};
    for (final path in scopeToRefs.keys) {
      if (path.startsWith(prefix)) {
        final remainder = path.substring(prefix.length);
        final nextPart = remainder.split('.').first;
        if (nextPart.isNotEmpty) childNames.add(nextPart);
      }
    }
    for (final childName in childNames.toList()..sort()) {
      buf.write(
        _buildScopeBlock(
          '$currentPath.$childName',
          scopeToRefs,
          config,
          idCodes,
        ),
      );
    }

    buf.writeln(r'$upscope $end');
    return buf.toString();
  }

  String _varLine(
    String ref,
    VcdExportConfig config,
    Map<String, String> idCodes,
  ) {
    final variable = config.signalMap[ref];
    if (variable == null) return '';
    final code = idCodes[ref]!;
    final width = variable.bitWidth ?? 1;
    final typeStr = variable.isReal ? 'real' : 'wire';
    return '\$var $typeStr $width $code ${variable.name} \$end\n';
  }

  // ── value changes ─────────────────────────────────────────────────────────────

  String _buildValueChanges(
    WaveformDataSource source,
    VcdExportConfig config,
    Map<String, String> idCodes,
  ) {
    final refs = config.signalRefs;
    final start = config.startTime;
    final end = config.endTime;

    // Emit $dumpvars with the value of each signal at the export start time.
    final buf = StringBuffer()
      ..writeln('#$start')
      ..writeln(r'$dumpvars');
    for (final ref in refs) {
      final variable = config.signalMap[ref];
      final rawValue = source.valueAt(ref, start);
      if (rawValue != null) {
        buf.writeln(_formatChange(rawValue, idCodes[ref]!, variable));
      }
    }
    buf.writeln(r'$end');

    // Collect all changes strictly after startTime up to and including endTime.
    // changesInRange is half-open [start, end), so pass end+1 to include end.
    final changesByTime = <int, List<(String ref, String value)>>{};
    for (final ref in refs) {
      final changes = source.changesInRange(ref, start + 1, end + 1);
      for (final change in changes) {
        (changesByTime[change.time] ??= []).add((ref, change.value));
      }
    }

    // Emit changes in ascending time order.
    final times = changesByTime.keys.toList()..sort();
    for (final time in times) {
      buf.writeln('#$time');
      for (final (ref, value) in changesByTime[time]!) {
        final variable = config.signalMap[ref];
        buf.writeln(_formatChange(value, idCodes[ref]!, variable));
      }
    }

    // Emit the end timestamp so consumers know the simulation boundary.
    if (end > start && !changesByTime.containsKey(end)) {
      buf.writeln('#$end');
    }

    return buf.toString();
  }

  String _formatChange(String rawValue, String code, Variable? variable) {
    final normalized = _normalizeValue(rawValue);
    if (variable?.isReal ?? false) {
      return 'r$normalized $code';
    }
    final width = variable?.bitWidth ?? 1;
    if (width == 1) {
      // Scalar: single character directly prepended to code (no space).
      final v = normalized.isNotEmpty ? normalized[normalized.length - 1] : 'x';
      return '$v$code';
    }
    return 'b$normalized $code';
  }

  String _normalizeValue(String raw) {
    var s = raw.toLowerCase();
    if (s.startsWith('b')) s = s.substring(1);
    if (s.startsWith('r')) s = s.substring(1);
    return s;
  }
}

/// Thrown when [VcdWriterService.writeVcd] fails due to an I/O error.
class VcdWriteException implements Exception {
  const VcdWriteException(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'VcdWriteException($path): $reason';
}
