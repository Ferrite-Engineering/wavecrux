// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent record of which `.wcrux-widget` bundles the user has
/// manually loaded and which directories they have asked the loader to
/// watch.
///
/// Backed by [SharedPreferences] so the configuration survives app
/// restart. The store does **not** validate that the recorded paths still
/// exist — that is the loader's job at startup. A path that has been
/// deleted on disk surfaces in the Settings panel as a non-fatal stale
/// entry which the user can dismiss.
@immutable
class CustomWidgetBundleStoreState {
  const CustomWidgetBundleStoreState({
    this.manualBundlePaths = const [],
    this.watchedDirectories = const [],
  });

  /// Paths of bundles the user explicitly loaded via the file picker.
  final List<String> manualBundlePaths;

  /// Directories the user asked the loader to watch for `.wcrux-widget`
  /// files.
  final List<String> watchedDirectories;

  CustomWidgetBundleStoreState copyWith({
    List<String>? manualBundlePaths,
    List<String>? watchedDirectories,
  }) => CustomWidgetBundleStoreState(
    manualBundlePaths: manualBundlePaths ?? this.manualBundlePaths,
    watchedDirectories: watchedDirectories ?? this.watchedDirectories,
  );

  @override
  bool operator ==(Object other) =>
      other is CustomWidgetBundleStoreState &&
      _listEquals(manualBundlePaths, other.manualBundlePaths) &&
      _listEquals(watchedDirectories, other.watchedDirectories);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(manualBundlePaths),
    Object.hashAll(watchedDirectories),
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Reads and writes [CustomWidgetBundleStoreState] via [SharedPreferences].
///
/// Two string-list keys: one for manually loaded bundle paths, one for
/// watched directories. Both lists deduplicate by path on add and preserve
/// insertion order so the Settings panel shows entries in the order the
/// user added them.
class CustomWidgetBundleStore {
  /// Creates a store that reads and writes via the supplied [prefs]
  /// instance. Tests pass `SharedPreferences.setMockInitialValues`-backed
  /// instances; production code constructs via [load].
  CustomWidgetBundleStore({required SharedPreferences prefs}) : _prefs = prefs;

  /// Convenience constructor that opens the platform [SharedPreferences]
  /// instance.
  static Future<CustomWidgetBundleStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CustomWidgetBundleStore(prefs: prefs);
  }

  static const String _manualBundlesKey = 'stage_pro.custom_widget_bundles';
  static const String _watchedDirsKey = 'stage_pro.custom_widget_watched_dirs';

  final SharedPreferences _prefs;

  /// Returns the current persisted state.
  CustomWidgetBundleStoreState read() {
    return CustomWidgetBundleStoreState(
      manualBundlePaths: _prefs.getStringList(_manualBundlesKey) ?? const [],
      watchedDirectories: _prefs.getStringList(_watchedDirsKey) ?? const [],
    );
  }

  /// Persists [state] to platform storage. Returns the persisted state so
  /// callers can chain reads.
  Future<CustomWidgetBundleStoreState> write(
    CustomWidgetBundleStoreState state,
  ) async {
    await _prefs.setStringList(_manualBundlesKey, state.manualBundlePaths);
    await _prefs.setStringList(_watchedDirsKey, state.watchedDirectories);
    return state;
  }

  /// Adds [path] to the manual-bundle list if not already present and
  /// persists. Returns the updated state.
  Future<CustomWidgetBundleStoreState> addManualBundle(String path) async {
    final current = read();
    if (current.manualBundlePaths.contains(path)) return current;
    return await write(
      current.copyWith(
        manualBundlePaths: [...current.manualBundlePaths, path],
      ),
    );
  }

  /// Removes [path] from the manual-bundle list and persists.
  Future<CustomWidgetBundleStoreState> removeManualBundle(String path) async {
    final current = read();
    final updated = current.manualBundlePaths.where((p) => p != path).toList();
    return await write(current.copyWith(manualBundlePaths: updated));
  }

  /// Adds [path] to the watched-directories list and persists.
  Future<CustomWidgetBundleStoreState> addWatchedDirectory(String path) async {
    final current = read();
    if (current.watchedDirectories.contains(path)) return current;
    return await write(
      current.copyWith(
        watchedDirectories: [...current.watchedDirectories, path],
      ),
    );
  }

  /// Removes [path] from the watched-directories list and persists.
  Future<CustomWidgetBundleStoreState> removeWatchedDirectory(
    String path,
  ) async {
    final current = read();
    final updated = current.watchedDirectories.where((p) => p != path).toList();
    return await write(current.copyWith(watchedDirectories: updated));
  }
}
