// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';

void main() {
  group('diagnosticsEnabledProvider', () {
    test('returns true in every build', () {
      // The diagnostics surfaces (Tab Diagnostics drawer, App Diagnostics
      // dialog, Pane Render Stats popover) ship in debug, profile, and release
      // builds — there is no per-user gating anymore. The provider exists as
      // the single place that gates UI visibility so the rule lives in one
      // location. Renamed from `diagnosticsAvailableProvider`.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(diagnosticsEnabledProvider), isTrue);
    });
  });
}
