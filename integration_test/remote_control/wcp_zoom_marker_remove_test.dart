// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_zoom_marker_remove_test.dart
//
// WCP `zoom_to_fit` / `add_markers` / `remove_items`
// integration test.
//
// The remote-control command surface has real-socket integration tests for
// `add_items` (wcp_add_signal_test.dart), `set_cursor` (wcp_set_cursor_test.dart),
// `set_viewport_range` (wcp_set_viewport_range_test.dart), `load`, and
// `wavecrux.getValueAt`, but `zoom_to_fit`, `add_markers`, and `remove_items`
// had no coverage. This file closes that gap with one command per section,
// following `wcp_set_cursor_test.dart`'s real-socket shape: start the WCP
// server, connect a real TCP client, send the command, and assert both the
// response frame AND the resulting provider state (not just "no error").
//
// Single-pane happy path only — the split-pane per-pane-routing variant is
// already documented as a pending refactor (wcp_load_test.dart)
// and is exercised for the other commands; repeating it here for all three
// commands would mostly duplicate that existing coverage without adding a
// new invariant.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../helpers/app_driver.dart';
import '../helpers/wcp_frame_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'WCP zoom_to_fit, add_markers, and remove_items each update their '
    'real provider state',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      final container = rootContainer(tester);
      // These commands route through the active tab's container (issue #44
      // — `RemoteControlNotifier._activeTab`), same as every other WCP
      // handler test in this directory.
      final activeTab = activeTabContainer(tester);

      // markerStateProvider and timeMapperProvider are autoDispose; hold a
      // listener open for the test's lifetime so state survives between the
      // WCP call and the assertion (same pattern as wcp_set_cursor_test.dart).
      final markerSub = activeTab.listen(markerStateProvider, (_, _) {});
      final mapperSub = activeTab.listen(timeMapperProvider, (_, _) {});
      addTearDown(markerSub.close);
      addTearDown(mapperSub.close);

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
          timeout: const Duration(seconds: 5),
        );
        expect(greeting['type'], equals('greeting'));

        void send(int id, String command, Map<String, dynamic> data) {
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
        }

        // ── zoom_to_fit ────────────────────────────────────────────────────
        //
        // The load above already leaves the mapper at fit-all, so first move
        // away from it (zoom in a few steps) to give zoom_to_fit something
        // real to undo.
        final fullMapper = activeTab.read(timeMapperProvider);
        activeTab.read(navigationProvider.notifier)
          ..zoomIn()
          ..zoomIn()
          ..zoomIn();
        final zoomedMapper = activeTab.read(timeMapperProvider);
        expect(
          zoomedMapper.visibleRange,
          lessThan(fullMapper.endTime - fullMapper.startTime),
          reason:
              'precondition: zoomIn must actually shrink the viewport '
              'below the full range, or zoom_to_fit below is a no-op test',
        );

        send(1, 'zoom_to_fit', const {});
        final zoomResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 1,
          tester: tester,
        );
        expect(zoomResp['error'], isNull);

        final fitMapper = activeTab.read(timeMapperProvider);
        expect(
          fitMapper.visibleStartTime,
          equals(fullMapper.startTime),
          reason: 'zoom_to_fit must restore the full simulation start time',
        );
        expect(
          fitMapper.visibleEndTime,
          equals(fullMapper.endTime),
          reason: 'zoom_to_fit must restore the full simulation end time',
        );

        // ── add_markers ────────────────────────────────────────────────────
        const markerName = 'm';
        const markerTime = 42;
        send(2, 'add_markers', const {
          'markers': [
            {'name': markerName, 'time': markerTime},
          ],
        });
        final markerResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 2,
          tester: tester,
        );
        expect(markerResp['error'], isNull);
        final markerItems =
            (markerResp['data'] as Map)['items'] as List<dynamic>;
        expect(markerItems, hasLength(1));
        expect((markerItems.first as Map)['name'], equals(markerName));

        expect(
          activeTab.read(markerStateProvider).getMarker(markerName),
          equals(markerTime),
          reason: 'add_markers must set the marker in markerStateProvider',
        );

        // ── remove_items ───────────────────────────────────────────────────
        // remove_items needs a registered item id, so add a signal first via
        // the same add_items command wcp_add_signal_test.dart exercises.
        send(3, 'add_items', const {'item_path': 'top.clk'});
        final addResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 3,
          tester: tester,
        );
        expect(addResp['error'], isNull);
        final addedItems = (addResp['data'] as Map)['items'] as List<dynamic>;
        expect(addedItems, hasLength(1));
        final signalId = (addedItems.first as Map)['id'] as int;

        expect(
          activeTab.read(signalGroupsProvider).signalCount,
          equals(1),
          reason:
              'precondition: add_items above must have added exactly '
              'one signal for remove_items to remove',
        );

        send(4, 'remove_items', {
          'ids': [signalId],
        });
        final removeResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 4,
          tester: tester,
        );
        expect(removeResp['error'], isNull);

        expect(
          activeTab.read(signalGroupsProvider).signalCount,
          equals(0),
          reason:
              'remove_items must remove the signal from signalGroupsProvider',
        );
      } finally {
        socket?.destroy();
        await container.read(remoteControlProvider.notifier).stopServer();
      }

      expect(tester.takeException(), isNull);
    },
  );
}
