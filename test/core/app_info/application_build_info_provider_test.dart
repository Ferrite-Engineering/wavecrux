// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wavecrux/core/app_info/application_build_info.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/app_info/build_info_fallback.dart';

void main() {
  group('applicationBuildInfoProvider', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'WaveCrux',
        packageName: 'com.ferriteengineering.wavecrux',
        version: '1.2.3',
        buildNumber: '42',
        buildSignature: '',
      );
    });

    test(
      'returns ApplicationBuildInfo with version from PackageInfo',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final info = await container.read(applicationBuildInfoProvider.future);

        expect(info.version, equals('1.2.3'));
        expect(info.buildNumber, equals('42'));
      },
    );

    test('returns non-empty gitSha (fallback "dev" locally)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final info = await container.read(applicationBuildInfoProvider.future);

      expect(info.gitSha, isNotEmpty);
    });

    test(
      'falls back to kBuildVersion when PackageInfo version is empty',
      () async {
        PackageInfo.setMockInitialValues(
          appName: 'WaveCrux',
          packageName: 'com.ferriteengineering.wavecrux',
          version: '',
          buildNumber: '',
          buildSignature: '',
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final info = await container.read(applicationBuildInfoProvider.future);

        expect(info.version, equals(kBuildVersion));
        expect(info.buildNumber, equals(kBuildNumber));
      },
    );

    test('architecture field is non-empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final info = await container.read(applicationBuildInfoProvider.future);

      expect(info.architecture, isNotEmpty);
    });

    test('flutterVersion field is non-empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final info = await container.read(applicationBuildInfoProvider.future);

      expect(info.flutterVersion, isNotEmpty);
    });

    test('dartVersion field is non-empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final info = await container.read(applicationBuildInfoProvider.future);

      expect(info.dartVersion, isNotEmpty);
    });

    test('overrideWith replaces the provider (Pro overlay pattern)', () async {
      const stub = ApplicationBuildInfo(
        version: '9.9.9',
        buildNumber: '999',
        gitSha: 'prosha',
        os: 'Windows 11',
        architecture: 'x86_64',
        flutterVersion: '4.0.0',
        dartVersion: '4.0.0',
      );
      final container = ProviderContainer(
        overrides: [
          applicationBuildInfoProvider.overrideWith((_) async => stub),
        ],
      );
      addTearDown(container.dispose);

      final info = await container.read(applicationBuildInfoProvider.future);

      expect(info, equals(stub));
      expect(info.version, equals('9.9.9'));
    });
  });
}
