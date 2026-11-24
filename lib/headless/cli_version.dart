// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The headless binary's version: `pubspec.yaml`'s version without its build
/// number. A plain constant because the binary has no Flutter and so no
/// `package_info_plus`; `test/headless/cli_version_test.dart` fails when it
/// and the pubspec disagree.
const String kWaveCruxCliVersion = '1.2.0';

/// The wellen release series the bundled `wellen_ffi` library builds against
/// (`native/wellen_ffi/Cargo.toml`), named as the engine in every document.
/// A series, not a patch release: the patch moves with the lockfile, which
/// a document need not track. The same test holds it to the manifest.
const String kWellenEngineVersion = '0.25';
