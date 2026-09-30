// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:wavecrux/core/eula/wavecrux_eula_storage.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_storage.dart';

/// Forgets this installation's EULA acceptance, so the agreement is presented
/// again on this launch.
const String kResetEulaFlag = '--reset-eula';

/// Forgets this installation's telemetry answer, so the one-time disclosure is
/// presented again on this launch. The installation id is kept.
const String kResetTelemetryConsentFlag = '--reset-telemetry-consent';

/// Honours the first-run testing flags in [args]: [kResetEulaFlag] and
/// [kResetTelemetryConsentFlag].
///
/// Both dialogs are deliberately once per installation, which makes them the
/// surfaces hardest to see twice; these flags put the installation back to
/// "never answered" for one of them. Each is independent and they combine.
///
/// Must run before the provider container is built: the EULA acceptance store
/// and the telemetry consent store start reading their persisted values the
/// moment anything first reads them, and a reset after that would not be seen
/// until the next launch.
///
/// The storages default to the ones that ship; tests pass their own.
Future<void> applyFirstRunResetFlags(
  List<String> args, {
  CruxEulaStorage eulaStorage = const WavecruxEulaStorage(),
  TelemetryStorage telemetryStorage = const WavecruxTelemetryStorage(),
}) async {
  if (args.contains(kResetEulaFlag)) {
    await resetCruxEulaAcceptance(eulaStorage);
  }
  if (args.contains(kResetTelemetryConsentFlag)) {
    await resetTelemetryConsent(telemetryStorage);
  }
}
