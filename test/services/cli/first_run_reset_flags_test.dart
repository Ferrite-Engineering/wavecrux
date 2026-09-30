// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/eula/wavecrux_eula_storage.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_storage.dart';
import 'package:wavecrux/services/cli/cli_args.dart';
import 'package:wavecrux/services/cli/first_run_reset_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Both first-run answers recorded, as on any machine that has launched a
  // build before. Through the adapters that ship, so a `remove` that wrote an
  // empty string instead would fail here: both stores read any stored value
  // as an answer.
  setUp(
    () => SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.$kCruxEulaAcceptedVersionKey': kCruxEulaVersion,
      'flutter.$kTelemetryConsentKey': 'enabled',
      'flutter.$kTelemetryInstallationIdKey': 'an-id',
    }),
  );

  const eula = WavecruxEulaStorage();
  const telemetry = WavecruxTelemetryStorage();

  test('--reset-eula forgets the acceptance and nothing else', () async {
    await applyFirstRunResetFlags(['--reset-eula']);

    expect(await eula.read(kCruxEulaAcceptedVersionKey), isNull);
    expect(await telemetry.read(kTelemetryConsentKey), 'enabled');
    expect(await telemetry.read(kTelemetryInstallationIdKey), 'an-id');
  });

  test('--reset-telemetry-consent leaves the EULA acceptance alone', () async {
    await applyFirstRunResetFlags(['--reset-telemetry-consent']);

    expect(await eula.read(kCruxEulaAcceptedVersionKey), kCruxEulaVersion);
    expect(await telemetry.read(kTelemetryConsentKey), isNull);
    expect(await telemetry.read(kTelemetryInstallationIdKey), 'an-id');
  });

  test('the two flags combine', () async {
    await applyFirstRunResetFlags([
      'dump.fst',
      '--reset-telemetry-consent',
      '--reset-eula',
    ]);

    expect(await eula.read(kCruxEulaAcceptedVersionKey), isNull);
    expect(await telemetry.read(kTelemetryConsentKey), isNull);
    expect(await telemetry.read(kTelemetryInstallationIdKey), 'an-id');
  });

  test('no flag touches nothing', () async {
    await applyFirstRunResetFlags(['dump.fst', '--reset']);

    expect(await eula.read(kCruxEulaAcceptedVersionKey), kCruxEulaVersion);
    expect(await telemetry.read(kTelemetryConsentKey), 'enabled');
  });

  test('the storages are injectable', () async {
    final storage = InMemoryCruxEulaStorage({
      kCruxEulaAcceptedVersionKey: kCruxEulaVersion,
    });

    await applyFirstRunResetFlags(['--reset-eula'], eulaStorage: storage);

    expect(await storage.read(kCruxEulaAcceptedVersionKey), isNull);
    // The shipped store was not the one reset.
    expect(await eula.read(kCruxEulaAcceptedVersionKey), kCruxEulaVersion);
  });

  test('the startup parser neither rejects nor misroutes the flag', () {
    final parsed = parseCliArgs(['--reset-eula', 'dump.fst']);

    expect(parsed.initialFiles, ['dump.fst']);
    expect(parsed.reset, isFalse);
  });

  test('--help lists both flags', () {
    expect(cliHelpText(), contains(kResetEulaFlag));
    expect(cliHelpText(), contains(kResetTelemetryConsentFlag));
  });
}
