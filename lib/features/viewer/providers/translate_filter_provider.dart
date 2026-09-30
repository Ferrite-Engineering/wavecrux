// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';

part 'translate_filter_provider.g.dart';

/// Captures translate-filter load/parse failures into the issue-reporter buffer.
final _log = Logger('wavecrux.translate');

/// Manages parsed GTKWave translate filters assigned to signals in the viewer.
///
/// State is a [Map<String, TranslateFilter>] keyed by signal ref.  The raw
/// file-path assignments are tracked separately in [filterPaths] for session
/// persistence — [SessionNotifier] reads them via [filterPaths] when building
/// a session snapshot and calls [restoreFromSession] when loading one.
@Riverpod(keepAlive: true)
class TranslateFilterNotifier extends _$TranslateFilterNotifier {
  static const _service = TranslateFilterService();

  // signalRef → absolute file path, mirrored from state for session snapshot.
  final Map<String, String> _paths = {};

  @override
  Map<String, TranslateFilter> build() => const {};

  /// Reads and parses the filter file at [filePath], then assigns it to
  /// [signalRef].
  ///
  /// Gracefully swallows I/O and parse errors (logs a warning).
  Future<void> assignFilter(String signalRef, String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      final filter = _service.parse(content);
      _paths[signalRef] = filePath;
      state = Map<String, TranslateFilter>.unmodifiable({
        ...state,
        signalRef: filter,
      });
    } on Exception catch (e) {
      _log.warning('Failed to load translate filter "$filePath": $e');
    }
  }

  /// Removes the translate filter assigned to [signalRef].  No-op if none.
  void removeFilter(String signalRef) {
    if (!state.containsKey(signalRef)) return;
    _paths.remove(signalRef);
    state = Map<String, TranslateFilter>.unmodifiable(
      Map<String, TranslateFilter>.from(state)..remove(signalRef),
    );
  }

  /// Returns the [TranslateFilter] assigned to [signalRef], or null.
  TranslateFilter? getFilter(String signalRef) => state[signalRef];

  /// Returns the current signalRef → file-path assignments for session
  /// persistence.  The returned map is unmodifiable.
  Map<String, String> get filterPaths => Map.unmodifiable(_paths);

  /// Removes all translate filters and resets state to empty.
  ///
  /// Called by [WaveformSourceNotifier] when a new file is opened or the
  /// current file is closed, so that stale filters from a previous file are
  /// not applied to signals in the new file that happen to share the same ref.
  void clearAll() {
    _paths.clear();
    state = const {};
  }

  /// Clears all filters and reloads them from [paths].
  ///
  /// Called by [SessionNotifier] when restoring a saved session.  Files that
  /// cannot be read are silently skipped.
  Future<void> restoreFromSession(Map<String, String> paths) async {
    _paths.clear();
    state = const {};
    for (final entry in paths.entries) {
      await assignFilter(entry.key, entry.value);
    }
  }
}
