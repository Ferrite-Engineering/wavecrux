// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart' show requireSpawnExecutableForHost;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Runs an external process and returns the result.
///
/// Injected in tests to avoid real process execution.
typedef FsdbProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

/// Locates an executable by name in `$PATH`.  Returns the full path or null.
///
/// Injected in tests so that PATH-dependent logic can be exercised without
/// needing real Synopsys or GTKWave tools installed.
typedef FsdbExecutableLocator = String? Function(String executableName);

// The locator hands this an absolute path, which the resolution leaves as it
// is. A bare name is resolved against PATH first, so on Windows it can never
// be searched for in the directory WaveCrux was launched from.
Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments,
) async => Process.run(requireSpawnExecutableForHost(executable), arguments);

String? _defaultLocator(String name) {
  if (kIsWeb) return null;
  final pathEnv = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  final dirs = pathEnv.split(separator);
  final executable = Platform.isWindows ? '$name.exe' : name;
  for (final dir in dirs) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, executable);
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Exception thrown when FSDB conversion fails.
class FsdbConversionException implements Exception {
  const FsdbConversionException(this.message);

  final String message;

  @override
  String toString() => 'FsdbConversionException: $message';
}

/// Service for detecting and converting Synopsys FSDB files to FST.
///
/// FSDB (Fast Signal Database) is a proprietary Synopsys format with no
/// public specification.  WaveCrux supports FSDB files through conversion only:
/// if `fsdb2vcd` is in `$PATH`, it runs FSDB → VCD via `fsdb2vcd` and then
/// VCD → FST via `vcd2fst`.  If only `fsdb2vcd` is available (no `vcd2fst`),
/// it produces a VCD file instead.
///
/// The service is stateless and designed for constructor injection of both the
/// process runner and executable locator so it can be fully unit-tested without
/// real Synopsys tools installed.
///
/// On Flutter Web [isFsdbFile] works normally; all other methods throw
/// [UnsupportedError].
class FsdbConversionService {
  const FsdbConversionService({
    FsdbProcessRunner? processRunner,
    FsdbExecutableLocator? executableLocator,
  }) : _processRunner = processRunner ?? _defaultProcessRunner,
       _locator = executableLocator ?? _defaultLocator;

  final FsdbProcessRunner _processRunner;
  final FsdbExecutableLocator _locator;

  /// Returns true when [path] ends with `.fsdb` (case-insensitive).
  bool isFsdbFile(String path) => path.toLowerCase().endsWith('.fsdb');

  /// Searches `$PATH` for the `fsdb2vcd` Synopsys executable.
  ///
  /// Returns the full path to the executable if found, or null if not found.
  /// On web always returns null.
  String? findFsdb2Vcd() => _locator('fsdb2vcd');

  /// Searches `$PATH` for the `vcd2fst` GTKWave utility.
  ///
  /// Returns the full path to the executable if found, or null if not found.
  /// On web always returns null.
  String? findVcd2Fst() => _locator('vcd2fst');

  /// Returns the path to a cached FST for [fsdbPath] if one exists and is
  /// newer than the FSDB file.  The cache sits alongside the original FSDB
  /// file with a `.fst` extension.
  ///
  /// Returns null if no cache exists or the cache is stale.
  /// Throws [UnsupportedError] on Flutter Web.
  String? getCachedFst(String fsdbPath) {
    if (kIsWeb) throw UnsupportedError('Not supported on web');
    final fstPath = '${p.withoutExtension(fsdbPath)}.fst';
    final fstFile = File(fstPath);
    final fsdbFile = File(fsdbPath);
    if (!fstFile.existsSync()) return null;
    final fstMod = fstFile.lastModifiedSync();
    final fsdbMod = fsdbFile.lastModifiedSync();
    return fstMod.isAfter(fsdbMod) ? fstPath : null;
  }

  /// Converts [fsdbPath] to FST (or VCD if `vcd2fst` is not in `$PATH`).
  ///
  /// Step 1: runs `fsdb2vcd [fsdbPath]` and captures stdout to a temp VCD.
  /// Step 2: if `vcd2fst` is found, runs `vcd2fst [vcd] [fst]` → returns the
  ///   FST path.  Otherwise renames the temp VCD to `<base>.vcd` and returns
  ///   that path.
  ///
  /// The output file is placed in [outputDir] when given, or in the same
  /// directory as [fsdbPath] by default.
  ///
  /// Throws [FsdbConversionException] if a conversion step fails.
  /// Throws [UnsupportedError] on Flutter Web.
  Future<String> convertFsdbToFst(
    String fsdbPath, {
    String? outputDir,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('FSDB conversion is not supported on web');
    }

    final fsdb2vcd = findFsdb2Vcd();
    if (fsdb2vcd == null) {
      throw const FsdbConversionException('fsdb2vcd not found in PATH');
    }

    final dir = outputDir ?? p.dirname(fsdbPath);
    final base = p.basenameWithoutExtension(fsdbPath);
    final tempVcdPath = p.join(dir, '$base.vcd.tmp');
    final outputFstPath = p.join(dir, '$base.fst');
    final outputVcdPath = p.join(dir, '$base.vcd');

    try {
      // Step 1: Run fsdb2vcd, write stdout to a temp VCD file.
      final vcdResult = await _processRunner(fsdb2vcd, [fsdbPath]);
      if (vcdResult.exitCode != 0) {
        throw FsdbConversionException(
          'fsdb2vcd failed (exit ${vcdResult.exitCode}): ${vcdResult.stderr}',
        );
      }
      await File(tempVcdPath).writeAsString(vcdResult.stdout as String);

      // Step 2: If vcd2fst is available, convert VCD → FST.
      final vcd2fst = findVcd2Fst();
      if (vcd2fst != null) {
        final fstResult = await _processRunner(vcd2fst, [
          tempVcdPath,
          outputFstPath,
        ]);
        if (fstResult.exitCode != 0) {
          throw FsdbConversionException(
            'vcd2fst failed (exit ${fstResult.exitCode}): ${fstResult.stderr}',
          );
        }
        return outputFstPath;
      } else {
        // No vcd2fst available: keep the intermediate VCD.
        await File(tempVcdPath).rename(outputVcdPath);
        return outputVcdPath;
      }
    } finally {
      // Clean up the temp file even on error.
      final temp = File(tempVcdPath);
      if (temp.existsSync()) {
        await temp.delete();
      }
    }
  }
}
