// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/cocotb/cocotb_log_parser.dart';

part 'cocotb_log_provider.g.dart';

/// Indirection so unit tests can substitute a string-based loader without
/// touching the real filesystem. Returns the file's contents as a single
/// string. Defaults to [_readFromDisk] in production.
typedef CocotbLogReader = Future<String> Function(String filePath);

Future<String> _readFromDisk(String path) => File(path).readAsString();

/// Manages the currently-loaded cocotb log file.
///
/// State is `null` when no log has been loaded. [loadFromFile] reads the
/// given path, parses it with [CocotbLogParser], and replaces the state.
/// [clear] returns to the empty state.
///
/// The active waveform's timescale is read at load time so timestamps can be
/// converted to ticks for correlation with the timeline. If no file is
/// loaded the parser falls back to a 1 ns/tick default.
@Riverpod(keepAlive: true)
class CocotbLog extends _$CocotbLog {
  /// Test-only override used to substitute a non-filesystem reader.
  @visibleForTesting
  CocotbLogReader reader = _readFromDisk;

  /// Test-only override used to substitute a parser.
  @visibleForTesting
  CocotbLogParser parser = const CocotbLogParser();

  @override
  CocotbLogFile? build() => null;

  /// Reads, parses, and stores [filePath]. Errors propagate to the caller.
  Future<void> loadFromFile(String filePath) async {
    final content = await reader(filePath);
    final timescale = ref.read(currentTimescaleProvider);
    state = parser.parse(content, filePath, timescale: timescale);
  }

  /// Clears the loaded log. Idempotent.
  void clear() {
    state = null;
  }
}
