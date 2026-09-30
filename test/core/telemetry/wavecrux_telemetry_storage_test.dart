// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('reset clears the answer and keeps the installation id', () async {
    // The `--reset-telemetry-consent` path, through the adapter that actually
    // ships rather than through the package's in-memory stand-in. The bug this
    // guards is a `remove` that writes an empty string: the consent store
    // treats any stored value as an answer, so the disclosure would stay
    // suppressed and the reset would look like it had worked.
    const storage = WavecruxTelemetryStorage();
    await storage.write(kTelemetryConsentKey, 'enabled');
    await storage.write(kTelemetryInstallationIdKey, 'an-id');

    await resetTelemetryConsent(storage);

    expect(await storage.read(kTelemetryConsentKey), isNull);
    expect(await storage.read(kTelemetryInstallationIdKey), 'an-id');
  });

  test('reset is a no-op when nothing was ever answered', () async {
    const storage = WavecruxTelemetryStorage();

    await resetTelemetryConsent(storage);

    expect(await storage.read(kTelemetryConsentKey), isNull);
  });
}
