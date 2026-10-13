// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_load_no_tab_test.dart
//
// WCP `load` into an app with no tab open, then viewport commands (#17).
//
// The bug: with no tab open, `load` put the waveform under a synthetic tab id
// that no pane displayed, so no canvas ever laid the trace out and
// `set_viewport_to` was acknowledged without effect. The headless unit tests
// pin the handler half (load opens and activates a tab; viewport commands
// error when no canvas has laid out). This test closes the loop on a real
// boot: the tab the load opens must be the one a pane shows, its canvas must
// lay out, and the viewport must actually move.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../helpers/app_driver.dart';
import '../helpers/wcp_frame_helpers.dart';

String _fixturePath(String relative) => [
  Directory.current.path,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('WCP load with no tab open shows the file and the viewport '
      'commands move it', (tester) async {
    await clearPersistedWorkspace();
    addTearDown(clearPersistedWorkspace);
    final file = _fixturePath('vcd/scalar_basics.vcd');
    expect(File(file).existsSync(), isTrue);

    // No file on the command line: the start screen, no tab.
    await seedFirstLaunchAnswers();
    await bootstrap();
    await tester.pump();
    final root = rootContainer(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(root.read(tabListProvider), isEmpty, reason: 'precondition');

    final startError = await root
        .read(remoteControlProvider.notifier)
        .startServer(0);
    expect(startError, isNull);
    final port = root.read(remoteControlProvider).port;

    Socket? socket;
    try {
      socket = await Socket.connect('127.0.0.1', port);
      final received = <Map<String, dynamic>>[];
      attachFrameReader(socket, received);
      await waitForFrame(
        received,
        (m) => m['type'] == 'greeting',
        tester: tester,
        timeout: const Duration(seconds: 5),
      );

      var nextId = 1;
      Future<Map<String, dynamic>> send(
        String command, [
        Map<String, dynamic> data = const {},
      ]) {
        final id = nextId++;
        socket!.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': id,
                  'command': command,
                  'data': data,
                }),
              ) +
              [0],
        );
        // A failed command answers with an `error` frame, not a `response`
        // carrying an error, so wait for either and let the caller check.
        return waitForFrame(
          received,
          (m) =>
              (m['type'] == 'response' || m['type'] == 'error') &&
              m['id'] == id,
          tester: tester,
        );
      }

      final load = await send('load', {'source': file});
      expect(load['type'], 'response', reason: 'load must succeed: $load');

      // The load opened a real tab, and it is the active one.
      await pumpUntil(tester, () => root.read(tabListProvider).isNotEmpty);
      final tabs = root.read(tabListProvider);
      expect(tabs, hasLength(1));
      expect(root.read(activeTabIdProvider), tabs.single.id);
      await pumpUntilWaveformReady(tester);

      // The pane showing the new tab must have mounted a canvas that laid the
      // trace out. This is the half of #17 the headless tests cannot see.
      final tab = activeTabContainer(tester);
      final laidOut = await pumpUntil(
        tester,
        () => tab.read(timeMapperProvider.notifier).isLaidOut,
      );
      expect(laidOut, isTrue, reason: 'no canvas laid out the loaded trace');

      // Narrow the view to [20, 40]: the canvas has laid the trace out, so
      // the command takes effect instead of erroring (code 5) or acking a
      // no-op.
      final range = await send('set_viewport_range', {
        'start': 20,
        'end': 40,
      });
      expect(range['type'], 'response', reason: '$range');
      await tester.pump();
      final afterRange = (await send('wavecrux.getState'))['data'] as Map;
      expect(afterRange['is_loaded'], isTrue);

      final viewportTo = await send('set_viewport_to', {'timestamp': 80});
      expect(viewportTo['type'], 'response', reason: '$viewportTo');
      await tester.pump();
      final afterTo = (await send('wavecrux.getState'))['data'] as Map;

      expect(
        afterTo['pan_offset_ticks'],
        isNot(afterRange['pan_offset_ticks']),
        reason: 'set_viewport_to must move the viewport, not just ack',
      );
      expect(
        afterTo['ticks_per_pixel'],
        afterRange['ticks_per_pixel'],
        reason: 'set_viewport_to pans; the zoom from set_viewport_range holds',
      );
    } finally {
      socket?.destroy();
      await root.read(remoteControlProvider.notifier).stopServer();
    }
    // Headless-bundle PNG codec errors are environmental; drain.
    tester.takeException();
  });
}
