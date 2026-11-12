// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: an integration test that forces a touch
/// `defaultTargetPlatform` on a desktop runner must also stand in for the
/// fold source.
///
/// Background (audit S08): `PlatformFoldSource.watch()` opens the iOS-only
/// `com.wavecrux/fold` event channel whenever `defaultTargetPlatform` is iOS.
/// The weekly integration run is a desktop embedder, which answers that channel
/// with `MissingPluginException`; the exception reaches the framework and
/// `os_memory_pressure_test.dart` failed on Linux, macOS and Windows. The
/// override only changes the *reported* platform, so the real channel must not
/// be reached: such a test passes `foldSourceProvider.overrideWithValue(...)`
/// with a fake [FoldSource] to the bootstrap.
///
/// The integration suite needs a device and cannot run in the unit suite, so
/// this reads the files. Comment lines are exempt.
void main() {
  test('a forced-iOS integration test overrides foldSourceProvider', () {
    final dir = Directory('integration_test');
    expect(dir.existsSync(), isTrue, reason: 'expected integration_test/');

    final forcesIos = RegExp(
      r'debugDefaultTargetPlatformOverride\s*=\s*TargetPlatform\.iOS',
    );
    final offenders = <String>[];
    var checked = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (!forcesIos.hasMatch(code)) continue;
      checked++;
      if (!code.contains('foldSourceProvider.overrideWithValue(')) {
        offenders.add(entity.path);
      }
    }

    expect(
      checked,
      greaterThan(0),
      reason:
          'the guard found no forced-iOS integration test, so it checks '
          'nothing; update it if os_memory_pressure_test.dart moved',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'these integration tests force TargetPlatform.iOS on a desktop '
          'runner without a fake foldSourceProvider, so the real source '
          'opens the iOS-only fold channel and fails with '
          'MissingPluginException:\n${offenders.join('\n')}',
    );
  });
}
