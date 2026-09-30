// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart' show requireSpawnExecutableForHost;
import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/models/platform_info.dart';

/// Collects a [PlatformInfo] snapshot from the host environment.
///
/// All collection is best-effort: any field that cannot be determined is set
/// to null or an empty string rather than throwing.
class PlatformInfoService {
  const PlatformInfoService();

  /// Build a [PlatformInfo] from the current runtime environment.
  ///
  /// Pass [screens] with display metrics gathered from
  /// `PlatformDispatcher.instance.views` at the call site (the service layer
  /// avoids importing dart:ui to keep it easily testable).
  PlatformInfo collect({List<ScreenInfo> screens = const []}) {
    if (kIsWeb) {
      return PlatformInfo(
        operatingSystem: 'web',
        osVersion: '',
        cpuArchitecture: 'wasm',
        cpuCores: 0,
        locale: '',
        dartVersion: '',
        screens: screens,
      );
    }

    return PlatformInfo(
      operatingSystem: Platform.operatingSystem,
      osVersion: _osVersion(),
      cpuArchitecture: _cpuArch(),
      cpuCores: Platform.numberOfProcessors,
      locale: Platform.localeName,
      dartVersion: _parseDartVersion(Platform.version),
      totalRamBytes: _totalRamBytes(),
      screens: screens,
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  static String _osVersion() {
    try {
      return Platform.operatingSystemVersion;
    } on Object catch (_) {
      return '';
    }
  }

  /// CPU architecture parsed from [Platform.version], which always ends with
  /// `on "<os>_<arch>"` (e.g. `on "macos_arm64"`).
  ///
  /// Avoids `dart:ffi` (`Abi.current()`) so this service compiles on web.
  /// Web callers never reach this method — [collect] returns the `wasm`
  /// constant before falling through to platform queries.
  static String _cpuArch() => parseCpuArch(Platform.version);

  /// Visible for testing.  Extracts the architecture token from a
  /// [Platform.version] string. Falls back to `'unknown'` on parse failure.
  static String parseCpuArch(String platformVersion) {
    try {
      // Platform.version example:
      //   3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on "macos_arm64"
      final match = RegExp(
        r'''on ['"]\w+_(\w+)['"]''',
      ).firstMatch(platformVersion);
      if (match != null) return match.group(1)!;
    } on Object catch (_) {}
    return 'unknown';
  }

  /// Parses the Dart VM version string into a short "version (channel)" form.
  ///
  /// `Platform.version` looks like:
  ///   "3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on 'macos_arm64'"
  /// Returns "3.5.3 (stable)", or the raw string on parse failure.
  static String parseDartVersion(String raw) {
    final match = RegExp(r'(\d+\.\d+\.\d+)\s+\((\w+)\)').firstMatch(raw);
    if (match != null) return '${match.group(1)} (${match.group(2)})';
    // Fall back to just the first token (the version number).
    final first = raw.trim().split(' ').first;
    return first.isEmpty ? raw : first;
  }

  static String _parseDartVersion(String raw) => parseDartVersion(raw);

  /// Returns total physical RAM in bytes, or null if unavailable.
  ///
  /// Uses platform-specific read-only queries:
  ///   - Linux  : reads /proc/meminfo  (no subprocess)
  ///   - macOS  : `sysctl -n hw.memsize`
  ///   - Windows: `wmic OS get TotalVisibleMemorySize /Value`
  static int? _totalRamBytes() {
    try {
      if (Platform.isLinux) return _ramLinux();
      if (Platform.isMacOS) return _ramMacOS();
      if (Platform.isWindows) return _ramWindows();
    } on Object catch (_) {}
    return null;
  }

  static int? _ramLinux() {
    try {
      final content = File('/proc/meminfo').readAsStringSync();
      final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(content);
      if (match != null) return int.parse(match.group(1)!) * 1024;
    } on Object catch (_) {}
    return null;
  }

  static int? _ramMacOS() {
    try {
      final result = Process.runSync('sysctl', ['-n', 'hw.memsize']);
      if (result.exitCode == 0) {
        return int.tryParse((result.stdout as String).trim());
      }
    } on Object catch (_) {}
    return null;
  }

  static int? _ramWindows() {
    try {
      // Bare `wmic` would let CreateProcess consult WaveCrux's current
      // directory — the shell it was launched from — ahead of the system
      // directories, so a `wmic.exe` in a checked-out repository would run
      // when a user opens the diagnostics snapshot. When nothing on PATH
      // answers to `wmic` (it is optional on current Windows), this throws
      // before anything is spawned and the RAM total reads as unknown.
      final result = Process.runSync(
        requireSpawnExecutableForHost('wmic'),
        ['OS', 'get', 'TotalVisibleMemorySize', '/Value'],
      );
      if (result.exitCode == 0) {
        final match = RegExp(
          r'TotalVisibleMemorySize=(\d+)',
        ).firstMatch(result.stdout as String);
        if (match != null) {
          return int.parse(match.group(1)!) * 1024; // wmic returns KB
        }
      }
    } on Object catch (_) {}
    return null;
  }
}
