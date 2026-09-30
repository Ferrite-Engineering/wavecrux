// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:developer' as developer;
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Paths the user asked for and did not get. `developer.log` emits nothing
/// from a release build, so these go to the product log, where the issue
/// reporter collects them.
final _log = Logger('wavecrux.decoders.plugins');

/// Pure-data description of the host environment that
/// [PluginDirectoryResolver] needs to compute the platform-default
/// plugin directory.
///
/// The runtime layer (an isolate at app start) constructs a real one
/// from `Platform` and `path_provider`. Tests construct fakes with the
/// values they want to exercise — the resolver itself is platform-blind
/// once it has a context.
@immutable
class PluginPlatformContext {
  const PluginPlatformContext({
    required this.platform,
    required this.appSupportPath,
    this.environment = const <String, String>{},
  });

  /// Which host platform the resolver is running on. Drives default-path
  /// computation and path-separator selection for the env var.
  final PluginHostPlatform platform;

  /// The platform's per-user application-support directory. On macOS the
  /// real value is `~/Library/Application Support`; on Windows it is
  /// `%APPDATA%`; on Linux it is `$XDG_CONFIG_HOME` (with `~/.config`
  /// fallback). The real loader resolves this with `path_provider`'s
  /// `getApplicationSupportDirectory()` or env-var inspection; tests
  /// pass any string they like.
  final String appSupportPath;

  /// Environment variables visible to the host process. The resolver
  /// reads `WAVECRUX_DECODER_PATH` from this map. Defaults to empty so
  /// tests don't have to opt out of every variable.
  final Map<String, String> environment;

  /// Path-separator character for [environment] values that carry path
  /// lists. Colon on Unix-like platforms; semicolon on Windows.
  String get pathListSeparator =>
      platform == PluginHostPlatform.windows ? ';' : ':';
}

/// Identifies which host operating system the resolver is targeting.
///
/// Kept as a domain enum rather than a `Platform.is*` check so tests can
/// pump any value without trying to mock `dart:io`.
enum PluginHostPlatform {
  linux,
  macos,
  windows,
}

/// Locates decoder-plugin directories the FFI loader should scan.
///
/// Sources, in priority order:
///
///   1. The `WAVECRUX_DECODER_PATH` environment variable (path-list
///      separated by `:` on Unix, `;` on Windows). Relative paths are
///      rejected with a logged warning so plugins cannot accidentally
///      resolve from the current working directory.
///   2. User-configured directories from
///      [AppSettings.userPluginDirectories].
///   3. The platform-default per-user directory:
///        * Linux:   `<appSupport>/wavecrux/decoders`
///        * macOS:   `<appSupport>/wavecrux/decoders`
///        * Windows: `<appSupport>/WaveCrux/decoders`
///
/// The resolver itself does not create directories. Nonexistent
/// directories are dropped from the returned list with a logged
/// warning (only a debug trace for the platform default, which most
/// installs never create); on-demand creation is a Settings-panel
/// concern.
class PluginDirectoryResolver {
  /// Constructs a resolver for the given host context. Construction is
  /// cheap; one resolver per app run.
  const PluginDirectoryResolver({required this.context});

  /// The host environment this resolver was built for.
  final PluginPlatformContext context;

  /// Returns every candidate path the resolver knows about, in priority
  /// order, **before** existence filtering and **before** deduplication.
  /// Useful for diagnostics surfaces that want to show "the loader
  /// considered these paths but they did not exist".
  List<String> resolveCandidatePaths({
    List<String> userConfigured = const <String>[],
    String? envVarRaw,
  }) {
    final candidates = <String>[];
    final pathCtx = _pathContext;

    // 1. Environment variable. Relative paths are rejected.
    if (envVarRaw != null && envVarRaw.isNotEmpty) {
      final separator = context.pathListSeparator;
      for (final entry in envVarRaw.split(separator)) {
        final trimmed = entry.trim();
        if (trimmed.isEmpty) continue;
        if (!pathCtx.isAbsolute(trimmed)) {
          _log.warning(
            'ignoring relative path "$trimmed" in WAVECRUX_DECODER_PATH '
            '(only absolute paths are allowed)',
          );
          continue;
        }
        candidates.add(pathCtx.normalize(trimmed));
      }
    }

    // 2. User-configured paths from AppSettings.
    for (final entry in userConfigured) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      if (!pathCtx.isAbsolute(trimmed)) {
        _log.warning(
          'ignoring relative user-configured path "$trimmed" (only absolute '
          'paths are allowed)',
        );
        continue;
      }
      candidates.add(pathCtx.normalize(trimmed));
    }

    // 3. Platform default.
    candidates.add(_defaultPath());

    return _dedup(candidates);
  }

  /// Returns the resolved candidate paths whose backing directory
  /// exists on disk, as `Directory` objects ready to be scanned.
  /// Nonexistent directories are skipped with a logged warning.
  ///
  /// The optional [exists] override lets tests assert the resolver's
  /// scan logic without touching the real filesystem.
  List<Directory> resolveDirectories({
    List<String> userConfigured = const <String>[],
    String? envVarRaw,
    bool Function(String path)? exists,
  }) {
    final check = exists ?? _defaultExists;
    final candidates = resolveCandidatePaths(
      userConfigured: userConfigured,
      envVarRaw: envVarRaw,
    );
    final defaultPath = _defaultPath();
    final out = <Directory>[];
    for (final candidate in candidates) {
      if (check(candidate)) {
        out.add(Directory(candidate));
      } else if (candidate == defaultPath) {
        // The platform default is absent on most installs: nobody has put a
        // plugin there. A trace, not a fault.
        developer.log(
          'plugin_directory_resolver: default directory "$candidate" does '
          'not exist — skipping',
          name: 'plugin_directory_resolver',
        );
      } else {
        _log.warning(
          'plugin directory "$candidate" does not exist — skipping (create '
          'it, or remove it from Settings)',
        );
      }
    }
    return out;
  }

  String _defaultPath() {
    final pathCtx = _pathContext;
    switch (context.platform) {
      case PluginHostPlatform.linux:
        return pathCtx.normalize(
          pathCtx.join(context.appSupportPath, 'wavecrux', 'decoders'),
        );
      case PluginHostPlatform.macos:
        return pathCtx.normalize(
          pathCtx.join(context.appSupportPath, 'wavecrux', 'decoders'),
        );
      case PluginHostPlatform.windows:
        return pathCtx.normalize(
          pathCtx.join(context.appSupportPath, 'WaveCrux', 'decoders'),
        );
    }
  }

  /// `path` package Context configured for [PluginPlatformContext.platform].
  /// Using a context (rather than the top-level helpers in
  /// `package:path`) keeps path semantics correct regardless of which
  /// host the resolver itself is running on — important for tests.
  p.Context get _pathContext {
    switch (context.platform) {
      case PluginHostPlatform.windows:
        return p.windows;
      case PluginHostPlatform.linux:
      case PluginHostPlatform.macos:
        return p.posix;
    }
  }

  List<String> _dedup(List<String> input) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in input) {
      final key = _caseSensitive ? raw : raw.toLowerCase();
      if (seen.add(key)) {
        out.add(raw);
      }
    }
    return out;
  }

  /// Linux is case-sensitive at the filesystem level; macOS and Windows
  /// are typically case-insensitive (HFS+/APFS default and NTFS).
  bool get _caseSensitive => context.platform == PluginHostPlatform.linux;

  bool _defaultExists(String path) {
    return Directory(path).existsSync();
  }
}
