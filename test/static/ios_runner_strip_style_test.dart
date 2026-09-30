// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard for the iOS release-build FFI symbol export.
///
/// On iOS the Rust `libwellen_ffi.a` is statically linked into the Runner
/// executable and Dart resolves the `wellen_*` C ABI at runtime via
/// `DynamicLibrary.process()` + `dlsym`. The `WellenFFIKeepalive` translation
/// unit protects the symbols from link-time dead-stripping, but archive
/// (App Store / TestFlight) builds ALSO run `strip` on the executable as a
/// post-processing step. Under Xcode's default Strip Style for executables
/// ("All Symbols") that deletes the dlsym export trie wholesale, so every
/// waveform open fails on a physical device with
/// "Failed to lookup symbol 'wellen_open'" — while debug builds keep working,
/// because their code lives in the unstripped Runner.debug.dylib.
///
/// The fix is `STRIP_STYLE = "non-global"` on the Runner target's Release and
/// Profile configurations. This test fails if the setting disappears — e.g.
/// after the Xcode project is regenerated or upgraded.
void main() {
  test(
    'Runner Release/Profile configs keep STRIP_STYLE = non-global',
    () {
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');
      expect(
        pbxproj.existsSync(),
        isTrue,
        reason: 'expected ios/Runner.xcodeproj/project.pbxproj at repo root',
      );

      final offenders = missingStripStyleConfigs(pbxproj.readAsStringSync());
      expect(
        offenders,
        isEmpty,
        reason:
            'The Runner app target must set STRIP_STYLE = "non-global" on its '
            'Release and Profile build configurations. Without it, the '
            'archive post-processing strip removes the wellen_* dlsym export '
            'trie from the Runner executable and every waveform open fails on '
            'physical iOS devices in release builds (works in debug — the '
            'debug dylib is never stripped). See '
            'native/wellen_ffi/Sources/WellenFFIKeepalive/'
            'wellen_ffi_keepalive.c for the full story. Missing in: '
            '${offenders.join(', ')}',
      );
    },
  );
}

/// Returns the names of Runner-app Release/Profile build configurations that
/// are missing `STRIP_STYLE = "non-global"`.
///
/// The pbxproj is scanned per `XCBuildConfiguration` block. Runner app-target
/// configs are identified by `INFOPLIST_FILE = Runner/Info.plist;` (present
/// only on the app target — not RunnerTests, not the project-level configs).
List<String> missingStripStyleConfigs(String pbxproj) {
  final offenders = <String>[];
  final chunks = pbxproj.split('isa = XCBuildConfiguration;');
  // The text between two `isa = XCBuildConfiguration;` markers contains one
  // configuration's buildSettings and its `name = <config>;` line.
  for (final chunk in chunks.skip(1)) {
    if (!chunk.contains('INFOPLIST_FILE = Runner/Info.plist;')) continue;
    final nameMatch = RegExp(
      r'^\s*name = (\w+);',
      multiLine: true,
    ).firstMatch(chunk);
    final name = nameMatch?.group(1);
    if (name != 'Release' && name != 'Profile') continue;
    if (!chunk.contains('STRIP_STYLE = "non-global";')) {
      offenders.add(name!);
    }
  }
  // Both configs must exist AND carry the setting — if the block structure
  // changed so much that neither was found, flag that too.
  if (offenders.isEmpty && !pbxproj.contains('STRIP_STYLE = "non-global";')) {
    offenders.add('no Runner Release/Profile configs found');
  }
  return offenders;
}
