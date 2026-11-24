// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/app_info/build_info_fallback.dart';

void main() {
  group('resolveBuildFact', () {
    test('keeps a value a release build passed', () {
      expect(resolveBuildFact('abc1234'), 'abc1234');
      expect(resolveBuildFact('  arm64 '), 'arm64');
    });

    test('reads dev when nothing was passed', () {
      expect(resolveBuildFact(''), 'dev');
      expect(resolveBuildFact('   '), 'dev');
    });
  });

  group('resolveCopyrightYear', () {
    test('uses the build year a release build passed', () {
      expect(resolveCopyrightYear('2026'), '2026');
      expect(resolveCopyrightYear(' 2027 ', now: DateTime(2030)), '2027');
    });

    test('falls back to the current year, never a literal', () {
      expect(resolveCopyrightYear('', now: DateTime(2031)), '2031');
      expect(resolveCopyrightYear('twenty', now: DateTime(2031)), '2031');
      expect(resolveCopyrightYear('26', now: DateTime(2031)), '2031');
    });
  });

  group('applicationBuildInfoProvider in a local build (no dart-defines)', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'WaveCrux',
        packageName: 'com.ferriteengineering.wavecrux',
        version: '1.2.0',
        buildNumber: '7',
        buildSignature: '',
      );
    });

    test('reads dev for commit, architecture and Flutter version', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final info = await container.read(applicationBuildInfoProvider.future);

      expect(info.gitSha, 'dev');
      expect(info.architecture, 'dev');
      expect(info.flutterVersion, 'dev');
    });
  });
}
