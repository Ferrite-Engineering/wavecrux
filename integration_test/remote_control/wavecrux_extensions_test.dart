// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wavecrux_extensions_test.dart
//
// WCP `wavecrux.setActiveTab` extension command test.
//
// The extension shipped 2026-05-21: it is registered in
// [WcpServer._supportedCommands] and dispatched in
// [RemoteControlNotifier._handleCommand] to `_handleSetActiveTab`. Per
// ARCHITECTURE.md §10, it carries an optional `pane_id` argument so external
// tools can switch focus to a specific pane in a split-pane workspace:
//
//   * `wavecrux.setActiveTab({tab_id: X, pane_id: L})` — activates tab X and
//     asserts it is hosted by pane L first; returns error code 6 if it is
//     not.
//   * `wavecrux.setActiveTab({tab_id: X})` — `pane_id` omitted; the command
//     activates X in whichever pane already hosts it, without a pane check.
//   * `wavecrux.setActiveTab({tab_id: X, pane_id: <mismatched>})` — asserts
//     the WCP server returns a structured `type: error` frame (not a crash).
//
// The first test below predates the extension and now exercises an
// unrelated unregistered-command name (kept as the WCP "unknown command"
// regression surface). The three that follow were empty, `skip: true`
// placeholders written before the extension landed; they now exercise the
// shipped behavior directly.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../helpers/app_driver.dart';
import '../helpers/wcp_frame_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'an unregistered WCP command — server replies with a structured '
    'Unknown-command error frame',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');
      final container = rootContainer(tester);

      final startError = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(startError, isNull);
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
        // The extension list announced in the greeting must include the
        // currently-supported wavecrux.* commands.
        expect(greeting['commands'], isA<List<dynamic>>());
        expect(greeting['commands'], contains('wavecrux.setActiveTab'));

        // Invoke an unregistered command. The server must respond with a
        // structured `type: error` frame (code 2 = unknown command), not
        // crash the connection.
        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 1,
                  'command': 'wavecrux.unregisteredProbeCommand',
                  'data': <String, Object?>{},
                }),
              ) +
              [0],
        );
        final response = await waitForFrame(
          received,
          (m) => m['id'] == 1,
          tester: tester,
        );
        expect(
          response['type'],
          equals('error'),
          reason:
              'an unregistered command must return type=error '
              'not type=response',
        );
        expect(
          response['code'],
          equals(2),
          reason: 'Unknown command must return code 2',
        );
        expect(
          (response['message'] as String?)?.toLowerCase(),
          contains('unknown command'),
        );
      } finally {
        socket?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }
    },
  );

  testWidgets(
    'wavecrux.setActiveTab({tab_id, pane_id}) focuses the tab in the named '
    'pane',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');
      final container = rootContainer(tester);
      final wsNotifier = container.wavecruxWorkspace;

      final tabA = wsNotifier.current.tabs.single;
      final paneL = wsNotifier.current.activePaneId;

      // Split off an empty pane R and make it active — the pre-migration
      // "always empty new pane" semantic `splitPane` documents — so the
      // command below has to actually move focus back to L, not just find
      // it already there.
      final paneR = await wsNotifier.splitPane();
      await tester.pump();
      expect(wsNotifier.current.activePaneId, equals(paneR));

      final startError = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(startError, isNull);
      final port = container.read(remoteControlProvider).port;
      expect(port, isPositive);

      Socket? socket;
      try {
        socket = await Socket.connect('127.0.0.1', port);
        final received = <Map<String, dynamic>>[];
        attachFrameReader(socket, received);
        await waitForFrame(
          received,
          (m) => m['type'] == 'greeting',
          tester: tester,
        );

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 2,
                  'command': 'wavecrux.setActiveTab',
                  'data': {'tab_id': tabA.id.value, 'pane_id': paneL.value},
                }),
              ) +
              [0],
        );
        final response = await waitForFrame(
          received,
          (m) => m['id'] == 2,
          tester: tester,
        );
        expect(response['type'], equals('response'));
        final responseData = response['data'] as Map<String, dynamic>;
        expect(responseData['tab_id'], equals(tabA.id.value));
        expect(responseData['pane_id'], equals(paneL.value));

        await tester.pump();
        final ws = wsNotifier.current;
        expect(ws.activePaneId, equals(paneL));
        expect(
          ws.panes.firstWhere((p) => p.id == paneL).activeTabId,
          equals(tabA.id),
        );
      } finally {
        socket?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }
    },
  );

  testWidgets(
    'wavecrux.setActiveTab({tab_id}) without pane_id activates the tab '
    'without a pane check',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');
      final container = rootContainer(tester);
      final wsNotifier = container.wavecruxWorkspace;

      final tabA = wsNotifier.current.tabs.single;
      final paneL = wsNotifier.current.activePaneId;
      final tabBId = await wsNotifier.newTab(
        displayName: 'Tab B',
        paneId: paneL,
      );
      await tester.pump();
      // newTab activates what it opens — tab B, still in pane L.
      expect(
        wsNotifier.current.panes.firstWhere((p) => p.id == paneL).activeTabId,
        equals(tabBId),
      );

      final startError = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(startError, isNull);
      final port = container.read(remoteControlProvider).port;
      expect(port, isPositive);

      Socket? socket;
      try {
        socket = await Socket.connect('127.0.0.1', port);
        final received = <Map<String, dynamic>>[];
        attachFrameReader(socket, received);
        await waitForFrame(
          received,
          (m) => m['type'] == 'greeting',
          tester: tester,
        );

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 3,
                  'command': 'wavecrux.setActiveTab',
                  'data': {'tab_id': tabA.id.value},
                }),
              ) +
              [0],
        );
        final response = await waitForFrame(
          received,
          (m) => m['id'] == 3,
          tester: tester,
        );
        expect(
          response['type'],
          equals('response'),
          reason: 'omitting pane_id must not error when the tab exists',
        );

        await tester.pump();
        expect(
          wsNotifier.current.panes.firstWhere((p) => p.id == paneL).activeTabId,
          equals(tabA.id),
        );
      } finally {
        socket?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }
    },
  );

  testWidgets(
    'wavecrux.setActiveTab with a pane_id that does not host the tab '
    'returns a structured error response (no crash)',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');
      final container = rootContainer(tester);
      final wsNotifier = container.wavecruxWorkspace;
      final tabA = wsNotifier.current.tabs.single;

      final startError = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(startError, isNull);
      final port = container.read(remoteControlProvider).port;
      expect(port, isPositive);

      Socket? socket;
      try {
        socket = await Socket.connect('127.0.0.1', port);
        final received = <Map<String, dynamic>>[];
        attachFrameReader(socket, received);
        await waitForFrame(
          received,
          (m) => m['type'] == 'greeting',
          tester: tester,
        );

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 4,
                  'command': 'wavecrux.setActiveTab',
                  'data': {
                    'tab_id': tabA.id.value,
                    'pane_id': 'pane-that-does-not-host-tab-a',
                  },
                }),
              ) +
              [0],
        );
        final response = await waitForFrame(
          received,
          (m) => m['id'] == 4,
          tester: tester,
        );
        expect(
          response['type'],
          equals('error'),
          reason: 'a pane_id/tab_id mismatch must return type=error',
        );
        expect(
          response['code'],
          equals(6),
          reason: 'a tab/pane mismatch must return code 6',
        );

        // No crash: the connection is still alive and answers a follow-up
        // command normally.
        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 5,
                  'command': 'wavecrux.setActiveTab',
                  'data': {'tab_id': tabA.id.value},
                }),
              ) +
              [0],
        );
        final followUp = await waitForFrame(
          received,
          (m) => m['id'] == 5,
          tester: tester,
        );
        expect(followUp['type'], equals('response'));
      } finally {
        socket?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }
    },
  );
}
