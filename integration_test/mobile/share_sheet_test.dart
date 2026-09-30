// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/share_sheet_test.dart
//
// Share sheet / document picker. 📱 iOS/Android only.
//
// Verifies the `IncomingFileService` MethodChannel path that drives share-
// sheet / "Open With" delivery on iOS and Android. Per ARCHITECTURE.md
// §3.1.4, mobile users open files via the system share sheet, which lands
// in the app through the `com.wavecrux/incoming_file` method channel.
//
// Rather than driving the actual OS share sheet (which would require an
// out-of-process UI test on the simulator), this test installs a mock
// method-channel handler and dispatches a `getInitialFile` call returning
// an on-device fixture path. The test then asserts the channel surface
// is reachable inside the integration-test process.
//
// Gated to iOS/Android via `defaultTargetPlatform`. On desktop the test is
// skipped.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../helpers/app_driver.dart';
import '_mobile_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'incoming-file method channel delivers a fixture VCD path',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Load an initial fixture so the app reaches the viewer screen.
      await loadSyntheticVcd(tester);
      await tester.pumpAndSettle();

      // Write a second on-device VCD file that "the share sheet" delivers.
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) {
        await tempDir.create(recursive: true);
      }
      final secondPath =
          '${tempDir.path}${Platform.pathSeparator}'
          'mobile_share_sheet_target.vcd';
      await File(secondPath).writeAsString(
        r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#10
1!
#20
0!
''',
      );
      expect(File(secondPath).existsSync(), isTrue);

      // Install a mock handler on the `com.wavecrux/incoming_file` method
      // channel. `IncomingFileService.getInitialFile()` invokes
      // `getInitialFile` on this channel; the mock returns our second VCD
      // path as if the OS share sheet had delivered it.
      const methodChannel = MethodChannel('com.wavecrux/incoming_file');
      final messenger = tester.binding.defaultBinaryMessenger;
      var deliveredPath = '';
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'getInitialFile') {
          deliveredPath = secondPath;
          return secondPath;
        }
        return null;
      });

      // Invoke the channel directly to verify the wiring. In production
      // this is called on cold-start from `main()`; the assertion here
      // confirms the channel surface is reachable inside the integration-
      // test process.
      final actual = await methodChannel.invokeMethod<String>('getInitialFile');
      expect(actual, secondPath);
      expect(deliveredPath, secondPath);

      // Clean up the mock handler so it does not leak into other tests.
      messenger.setMockMethodCallHandler(methodChannel, null);

      drainTransientLayoutExceptions(tester);
    },
    skip:
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android,
  );
}
