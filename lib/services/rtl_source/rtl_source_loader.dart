// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

/// Thrown when an RTL source file referenced from a stems file cannot be read.
class RtlSourceLoadException implements Exception {
  const RtlSourceLoadException(this.filePath, this.reason);

  final String filePath;
  final String reason;

  @override
  String toString() => 'RtlSourceLoadException($filePath): $reason';
}

/// In-memory representation of a loaded RTL source file: the original path
/// and the per-line text (with platform line endings normalised to `\n`).
@immutable
class RtlSourceFile {
  const RtlSourceFile({required this.path, required this.lines});

  final String path;
  final List<String> lines;

  int get lineCount => lines.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtlSourceFile &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          _listEquals(lines, other.lines);

  @override
  int get hashCode => Object.hash(path, Object.hashAll(lines));

  @override
  String toString() => 'RtlSourceFile($path, $lineCount lines)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Loads RTL source files from disk for the source-annotation panel.
///
/// Caches by absolute file path so repeated lookups (e.g. cursor moves
/// re-resolving the same file) don't re-read the disk.  Cache entries
/// invalidate when the file's modification time changes.
///
/// **The cache is bounded and evicted least-recently-used.** The loader is
/// owned by a `keepAlive` notifier, so it outlives every document the user
/// opens; it was cleared only when a stems file was loaded or dropped.
/// Walking an SoC's signals therefore accumulated the full line list of
/// every source file visited — one `List<String>` per file, for the life
/// of the session, whether or not the panel would ever show it again. Two
/// bounds, whichever binds first: [maxCachedFiles] entries and
/// [maxCachedLines] retained lines, so one generated multi-hundred-thousand
/// line netlist cannot sit in the cache behind a count that says 3 files.
/// Eviction costs a re-read of a file the user has navigated away from.
///
/// `Map` preserves insertion order; the LRU ordering is maintained by
/// removing and re-inserting an entry on read — the same shape as the
/// NetCrux schematic painter's label-layout cache.
///
/// On Flutter Web the loader is a no-op — RTL source annotation is desktop
/// only (gated upstream on `deviceClassProvider`), and the web build has no
/// `dart:io` access to local source files.
class RtlSourceLoader {
  RtlSourceLoader({
    FileReader? fileReader,
    this.maxCachedFiles = 32,
    this.maxCachedLines = 200000,
  }) : _fileReader = fileReader ?? const _DefaultFileReader();

  /// Maximum source files retained at once. Comfortably more than a
  /// debugging session moves between before it forgets one.
  final int maxCachedFiles;

  /// Maximum lines retained across every cached file.
  final int maxCachedLines;

  final FileReader _fileReader;
  final Map<String, _CacheEntry> _cache = {};
  int _cachedLines = 0;

  /// Files currently held. Exposed so the bound can be asserted.
  @visibleForTesting
  int get cachedFileCount => _cache.length;

  /// Lines currently held across every cached file.
  @visibleForTesting
  int get cachedLineCount => _cachedLines;

  /// Loads [path] and returns its parsed [RtlSourceFile].
  ///
  /// Throws [RtlSourceLoadException] when the file does not exist or cannot
  /// be read.
  Future<RtlSourceFile> load(String path) async {
    final stat = await _fileReader.stat(path);
    if (stat == null) {
      throw RtlSourceLoadException(path, 'file not found');
    }
    final cached = _cache.remove(path);
    if (cached != null && cached.modified == stat.modified) {
      // Re-insert: most-recently-used goes to the tail.
      _cache[path] = cached;
      return cached.file;
    }
    if (cached != null) _cachedLines -= cached.file.lineCount;
    final String contents;
    try {
      contents = await _fileReader.readAsString(path);
    } on Exception catch (e) {
      throw RtlSourceLoadException(path, e.toString());
    }
    final file = RtlSourceFile(
      path: path,
      lines: _splitLines(contents),
    );
    _cache[path] = _CacheEntry(file: file, modified: stat.modified);
    _cachedLines += file.lineCount;
    _evictToBounds();
    return file;
  }

  /// Drops a cached file (e.g. when a stems file is re-loaded).
  void invalidate(String path) {
    final removed = _cache.remove(path);
    if (removed != null) _cachedLines -= removed.file.lineCount;
  }

  /// Drops every cached file.
  void clear() {
    _cache.clear();
    _cachedLines = 0;
  }

  /// Evicts least-recently-used entries until both bounds hold. The
  /// just-loaded file is the newest, so it is never the victim (a single
  /// file larger than [maxCachedLines] is kept — the alternative is a
  /// cache that can never hold the file the user is reading).
  void _evictToBounds() {
    while (_cache.length > 1 &&
        (_cache.length > maxCachedFiles || _cachedLines > maxCachedLines)) {
      final oldest = _cache.keys.first;
      final entry = _cache.remove(oldest)!;
      _cachedLines -= entry.file.lineCount;
    }
  }

  static List<String> _splitLines(String contents) {
    if (contents.isEmpty) return const [''];
    // Preserve final empty line when the file ends with `\n`.
    final normalised = contents.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalised.split('\n');
  }
}

class _CacheEntry {
  const _CacheEntry({required this.file, required this.modified});
  final RtlSourceFile file;
  final DateTime modified;
}

/// File-IO adapter abstracted to support a fake reader in unit tests.
abstract class FileReader {
  const FileReader();
  Future<RtlFileStat?> stat(String path);
  Future<String> readAsString(String path);
}

/// Lightweight stat result containing only the modification time.
@immutable
class RtlFileStat {
  const RtlFileStat({required this.modified});
  final DateTime modified;
}

class _DefaultFileReader extends FileReader {
  const _DefaultFileReader();

  @override
  Future<RtlFileStat?> stat(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final stat = file.statSync();
    return RtlFileStat(modified: stat.modified);
  }

  @override
  Future<String> readAsString(String path) => File(path).readAsString();
}
