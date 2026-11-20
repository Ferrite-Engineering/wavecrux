// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart'
    show SpawnHost, isAbsoluteSpawnPath, requireSpawnExecutableForHost;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/waveform/lxt2fst_cache.dart'
    show
        AppCacheDirectoryResolver,
        defaultAppCacheDirectory,
        stableSourcePathHash;

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
) async =>
    await Process.run(requireSpawnExecutableForHost(executable), arguments);

String? _defaultLocator(String name) => locateFsdbExecutable(name);

/// Finds [name] on `PATH` and returns its absolute path, or null.
///
/// On Windows the search is the shared resolution's, which honours `PATHEXT`
/// (so a `fsdb2vcd.bat` or `vcd2fst.cmd` wrapper around a vendor toolchain is
/// found, not just `.exe`). Elsewhere it walks `PATH` for an existing file,
/// since `execvp` has no resolution to borrow.
///
/// [host] carries every fact the search reads, so a test can hand it a
/// Windows host with a synthetic `PATH`, `PATHEXT` and file probe on any
/// machine.
String? locateFsdbExecutable(String name, {SpawnHost? host}) {
  if (kIsWeb) return null;
  final h = host ?? SpawnHost.current();
  if (h.windows) {
    final resolved = h.resolveExecutable(name);
    return isAbsoluteSpawnPath(resolved) ? resolved : null;
  }
  final exists = h.exists ?? (String path) => File(path).existsSync();
  for (final dir in (h.environment['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    // posix, not the running machine's separator: [host] may describe a
    // POSIX host while a test runs on Windows.
    final candidate = p.posix.join(dir, name);
    if (exists(candidate)) return candidate;
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
/// The output goes beside the FSDB file (`<base>.fst` or `<base>.vcd`) unless
/// a file there by that name is not WaveCrux's: WaveCrux marks its own output
/// with a `<base>.fsdbcache.json` sidecar, and when a `<base>.fst`,
/// `<base>.vcd` or `<base>.vcd.tmp` exists without it, the conversion goes to
/// `${appCacheDir}/legacy_conversions/fsdb/<hash-of-fsdb-path>/` instead.
/// WaveCrux never writes over a file it did not create.
///
/// The service is stateless and designed for constructor injection of the
/// process runner, executable locator and app-cache directory so it can be
/// fully unit-tested without real Synopsys tools installed.
///
/// On Flutter Web [isFsdbFile] works normally; all other methods throw
/// [UnsupportedError].
class FsdbConversionService {
  const FsdbConversionService({
    FsdbProcessRunner? processRunner,
    FsdbExecutableLocator? executableLocator,
    AppCacheDirectoryResolver? appCacheDirResolver,
  }) : _processRunner = processRunner ?? _defaultProcessRunner,
       _locator = executableLocator ?? _defaultLocator,
       _appCacheDir = appCacheDirResolver ?? defaultAppCacheDirectory;

  /// Suffix of the sidecar that marks `<base>.fst` / `<base>.vcd` in a
  /// directory as WaveCrux's conversion of `<base>.fsdb`, and records the
  /// FSDB size the conversion was made from.
  @visibleForTesting
  static const String sidecarSuffix = '.fsdbcache.json';

  final FsdbProcessRunner _processRunner;
  final FsdbExecutableLocator _locator;
  final AppCacheDirectoryResolver _appCacheDir;

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

  /// Returns the path to a cached FST for [fsdbPath] if WaveCrux converted it
  /// earlier and the conversion is still current: the `.fst` is newer than
  /// the FSDB file and its sidecar records the FSDB's size. The cache sits
  /// alongside the original FSDB file, or in the app-cache directory when
  /// the sibling name was taken by a file WaveCrux did not write.
  ///
  /// A `<base>.fst` beside the FSDB without the sidecar is not a cache: it is
  /// the user's own file, whatever its timestamp.
  ///
  /// Returns null if no cache exists or the cache is stale.
  /// Throws [UnsupportedError] on Flutter Web.
  Future<String?> getCachedFst(String fsdbPath) async {
    if (kIsWeb) throw UnsupportedError('Not supported on web');
    final base = p.basenameWithoutExtension(fsdbPath);
    final siblingDir = p.dirname(fsdbPath);
    if (_isFreshConversion(siblingDir, base, fsdbPath)) {
      return p.join(siblingDir, '$base.fst');
    }
    final String cacheDir;
    try {
      cacheDir = await _appCacheOutputDir(fsdbPath);
    } on Object {
      return null;
    }
    if (_isFreshConversion(cacheDir, base, fsdbPath)) {
      return p.join(cacheDir, '$base.fst');
    }
    return null;
  }

  bool _isFreshConversion(String dir, String base, String fsdbPath) {
    final fstFile = File(p.join(dir, '$base.fst'));
    if (!fstFile.existsSync()) return false;
    final fsdbStat = File(fsdbPath).statSync();
    if (!fstFile.lastModifiedSync().isAfter(fsdbStat.modified)) return false;
    final sidecar = File(p.join(dir, '$base$sidecarSuffix'));
    if (!sidecar.existsSync()) return false;
    try {
      final json = jsonDecode(sidecar.readAsStringSync());
      return json is Map && json['sourceSize'] == fsdbStat.size;
    } on Object {
      return false;
    }
  }

  /// The app-cache directory a conversion of [fsdbPath] goes to when the
  /// sibling names are taken. One directory per FSDB path, so the converted
  /// file keeps the FSDB's base name (it becomes the tab title).
  Future<String> _appCacheOutputDir(String fsdbPath) async {
    final root = await _appCacheDir();
    return p.join(
      root.path,
      'legacy_conversions',
      'fsdb',
      stableSourcePathHash(fsdbPath),
    );
  }

  /// Where the conversion of [fsdbPath] writes when no `outputDir` is given:
  /// beside the FSDB, unless one of the names it would write exists there
  /// without WaveCrux's sidecar.
  Future<String> _defaultOutputDir(String fsdbPath, String base) async {
    final siblingDir = p.dirname(fsdbPath);
    final ours = File(p.join(siblingDir, '$base$sidecarSuffix')).existsSync();
    final taken = ['$base.fst', '$base.vcd', '$base.vcd.tmp'].any(
      (name) => File(p.join(siblingDir, name)).existsSync(),
    );
    if (ours || !taken) return siblingDir;
    try {
      final dir = await _appCacheOutputDir(fsdbPath);
      Directory(dir).createSync(recursive: true);
      return dir;
    } on Object catch (e) {
      throw FsdbConversionException(
        'a file named $base.fst or $base.vcd already exists beside the FSDB '
        'file and the app cache is unavailable ($e)',
      );
    }
  }

  void _recordSuccess(String dir, String base, String fsdbPath) =>
      _writeSidecar(dir, base, fsdbPath, size: File(fsdbPath).statSync().size);

  void _writeSidecar(String dir, String base, String fsdbPath, {int? size}) {
    File(p.join(dir, '$base$sidecarSuffix')).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'sourcePath': fsdbPath,
        'sourceSize': ?size,
        if (size == null) 'pending': true,
      }),
    );
  }

  /// Converts [fsdbPath] to FST (or VCD if `vcd2fst` is not in `$PATH`).
  ///
  /// Step 1: runs `fsdb2vcd [fsdbPath]` and captures stdout to a temp VCD.
  /// Step 2: if `vcd2fst` is found, runs `vcd2fst [vcd] [fst]` → returns the
  ///   FST path.  Otherwise renames the temp VCD to `<base>.vcd` and returns
  ///   that path.
  ///
  /// The output file is placed in [outputDir] when given. Otherwise it goes
  /// in the same directory as [fsdbPath], unless a file WaveCrux did not
  /// write already holds one of the output names there; then it goes to a
  /// per-FSDB app-cache directory (see the class comment).
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

    final base = p.basenameWithoutExtension(fsdbPath);
    final dir = outputDir ?? await _defaultOutputDir(fsdbPath, base);
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
      // Mark the output names as ours before the first write, so a failed
      // run's leftovers are reconverted in place next time; the sidecar
      // records no size yet, so it is never a cache hit.
      _writeSidecar(dir, base, fsdbPath);
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
        _recordSuccess(dir, base, fsdbPath);
        return outputFstPath;
      } else {
        // No vcd2fst available: keep the intermediate VCD.
        await File(tempVcdPath).rename(outputVcdPath);
        _recordSuccess(dir, base, fsdbPath);
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
