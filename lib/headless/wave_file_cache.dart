// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/services/wave_session/wave_queries.dart';
import 'package:wavecrux/services/waveform/wellen_provider_io.dart';

/// A waveform file opened for the command line: its source, its format and
/// an index of its signals.
class WaveFile {
  /// A file whose data [source] holds, in [format], released by [close].
  WaveFile({
    required this.source,
    required this.format,
    required Future<void> Function() close,
  }) : _close = close;

  /// The opened data.
  final WaveformDataSource source;

  /// The container format wellen read (`VCD`, `FST`, `GHW`, ...).
  final String format;

  final Future<void> Function() _close;

  /// Every signal by path and by reference.
  late final WaveSignalIndex index = WaveSignalIndex(source.rootScopes);

  /// Releases the file.
  Future<void> close() => _close();
}

/// Opens the waveform at [path], or throws what the reader threw.
typedef WaveFileOpener = Future<WaveFile> Function(String path);

/// Opens [path] through wellen, the reader the app uses on the desktop.
Future<WaveFile> openWithWellen(String path) async {
  final provider = WellenProvider();
  try {
    await provider.openFile(path);
  } on Object {
    await provider.closeAndRelease();
    rethrow;
  }
  return WaveFile(
    source: provider,
    format: provider.fileFormat,
    close: provider.closeAndRelease,
  );
}

/// The files a process keeps open: the [capacity] most recently used, keyed
/// by canonical path, size and modification time, so a file rewritten in
/// place by a new simulation run is read again and two spellings of one file
/// share an entry.
class WaveFileCache {
  /// A cache that opens through [opener] and keeps [capacity] files.
  WaveFileCache({this.opener = openWithWellen, this.capacity = 2})
    : assert(capacity > 0, 'a cache holds at least one file');

  /// How a file is opened.
  final WaveFileOpener opener;

  /// How many files stay open.
  final int capacity;

  // Least recently used first.
  final Map<String, WaveFile> _open = <String, WaveFile>{};

  /// The keys held, least recently used first.
  @visibleForTesting
  List<String> get keys => List<String>.unmodifiable(_open.keys);

  /// The key of the file at [path]: its canonical path, size and modification
  /// time. Throws a [FileSystemException] when it cannot be read.
  static String keyOf(String path) {
    final canonical = File(path).resolveSymbolicLinksSync();
    final stat = File(canonical).statSync();
    return '$canonical\n${stat.size}\n'
        '${stat.modified.microsecondsSinceEpoch}';
  }

  /// The file at [path], opened now or kept from an earlier call. Throws
  /// what the opener threw; nothing is kept for a file that failed to open.
  Future<WaveFile> open(String path) async {
    final key = keyOf(path);
    final kept = _open.remove(key);
    if (kept != null) {
      _open[key] = kept;
      return kept;
    }
    final opened = await opener(path);
    // An older copy of the same file (rewritten since) is never asked for
    // again; release it at once rather than when it ages out.
    final canonical = key.substring(0, key.indexOf('\n') + 1);
    final stale = _open.keys.where((k) => k.startsWith(canonical)).toList();
    for (final k in stale) {
      await _open.remove(k)!.close();
    }
    _open[key] = opened;
    while (_open.length > capacity) {
      final oldest = _open.keys.first;
      await _open.remove(oldest)!.close();
    }
    return opened;
  }

  /// Closes every file held.
  Future<void> closeAll() async {
    final files = _open.values.toList();
    _open.clear();
    for (final file in files) {
      await file.close();
    }
  }
}
