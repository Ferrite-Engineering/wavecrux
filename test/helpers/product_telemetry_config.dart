// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_config.dart';

/// The telemetry binding the app's root scope makes that has no working
/// default: WaveCrux's own product configuration.
///
/// Telemetry follows the user's consent, so until the consent store settles a
/// recorded event is held for it, and holding one reads the product
/// configuration. A test container that records anything (opening a file,
/// adding a tab, adding a decoder) therefore needs the binding production
/// makes, or the record throws. With the in-memory consent store a test gets,
/// consent is never given, so the held events are dropped and nothing is
/// sent.
final Override productTelemetryConfig = cruxTelemetryConfigProvider
    .overrideWithValue(wavecruxTelemetryConfig);
