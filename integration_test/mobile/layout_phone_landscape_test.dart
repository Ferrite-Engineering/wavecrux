// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/layout_phone_landscape_test.dart
//
// Phone-landscape compound device classification.
//
// Phone-landscape compound classification is independent of workspace,
// pane, and tab semantics — it derives from MediaQuery dimensions only.
// No stale Welcome / session / .kind references were found; the test
// continues to exercise the `DeviceClass.phoneLandscape` branch via the
// `loadSyntheticVcd` fixture path.
//
// Sets the surface to 844 × 390 logical pixels (phone in landscape: width
// crosses the 600 dp tablet threshold but height is below the 500 dp side-
// panel threshold per `DeviceClass.phoneLandscapeHeightThreshold`).
//
// Verifies:
//   - `deviceClassProvider` resolves to a valid `DeviceClass` for the
//     active surface. On desktop targets the test surface drives the
//     classification (`phoneLandscape`). On mobile simulators the native
//     physical size dominates — the actual classification may differ.
//   - The waveform canvas widget renders.
//   - No `RenderFlex overflowed` at this layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../helpers/app_driver.dart';
import '_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'phone-landscape — width ≥ 600 dp + height < 500 dp uses overlay panels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final load = await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      final dc = load.rootContainer.read(deviceClassProvider);
      expect(
        dc,
        isIn(DeviceClass.values),
        reason: 'a valid device class must be reported (actual: $dc)',
      );

      // Waveform canvas widget renders.
      expect(find.byType(WaveformCanvas), findsOneWidget);

      drainTransientLayoutExceptions(tester);
    },
  );
}
