// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Local-development fallback build metadata.
///
/// CI runs `tool/generate_build_info.dart` which overwrites
/// `lib/core/app_info/build_info.dart` with the real git SHA, Flutter version,
/// OS, and architecture for the release build. That generated file is listed in
/// `.gitignore` so this fallback is what developers see when running locally.
///
/// The About dialog always has something to display; it never crashes on
/// missing build info.
const String kBuildVersion = '0.1.0';
const String kBuildNumber = '0';
const String kBuildGitSha = 'dev';
const String kBuildOs = 'dev';
const String kBuildArchitecture = 'dev';
const String kBuildFlutterVersion = 'dev';
const String kBuildDartVersion = 'dev';
