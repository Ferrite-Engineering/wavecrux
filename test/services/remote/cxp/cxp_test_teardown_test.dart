// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';

import '../../../helpers/cxp_test_teardown.dart';
import '../../../helpers/product_telemetry_config.dart';

/// The teardown the CXP tests share: the node is fully stopped before its
/// directory goes, and the directory is then deleted once.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'WaveCrux',
      packageName: 'com.ferriteengineering.wavecrux',
      version: '0.0.0-test',
      buildNumber: '0',
      buildSignature: '',
    );
  });

  group('disposeCxpContainer', () {
    late Directory dir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('wavecrux_cxp_td_');
    });

    tearDown(() async {
      await deleteCxpTempDirectory(dir);
    });

    ProviderContainer containerOver(Directory manifestDir) => ProviderContainer(
      overrides: [
        productTelemetryConfig,
        cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding),
        cruxCxpManifestDirectoryProvider.overrideWith(
          (_) async => manifestDir.path,
        ),
        cruxCxpTransportAvailableProvider.overrideWithValue(true),
        cruxCxpLaunchSettingsProvider.overrideWithValue(
          const CruxCxpSettings(enabled: true, port: 0),
        ),
      ],
    );

    test('returns only after the runtime has stopped and removed its '
        'manifest', () async {
      final container = containerOver(dir);
      final runtime = await container.read(cruxCxpRuntimeProvider.future);
      expect(runtime, isNotNull);
      expect(runtime!.isAvailable, isTrue, reason: runtime.unavailableReason);
      expect(
        dir.listSync().whereType<File>(),
        isNotEmpty,
        reason: 'the running runtime advertises itself with a manifest',
      );

      await disposeCxpContainer(container);

      // Plain `container.dispose()` leaves the manifest behind at this point:
      // the runtime provider stops its runtime without waiting.
      expect(dir.listSync(), isEmpty);
      expect(runtime.isAvailable, isFalse);
    });

    test('does not start a runtime that was never read', () async {
      final container = containerOver(dir);

      await disposeCxpContainer(container);

      expect(dir.listSync(), isEmpty);
    });
  });

  group('deleteCxpTempDirectory', () {
    test('deletes a real directory tree', () async {
      final real = await Directory.systemTemp.createTemp('wavecrux_cxp_del_');
      File(
        '${real.path}${Platform.pathSeparator}a.json',
      ).writeAsStringSync('{}');

      await deleteCxpTempDirectory(real);

      expect(real.existsSync(), isFalse);
    });

    test('a directory that is already gone is not an error', () async {
      final real = await Directory.systemTemp.createTemp('wavecrux_cxp_del_');
      real.deleteSync();

      await deleteCxpTempDirectory(real);
    });
  });
}
