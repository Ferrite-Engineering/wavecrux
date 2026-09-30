// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Immutable snapshot of version, build, and platform metadata for the
/// running WaveCrux instance.
///
/// Populated from the generated `build_info.dart` file (refreshed by CI via
/// `tool/generate_build_info.dart`). Locally the generator writes fallback
/// "dev" values so the About box always has something to display.
@immutable
final class ApplicationBuildInfo {
  const ApplicationBuildInfo({
    required this.version,
    required this.buildNumber,
    required this.gitSha,
    required this.os,
    required this.architecture,
    required this.flutterVersion,
    required this.dartVersion,
  });

  /// Human-readable semver string, e.g. `"1.2.3"`.
  final String version;

  /// Platform build number, e.g. `"42"`.
  final String buildNumber;

  /// Short git commit SHA, e.g. `"abc1234"`. `"dev"` locally.
  final String gitSha;

  /// Operating system name, e.g. `"macOS 15.4"`.
  final String os;

  /// CPU architecture, e.g. `"arm64"` or `"x86_64"`.
  final String architecture;

  /// Flutter SDK version string.
  final String flutterVersion;

  /// Dart SDK version string.
  final String dartVersion;

  @override
  bool operator ==(Object other) =>
      other is ApplicationBuildInfo &&
      other.version == version &&
      other.buildNumber == buildNumber &&
      other.gitSha == gitSha &&
      other.os == os &&
      other.architecture == architecture &&
      other.flutterVersion == flutterVersion &&
      other.dartVersion == dartVersion;

  @override
  int get hashCode => Object.hash(
    version,
    buildNumber,
    gitSha,
    os,
    architecture,
    flutterVersion,
    dartVersion,
  );
}
