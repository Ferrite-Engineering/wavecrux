// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Cache logic for LXT/LXT2 → FST convert-on-open.
//
// Desktop/mobile only. The web build has no filesystem siblings to write
// into and no conversion cache at all: [WaveformSourceNotifier.openFromBytes]
// converts the picked bytes in memory on every open.
//
// Strategy (the cache lookup logic):
//
//   1. Try the sibling location first: `<source-basename-no-ext>.fst` in
//      the same directory as the source. This is the path a user actually
//      sees and it makes a re-open of the source file instantaneous.
//   2. If the sibling directory is not writable (sandboxed cloud mount,
//      read-only share, removable media), fall back to
//      `${appCacheDir}/legacy_conversions/<sha256-of-source-path>.fst`.
//   3. On open, consider a cached `.fst` *fresh* iff:
//        a) its mtime ≥ source mtime, AND
//        b) the sidecar `.lxt2cache.json` records a matching source size.
//      A stale cache (source touched, copied with different size, etc.)
//      causes reconversion.
//
// The size check matters: a file copy preserving mtime would otherwise
// look fresh even when the underlying capture changed. SHA-256 of the
// whole file is overkill for an archive workflow — size + mtime is a
// strong enough fingerprint for the audience that has these files.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the directory used for the app-cache fallback path.
/// Injectable so tests don't have to hit `path_provider`.
typedef AppCacheDirectoryResolver = Future<Directory> Function();

Future<Directory> _defaultAppCacheDir() async {
  // `getApplicationCacheDirectory` is the right target
  // ("${appCacheDir}/legacy_conversions"), but it is not yet wired on
  // every platform in this project. Fall back to ApplicationSupport which
  // the rest of the codebase already relies on.
  try {
    return await getApplicationCacheDirectory();
  } on Object {
    return await getApplicationSupportDirectory();
  }
}

/// Decision returned by [Lxt2FstCache.resolve] describing how the open
/// path should proceed for a given source file.
@immutable
class Lxt2CacheDecision {
  const Lxt2CacheDecision({
    required this.fstPath,
    required this.fromCache,
    required this.isSibling,
  });

  /// Absolute path where the converted FST either already lives (when
  /// [fromCache] is `true`) or where the converter must write it (when
  /// `false`).
  final String fstPath;

  /// `true` when [fstPath] is a fresh, reusable cache hit — the caller
  /// skips the converter entirely and hands the path to wellen directly.
  final bool fromCache;

  /// `true` when [fstPath] is the sibling-of-source location, `false` when
  /// it is the app-cache fallback.
  final bool isSibling;
}

/// Cache helper for the LXT/LXT2 convert-on-open path. Stateless apart
/// from the injected [AppCacheDirectoryResolver]; safe to construct on
/// demand.
class Lxt2FstCache {
  Lxt2FstCache({AppCacheDirectoryResolver? appCacheDirResolver})
    : _appCacheDir = appCacheDirResolver ?? _defaultAppCacheDir;

  /// Filename of the sidecar metadata that records the source size used
  /// to detect stale caches. Lives next to the cached FST.
  @visibleForTesting
  static const String sidecarSuffix = '.lxt2cache.json';

  /// Subdirectory under the app-cache root that holds fallback FSTs.
  @visibleForTesting
  static const String appCacheSubdir = 'legacy_conversions';

  final AppCacheDirectoryResolver _appCacheDir;

  /// Decide where the converted FST for [sourcePath] should live and
  /// whether the existing on-disk file is a fresh cache hit.
  ///
  /// The returned [Lxt2CacheDecision.fstPath] is guaranteed to be in a
  /// directory the caller can write to: either the sibling directory
  /// (when writable) or the app-cache subdirectory (always writable).
  Future<Lxt2CacheDecision> resolve(String sourcePath) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Lxt2FstCache is desktop/mobile-only — the web build converts in '
        'memory on every open and has no conversion cache.',
      );
    }
    final source = File(sourcePath);
    final sourceStat = source.statSync();
    final sourceMTime = sourceStat.modified;
    final sourceSize = sourceStat.size;

    final sibling = _siblingFstPath(sourcePath);
    final siblingWritable = _isWritable(p.dirname(sibling));
    if (siblingWritable) {
      final fresh = _isFresh(
        fstPath: sibling,
        sourceMTime: sourceMTime,
        sourceSize: sourceSize,
      );
      return Lxt2CacheDecision(
        fstPath: sibling,
        fromCache: fresh,
        isSibling: true,
      );
    }

    final fallback = await _appCacheFstPath(sourcePath);
    final fresh = _isFresh(
      fstPath: fallback,
      sourceMTime: sourceMTime,
      sourceSize: sourceSize,
    );
    return Lxt2CacheDecision(
      fstPath: fallback,
      fromCache: fresh,
      isSibling: false,
    );
  }

  /// Record a successful conversion: writes the sidecar metadata so future
  /// [resolve] calls can detect stale caches.
  Future<void> recordSuccess({
    required String sourcePath,
    required String fstPath,
  }) async {
    if (kIsWeb) return;
    final stat = File(sourcePath).statSync();
    final sidecar = File('$fstPath$sidecarSuffix');
    sidecar.parent.createSync(recursive: true);
    sidecar.writeAsStringSync(
      jsonEncode(<String, Object?>{
        'sourcePath': sourcePath,
        'sourceSize': stat.size,
        'sourceMTime': stat.modified.toUtc().toIso8601String(),
      }),
    );
  }

  /// Compute the sibling-FST path: `<basename-no-ext>.fst` next to source.
  @visibleForTesting
  String siblingFstPathForTest(String sourcePath) =>
      _siblingFstPath(sourcePath);

  /// Compute the app-cache fallback FST path.
  Future<String> appCacheFstPathForTest(String sourcePath) =>
      _appCacheFstPath(sourcePath);

  String _siblingFstPath(String sourcePath) {
    final dir = p.dirname(sourcePath);
    final base = p.basenameWithoutExtension(sourcePath);
    return p.join(dir, '$base.fst');
  }

  Future<String> _appCacheFstPath(String sourcePath) async {
    final base = await _appCacheDir();
    final subdir = Directory(p.join(base.path, appCacheSubdir))
      ..createSync(recursive: true);
    return p.join(subdir.path, '${_stableHashHex(sourcePath)}.fst');
  }

  bool _isFresh({
    required String fstPath,
    required DateTime sourceMTime,
    required int sourceSize,
  }) {
    final fst = File(fstPath);
    if (!fst.existsSync()) return false;
    final fstStat = fst.statSync();
    if (fstStat.modified.isBefore(sourceMTime)) return false;
    final sidecar = File('$fstPath$sidecarSuffix');
    if (!sidecar.existsSync()) return false;
    try {
      final raw = sidecar.readAsStringSync();
      final json = jsonDecode(raw);
      if (json is! Map) return false;
      final storedSize = json['sourceSize'];
      if (storedSize is! int || storedSize != sourceSize) return false;
      return true;
    } on Object {
      return false;
    }
  }

  /// Test if [dir] is writable by attempting to create a small temp file.
  ///
  /// The cheap-and-correct approach. Probing permissions via stat() lies
  /// in too many sandbox scenarios (macOS app-sandbox advertises +w on
  /// dirs the user did not grant; cloud-storage providers similarly lie).
  bool _isWritable(String dir) {
    final probe = File(
      p.join(
        dir,
        '.wavecrux_lxt2_writeprobe_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      probe
        ..writeAsBytesSync(const <int>[0])
        ..deleteSync();
      return true;
    } on Object {
      return false;
    }
  }
}

/// Stable 32-bit FNV-1a hash of [input], rendered as an 8-char lowercase
/// hex string. Used as the app-cache filename for a source path so that
/// reopening the same file always lands on the same cached `.fst`. Not
/// cryptographic — only collision resistance for cache filenames matters,
/// and a 32-bit hash is plenty at that scale. Two independent runs are
/// combined to give the filename eight extra hex digits of entropy
/// without overflowing JS's 53-bit safe integer range.
String _stableHashHex(String input) {
  const fnvOffset = 0x811c9dc5;
  const fnvPrime = 0x01000193;
  const mask = 0xffffffff;
  final bytes = utf8.encode(input);
  var hashA = fnvOffset;
  for (final byte in bytes) {
    hashA = ((hashA ^ byte) * fnvPrime) & mask;
  }
  // Independent run starting from a swizzled seed gives extra entropy
  // without needing 64-bit arithmetic.
  var hashB = fnvOffset ^ 0xdeadbeef;
  for (final byte in bytes.reversed) {
    hashB = ((hashB ^ byte) * fnvPrime) & mask;
  }
  return hashA.toRadixString(16).padLeft(8, '0') +
      hashB.toRadixString(16).padLeft(8, '0');
}
