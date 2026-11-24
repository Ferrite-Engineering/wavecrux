// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Build metadata for the About dialog.
///
/// The release build scripts (`scripts/_build_info.sh`, sourced by
/// `build_macos.sh`, `build_linux.sh` and `build_windows.sh`) pass the commit,
/// architecture, Flutter version and build year as `--dart-define`s, and this
/// file reads them with `String.fromEnvironment`. A local build passes none
/// of them, so the About dialog shows `dev` and never crashes on missing
/// build info.
const String kBuildVersion = '0.1.0';
const String kBuildNumber = '0';
const String kBuildOs = 'dev';
const String kBuildDartVersion = 'dev';

/// Short commit of a release build (`--dart-define=BUILD_COMMIT=<sha>`).
final String kBuildGitSha = resolveBuildFact(
  const String.fromEnvironment('BUILD_COMMIT'),
);

/// CPU architecture of a release build (`--dart-define=BUILD_ARCHITECTURE`).
final String kBuildArchitecture = resolveBuildFact(
  const String.fromEnvironment('BUILD_ARCHITECTURE'),
);

/// Flutter SDK version of a release build
/// (`--dart-define=BUILD_FLUTTER_VERSION`).
final String kBuildFlutterVersion = resolveBuildFact(
  const String.fromEnvironment('BUILD_FLUTTER_VERSION'),
);

/// Four-digit year the release was built (`--dart-define=BUILD_YEAR`).
const String kBuildYear = String.fromEnvironment('BUILD_YEAR');

/// A build fact as the About dialog shows it: the value a release build
/// passed, or `dev` when a local build passed none.
String resolveBuildFact(String raw) {
  final value = raw.trim();
  return value.isEmpty ? 'dev' : value;
}

/// The copyright year: the build year a release build passed, else the
/// current year (a local build has no build date of its own).
String resolveCopyrightYear(String raw, {DateTime? now}) {
  final value = raw.trim();
  if (RegExp(r'^\d{4}$').hasMatch(value)) return value;
  return (now ?? DateTime.now()).year.toString();
}
