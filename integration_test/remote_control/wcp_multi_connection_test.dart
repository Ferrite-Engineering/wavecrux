// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_multi_connection_test.dart
//
// WCP multi-connection integration test.
//
// `WcpServer` is a generic socket server (`lib/services/remote/wcp_server.dart`
// — "Multiple concurrent clients are supported") and every other WCP
// integration test in this directory (wcp_add_signal_test.dart,
// wcp_set_cursor_test.dart, wcp_set_viewport_range_test.dart, …) opens
// exactly one client socket. This test opens TWO simultaneous real TCP
// sockets against one running app instance and asserts:
//
//   1. `remoteControlProvider.connectedClients` tracks both connections.
//   2. Each connection's command responses are routed back to that SAME
//      connection only — client A's `add_items` response never leaks onto
//      client B's frame stream, and vice versa.
//   3. A server-broadcast event (`waveforms_loaded`, triggered by `reload`
//      on client A) fans out to BOTH connected clients, not just the one
//      that issued the command.
//   4. Both connections' commands land in the shared provider state (both
//      target the same active-tab container — issue #44 routing), so the
//      end state reflects both clients' work.
//   5. `connectedClients` drops back down as each socket disconnects.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
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
    'two simultaneous WCP client sockets each dispatch independently and '
    'both receive broadcast events',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      final container = rootContainer(tester);
      final activeTab = activeTabContainer(tester);

      // cursorStateProvider is autoDispose; hold it open across the WCP
      // call and the assertion (same rationale as wcp_set_cursor_test.dart).
      final cursorSub = activeTab.listen(cursorStateProvider, (_, _) {});
      addTearDown(cursorSub.close);

      final startError = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(
        startError,
        isNull,
        reason: 'WCP server failed to start: $startError',
      );

      final port = container.read(remoteControlProvider).port;
      expect(port, isPositive);

      Socket? socketA;
      Socket? socketB;
      try {
        // ── connect both clients ──────────────────────────────────────────
        socketA = await Socket.connect('127.0.0.1', port);
        final receivedA = <Map<String, dynamic>>[];
        attachFrameReader(socketA, receivedA);

        socketB = await Socket.connect('127.0.0.1', port);
        final receivedB = <Map<String, dynamic>>[];
        attachFrameReader(socketB, receivedB);

        final greetingA = await waitForFrame(
          receivedA,
          (m) => m['type'] == 'greeting',
          tester: tester,
          timeout: const Duration(seconds: 5),
        );
        expect(greetingA['type'], equals('greeting'));

        final greetingB = await waitForFrame(
          receivedB,
          (m) => m['type'] == 'greeting',
          tester: tester,
          timeout: const Duration(seconds: 5),
        );
        expect(greetingB['type'], equals('greeting'));

        final bothConnected = await pumpUntil(
          tester,
          () => container.read(remoteControlProvider).connectedClients == 2,
        );
        expect(
          bothConnected,
          isTrue,
          reason: 'server must track both simultaneous connections',
        );

        void send(
          Socket socket,
          int id,
          String command,
          Map<String, dynamic> data,
        ) {
          socket.add(
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
        }

        // Client A re-asserts the active tab's source (issue #44 preamble,
        // same as wcp_add_signal_test.dart / wcp_reload_event_test.dart) so
        // both add_items and the later reload have a source to act on.
        send(socketA, 100, 'load', {
          'source': _fixturePath('vcd/scalar_basics.vcd'),
        });
        final loadResp = await waitForFrame(
          receivedA,
          (m) => m['type'] == 'response' && m['id'] == 100,
          tester: tester,
        );
        expect(loadResp['error'], isNull);

        // ── client A: add_items ──────────────────────────────────────────
        send(socketA, 1, 'add_items', const {'item_path': 'top.clk'});
        final responseA = await waitForFrame(
          receivedA,
          (m) => m['type'] == 'response' && m['id'] == 1,
          tester: tester,
        );
        expect(responseA['type'], equals('response'));

        // ── client B: set_cursor ─────────────────────────────────────────
        const targetTick = 50;
        send(socketB, 2, 'set_cursor', const {'timestamp': targetTick});
        final responseB = await waitForFrame(
          receivedB,
          (m) => m['type'] == 'response' && m['id'] == 2,
          tester: tester,
        );
        expect(responseB['type'], equals('response'));

        // ── per-connection routing: no cross-talk ────────────────────────
        // Give the event loop a beat to deliver any (incorrect) cross-wired
        // frame before asserting its absence.
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          receivedB.any((m) => m['type'] == 'response' && m['id'] == 1),
          isFalse,
          reason:
              "client A's add_items response (id 1) must not be "
              'delivered to client B',
        );
        expect(
          receivedA.any((m) => m['type'] == 'response' && m['id'] == 2),
          isFalse,
          reason:
              "client B's set_cursor response (id 2) must not be "
              'delivered to client A',
        );

        // ── both commands landed in shared provider state ────────────────
        expect(
          activeTab.read(signalGroupsProvider).signalCount,
          greaterThan(0),
          reason: "client A's add_items must have added a signal",
        );
        expect(
          activeTab.read(cursorStateProvider).primaryCursorTime,
          equals(targetTick),
          reason: "client B's set_cursor must have moved the cursor",
        );

        // ── broadcast fan-out: reload from A reaches BOTH clients ────────
        send(socketA, 3, 'reload', const {});
        final eventOnA = await waitForFrame(
          receivedA,
          (m) => m['type'] == 'event' && m['event'] == 'waveforms_loaded',
          tester: tester,
        );
        expect(eventOnA['event'], equals('waveforms_loaded'));

        final eventOnB = await waitForFrame(
          receivedB,
          (m) => m['type'] == 'event' && m['event'] == 'waveforms_loaded',
          tester: tester,
        );
        expect(
          eventOnB['event'],
          equals('waveforms_loaded'),
          reason:
              'a broadcast event triggered by client A must also reach '
              'client B, which never issued the reload itself',
        );

        final reloadResponse = await waitForFrame(
          receivedA,
          (m) => m['type'] == 'response' && m['id'] == 3,
          tester: tester,
        );
        expect(reloadResponse['error'], isNull);

        // ── teardown: connectedClients drops as each socket disconnects ──
        socketA.destroy();
        socketA = null;
        final oneLeft = await pumpUntil(
          tester,
          () => container.read(remoteControlProvider).connectedClients == 1,
        );
        expect(
          oneLeft,
          isTrue,
          reason: 'disconnecting client A must drop connectedClients to 1',
        );

        socketB.destroy();
        socketB = null;
        final noneLeft = await pumpUntil(
          tester,
          () => container.read(remoteControlProvider).connectedClients == 0,
        );
        expect(
          noneLeft,
          isTrue,
          reason: 'disconnecting client B must drop connectedClients to 0',
        );
      } finally {
        socketA?.destroy();
        socketB?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }

      expect(tester.takeException(), isNull);
    },
  );
}
