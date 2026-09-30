// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wavecrux/domain/models/last_session_manifest.dart';

/// Saves and loads the lightweight last-session manifest used by the startup
/// tab-restoration feature (`AppSettings.restoreTabsOnLaunch`).
///
/// The manifest is written to `{appSupportDir}/last_session.json` on quit and
/// read on the next cold start. It records only the file path and optional
/// session file path for each open tab — per-tab state lives in the individual
/// `.wavecrux` session files.
///
/// On web or when `path_provider` is unavailable, all operations degrade
/// gracefully to no-ops or empty returns.
///
/// Pass [directoryFactory] to override the directory used for storage — useful
/// in tests that need a temp directory instead of the real app support dir.
class LastSessionService {
  const LastSessionService({Future<Directory> Function()? directoryFactory})
    : _directoryFactory = directoryFactory;

  final Future<Directory> Function()? _directoryFactory;

  static const _kFileName = 'last_session.json';

  /// Persists [manifest] to `{appSupportDir}/last_session.json`.
  ///
  /// Silently swallows I/O errors — a failed save is non-fatal; the worst
  /// outcome is that the next launch does not restore tabs.
  Future<void> save(LastSessionManifest manifest) async {
    try {
      final file = await _manifestFile();
      if (file == null) return;
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
    } on Exception catch (_) {
      // Non-fatal — silently ignore.
    }
  }

  /// Loads the manifest from `{appSupportDir}/last_session.json`.
  ///
  /// Returns [LastSessionManifest.empty] when the file does not exist, cannot
  /// be read, or contains invalid JSON — the caller never needs to handle an
  /// error state.
  Future<LastSessionManifest> load() async {
    try {
      final file = await _manifestFile();
      if (file == null || !file.existsSync()) return LastSessionManifest.empty;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return LastSessionManifest.empty;
      return LastSessionManifest.fromJson(decoded);
    } on Exception catch (_) {
      return LastSessionManifest.empty;
    }
  }

  /// Deletes the manifest file so a subsequent launch starts fresh.
  Future<void> clear() async {
    try {
      final file = await _manifestFile();
      if (file != null && file.existsSync()) await file.delete();
    } on Exception catch (_) {
      // Non-fatal.
    }
  }

  Future<File?> _manifestFile() async {
    try {
      final factory = _directoryFactory;
      final dir = factory != null
          ? await factory()
          : await getApplicationSupportDirectory();
      return File('${dir.path}/$_kFileName');
    } on Exception catch (_) {
      return null;
    }
  }
}
