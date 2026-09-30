// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WaveCrux's persistence adapter for the accepted-EULA version.
///
/// Lives in `SharedPreferences` under the suite-fixed key
/// [kCruxEulaAcceptedVersionKey], **outside** `AppSettings`, for the same
/// reason the telemetry consent decision does: `AppSettings` is the user's
/// preference document, the thing they copy to a second machine or hand to a
/// colleague, and an acceptance must not travel that way. A settings file
/// carried to a new machine must not carry an agreement the person at that
/// machine never accepted.
///
/// Reads and writes **fail soft, towards asking again**. That is the opposite
/// direction from [WavecruxTelemetryStorage], and deliberately so: an
/// unreadable telemetry store collects nothing, which is the safe answer there,
/// whereas an unreadable acceptance store must not be mistaken for an
/// acceptance. EULA section 2.1 does not let the application proceed without
/// one, so a broken store shows the agreement rather than skipping it.
class WavecruxEulaStorage extends CruxEulaStorage {
  /// Creates the adapter. Stateless — `SharedPreferences.getInstance()` is
  /// itself cached by the plugin.
  const WavecruxEulaStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } on Object catch (_) {
      // Reads as "never accepted", which presents the agreement.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } on Object catch (_) {
      // The acceptance is lost and the user is asked again next launch. That
      // is an annoyance; the alternative — treating a failed write as done —
      // would be a build running with no recorded acceptance at all.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } on Object catch (_) {
      // Same posture as write. `--reset-eula` not taking effect is a testing
      // inconvenience, never a user-facing failure.
    }
  }
}
