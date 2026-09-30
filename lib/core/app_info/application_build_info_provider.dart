// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/app_info/application_build_info.dart';
import 'package:wavecrux/core/app_info/build_info_fallback.dart';

part 'application_build_info_provider.g.dart';

/// Provides [ApplicationBuildInfo] for the running WaveCrux instance.
///
/// Version and build number come from `package_info_plus` (reads the platform
/// bundle at runtime). Git SHA, Flutter/Dart versions, OS, and architecture
/// come from the generated `build_info.dart` written by CI; locally they fall
/// back to `"dev"` constants in [build_info_fallback.dart].
///
/// This provider is overridable by the Pro overlay to supply Pro-specific build
/// metadata if needed. The About dialog reads only from this provider.
@Riverpod(keepAlive: true)
Future<ApplicationBuildInfo> applicationBuildInfo(
  Ref ref,
) async {
  final info = await PackageInfo.fromPlatform();

  final os = _resolveOs();

  return ApplicationBuildInfo(
    version: info.version.isNotEmpty ? info.version : kBuildVersion,
    buildNumber: info.buildNumber.isNotEmpty ? info.buildNumber : kBuildNumber,
    gitSha: kBuildGitSha,
    os: os,
    architecture: kBuildArchitecture,
    flutterVersion: kBuildFlutterVersion,
    dartVersion: kBuildDartVersion,
  );
}

String _resolveOs() {
  if (kIsWeb) return 'Web';
  try {
    if (Platform.isMacOS) {
      return 'macOS ${Platform.operatingSystemVersion}';
    } else if (Platform.isLinux) {
      return 'Linux ${Platform.operatingSystemVersion}';
    } else if (Platform.isWindows) {
      return 'Windows ${Platform.operatingSystemVersion}';
    } else if (Platform.isIOS) {
      return 'iOS ${Platform.operatingSystemVersion}';
    } else if (Platform.isAndroid) {
      return 'Android ${Platform.operatingSystemVersion}';
    }
  } on Exception catch (_) {}
  return kBuildOs;
}
