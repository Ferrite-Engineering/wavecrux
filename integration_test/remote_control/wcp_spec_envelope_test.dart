// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_spec_envelope_test.dart
//
// End-to-end coverage of the upstream WCP spec envelope over a real TCP
// socket: id-less commands with top-level parameters, command-echo
// responses, in-order pipelined replies, spec-shaped errors, marker
// placement/removal, and add_items atomicity on partial failure.
//
// The legacy id-framed dialect is covered by the sibling wcp_*_test.dart
// files; this file drives the same server exclusively through the spec
// envelope a third-party WCP client (e.g. a Surfer script) would use.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../helpers/app_driver.dart';
import '../helpers/wcp_frame_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'WCP spec-envelope session: greeting, add_items, pipelining, markers, '
    'partial-failure atomicity',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      final container = rootContainer(tester);
      final activeTab = activeTabContainer(tester);

      // markerStateProvider is autoDispose; hold a listener open so state
      // survives between the WCP call and the assertion.
      final markerSub = activeTab.listen(markerStateProvider, (_, _) {});
      final cursorSub = activeTab.listen(cursorStateProvider, (_, _) {});
      addTearDown(markerSub.close);
      addTearDown(cursorSub.close);

      final error = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(error, isNull, reason: 'WCP server failed to start: $error');
      final port = container.read(remoteControlProvider).port;

      Socket? socket;
      try {
        socket = await Socket.connect('127.0.0.1', port);
        final received = <Map<String, dynamic>>[];
        attachFrameReader(socket, received);

        void send(Map<String, dynamic> msg) {
          socket!.add(utf8.encode(jsonEncode(msg)) + [0]);
        }

        // ── greeting handshake ─────────────────────────────────────────────
        final greeting = await waitForFrame(
          received,
          (m) => m['type'] == 'greeting',
          tester: tester,
          timeout: const Duration(seconds: 5),
        );
        expect(greeting['version'], equals('0'));
        expect(
          (greeting['commands'] as List).cast<String>(),
          containsAll(['add_items', 'add_variables', 'add_scope']),
        );

        // Client greeting with a supported version draws no error frame.
        send({'type': 'greeting', 'version': '0', 'commands': <String>[]});

        // ── pipelined spec commands, in-order replies ──────────────────────
        // add_items (payload-bearing echo) followed immediately by
        // set_cursor (ack). The replies must arrive in request order.
        send({
          'type': 'command',
          'command': 'add_items',
          'items': ['top.clk'],
        });
        send({'type': 'command', 'command': 'set_cursor', 'timestamp': 30});

        await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['command'] == 'ack',
          tester: tester,
        );
        final responses = received
            .where((m) => m['type'] == 'response')
            .toList();
        expect(
          responses.map((m) => m['command']).toList(),
          equals(['add_items', 'ack']),
          reason: 'spec replies must be correlated by request order',
        );
        final addResp = responses.first;
        expect(addResp.containsKey('id'), isFalse);
        final ids = (addResp['ids'] as List).cast<int>();
        expect(ids, hasLength(1));

        expect(activeTab.read(signalGroupsProvider).signalCount, equals(1));
        expect(
          activeTab.read(cursorStateProvider).primaryCursorTime,
          equals(30),
        );

        // ── get_item_list responds with ids ────────────────────────────────
        send({'type': 'command', 'command': 'get_item_list'});
        final listResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['command'] == 'get_item_list',
          tester: tester,
        );
        expect((listResp['ids'] as List).cast<int>(), equals(ids));

        // ── markers: add via spec shape, remove via remove_items ───────────
        send({
          'type': 'command',
          'command': 'add_markers',
          'markers': [
            {'name': 'a', 'time': 42, 'move_focus': false},
          ],
        });
        final markerResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['command'] == 'add_markers',
          tester: tester,
        );
        final markerId = (markerResp['ids'] as List).cast<int>().single;
        expect(activeTab.read(markerStateProvider).getMarker('a'), equals(42));

        send({
          'type': 'command',
          'command': 'remove_items',
          'ids': [markerId],
        });
        await waitForFrame(
          received,
          (m) =>
              m['type'] == 'response' &&
              m['command'] == 'ack' &&
              received.indexOf(m) > received.indexOf(markerResp),
          tester: tester,
        );
        expect(
          activeTab.read(markerStateProvider).getMarker('a'),
          isNull,
          reason: 'remove_items on a marker id must clear the marker',
        );

        // ── partial-failure add is atomic ──────────────────────────────────
        send({
          'type': 'command',
          'command': 'add_items',
          'items': ['top.rst', 'top.does_not_exist'],
        });
        final errResp = await waitForFrame(
          received,
          (m) => m['type'] == 'error' && m['error'] == 'add_items',
          tester: tester,
        );
        expect(errResp['message'], contains('top.does_not_exist'));
        expect(errResp.containsKey('code'), isFalse);
        expect(
          activeTab.read(signalGroupsProvider).signalCount,
          equals(1),
          reason:
              'a partially resolvable add_items must display nothing — only '
              'the earlier successful add remains',
        );

        // The failed batch must not have registered anything either.
        send({'type': 'command', 'command': 'get_item_list'});
        final finalList = await waitForFrame(
          received,
          (m) =>
              m['type'] == 'response' &&
              m['command'] == 'get_item_list' &&
              received.indexOf(m) > received.indexOf(errResp),
          tester: tester,
        );
        expect((finalList['ids'] as List).cast<int>(), equals(ids));
      } finally {
        socket?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }

      expect(tester.takeException(), isNull);
    },
  );
}
