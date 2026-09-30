// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_get_value_test.dart
//
// WCP wavecrux.getValueAt integration test.
//
// Loads scalar_basics.vcd, starts the WCP server, connects a test client,
// sends wavecrux.getValueAt for top.clk at t=50, and asserts the returned
// value matches the known ground truth from scalar_basics.expected.json
// (top.clk = "1" at t=50).

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

  // The WCP `wavecrux.getValueAt` handler resolves the hierarchical
  // `signal_path` ("top.clk") to a wellen signal-ref handle via
  // `source.findVariables` before calling `loadSignal` / `valueAt` (those
  // APIs key off `Variable.signalRef`, not the path string). See
  // `_handleGetValueAt` in remote_control_notifier.dart.
  testWidgets('WCP wavecrux.getValueAt returns correct signal value', (
    tester,
  ) async {
    await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

    final container = rootContainer(tester);

    final error = await container
        .read(remoteControlProvider.notifier)
        .startServer(0);
    expect(error, isNull, reason: 'WCP server failed to start: $error');

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
      );
      expect(greeting['type'], equals('greeting'));

      // Preamble: explicit wcp.load so the root-scope
      // WaveformSourceNotifier (which the wavecrux.getValueAt handler
      // reads from) has the file populated. CLI-loaded files only
      // populate the per-tab notifier; the WCP → per-tab routing
      // refactor will eventually make this unnecessary.
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

      // Query the value of top.clk at t=50.
      // From scalar_basics.vcd: at t=50 the clock transitioned to 1.
      const signalPath = 'top.clk';
      const queryTime = 50;
      final cmd = jsonEncode({
        'type': 'command',
        'id': 1,
        'command': 'wavecrux.getValueAt',
        'data': {'signal_path': signalPath, 'time': queryTime},
      });
      socket.add(utf8.encode(cmd) + [0]);

      final response = await waitForFrame(
        received,
        (m) => m['type'] == 'response' && m['id'] == 1,
        tester: tester,
      );

      final data = response['data'] as Map<String, dynamic>;
      expect(data['signal_path'], equals(signalPath));
      expect(data['time'], equals(queryTime));
      // top.clk is 1 at t=50 per the VCD (transition at #50: 1!).
      expect(
        data['value'],
        equals('1'),
        reason: 'top.clk should be 1 at t=50 per scalar_basics.vcd',
      );
    } finally {
      socket?.destroy();
      await container.read(remoteControlProvider.notifier).stopServer();
    }
  });
}
