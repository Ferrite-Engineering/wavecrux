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
/// directory goes, and a refused delete is retried only where Windows needs it.
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
    const noDelay = <Duration>[Duration.zero, Duration.zero, Duration.zero];
    final dir = Directory('unused');

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

    test('on Windows a refused delete is retried until it succeeds', () async {
      var calls = 0;

      await deleteCxpTempDirectory(
        dir,
        isWindows: true,
        delays: noDelay,
        delete: (_) {
          calls++;
          if (calls < 3) throw const PathAccessException('unused', OSError());
        },
      );

      expect(calls, 3);
    });

    test('on Windows the original error surfaces once the retries are '
        'spent', () async {
      var calls = 0;

      await expectLater(
        deleteCxpTempDirectory(
          dir,
          isWindows: true,
          delays: noDelay,
          delete: (_) {
            calls++;
            throw const PathAccessException('unused', OSError());
          },
        ),
        throwsA(isA<PathAccessException>()),
      );

      expect(calls, noDelay.length + 1);
    });

    test('off Windows a refused delete fails at once', () async {
      var calls = 0;

      await expectLater(
        deleteCxpTempDirectory(
          dir,
          isWindows: false,
          delays: noDelay,
          delete: (_) {
            calls++;
            throw const PathAccessException('unused', OSError());
          },
        ),
        throwsA(isA<PathAccessException>()),
      );

      expect(calls, 1);
    });

    test('an error that is not a file-system error is never retried', () async {
      var calls = 0;

      await expectLater(
        deleteCxpTempDirectory(
          dir,
          isWindows: true,
          delays: noDelay,
          delete: (_) {
            calls++;
            throw StateError('not a lock');
          },
        ),
        throwsStateError,
      );

      expect(calls, 1);
    });
  });
}
