// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_reload_event_test.dart
//
// WCP waveforms_loaded event integration test.
//
// Loads scalar_basics.vcd, starts the WCP server, connects a test client
// before triggering a reload, sends the reload command, and asserts that
// the client receives a waveforms_loaded event from the server.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

  testWidgets(
    'WCP reload command broadcasts waveforms_loaded event to connected client',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      final container = rootContainer(tester);

      final startError = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(startError, isNull, reason: 'WCP server failed to start');

      final port = container.read(remoteControlProvider).port;
      expect(port, isPositive);

      Socket? socket;
      try {
        socket = await Socket.connect('127.0.0.1', port);
        final received = <Map<String, dynamic>>[];
        attachFrameReader(socket, received);

        final greeting = await waitForFrame(
          received,
          (m) => m['type'] == 'greeting',
          tester: tester,
          timeout: const Duration(seconds: 5),
        );
        expect(greeting['type'], equals('greeting'));

        // Preamble: load the file into the root-scope source
        // first so `wcp.reload` has a `currentFilePath` to reload. CLI-
        // loaded files only populate the per-tab notifier; the WCP →
        // per-tab routing refactor will eventually make this preamble
        // unnecessary.
        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 100,
                  'command': 'load',
                  'data': {'source': _fixturePath('vcd/scalar_basics.vcd')},
                }),
              ) +
              [0],
        );
        final loadResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 100,
          tester: tester,
        );
        expect(loadResp['error'], isNull);

        final cmd = jsonEncode({
          'type': 'command',
          'id': 1,
          'command': 'reload',
          'data': <String, dynamic>{},
        });
        socket.add(utf8.encode(cmd) + [0]);

        // The server broadcasts a waveforms_loaded event before the
        // command response. Wait for the event explicitly.
        final event = await waitForFrame(
          received,
          (m) => m['type'] == 'event' && m['event'] == 'waveforms_loaded',
          tester: tester,
        );
        expect(event['event'], equals('waveforms_loaded'));

        // The command response also arrives.
        final response = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 1,
          tester: tester,
        );
        expect(response['error'], isNull);
      } finally {
        socket?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }
    },
  );
}
