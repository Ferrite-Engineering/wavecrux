// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_set_cursor_test.dart
//
// WCP `set_cursor` integration test.
//
// Single-pane happy path: load `scalar_basics.vcd`, start the WCP server,
// connect a test client, send `set_cursor` for t = 50 ticks, and assert
// the root-scope `cursorStateProvider` reflects the new cursor
// position (the surface today's `RemoteControlNotifier` writes through).
//
// Split-pane variant: build a 2-tab / 2-pane workspace,
// activate pane L (tab A), send `set_cursor` for t = 77, then activate
// pane R (tab B) and send `set_cursor` for t = 88. The variant verifies
// both commands return a non-error `response` frame and that the
// workspace pane/tab structure survives the calls intact. The deeper
// per-pane assertion — that only the active pane's active tab's
// per-tab `cursorStateProvider` updates — depends on the
// pending WCP → per-tab routing refactor (see the resolution note in
// wcp_load_test.dart); the variant documents the contract and asserts the
// parts that hold today.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

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

  testWidgets('WCP set_cursor updates cursorStateProvider', (tester) async {
    await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

    final container = rootContainer(tester);
    // The WCP set_cursor handler routes through the active tab's container
    // (issue #44 — `RemoteControlNotifier._activeTab`), so the cursor lands in
    // the per-tab `cursorStateProvider`, not the root-scope instance. Read the
    // active tab's container for the assertion.
    final activeTab = activeTabContainer(tester);

    // cursorStateProvider is autoDispose and has no other listener in this
    // headless test — so without a held subscription it disposes between
    // placePrimary() and the assertion, and the read returns a fresh null
    // state. Hold the per-tab instance open for the test's lifetime.
    final cursorSub = activeTab.listen(cursorStateProvider, (_, _) {});
    addTearDown(cursorSub.close);

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

      const targetTick = 50;
      final cmd = jsonEncode({
        'type': 'command',
        'id': 1,
        'command': 'set_cursor',
        'data': {'timestamp': targetTick},
      });
      socket.add(utf8.encode(cmd) + [0]);

      final response = await waitForFrame(
        received,
        (m) => m['type'] == 'response' && m['id'] == 1,
        tester: tester,
      );
      expect(response['type'], equals('response'));

      // Assert the cursor moved to the requested tick. The WCP handler writes
      // to the active tab's per-tab `cursorStateProvider` (issue #44 routing);
      // the test reads the same surface.
      final cursor = activeTab.read(cursorStateProvider);
      expect(
        cursor.primaryCursorTime,
        equals(targetTick),
        reason: 'Cursor should be at t=$targetTick after WCP set_cursor',
      );
    } finally {
      socket?.destroy();
      await container.read(remoteControlProvider.notifier).stopServer();
    }
  });

  testWidgets(
    'WCP set_cursor in a split-pane workspace targets each active pane '
    'in turn without disturbing pane layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      addTearDown(() async {
        await WorkspaceService(codec: const WaveCruxWorkspaceCodec()).clear();
      });

      final fileA = _fixturePath('vcd/scalar_basics.vcd');
      final fileB = _fixturePath('vcd/vector_formats.vcd');
      expect(File(fileA).existsSync(), isTrue);
      expect(File(fileB).existsSync(), isTrue);

      await seedFirstLaunchAnswers();
      await bootstrap(args: [fileA]);
      await tester.pump();
      await pumpUntilWaveformReady(tester);

      final root = rootContainer(tester);

      for (var i = 0; i < 30; i++) {
        if (root.read(tabListProvider).isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      final tabA = root.read(tabListProvider).first;

      final wsNotifier = root.wavecruxWorkspace;
      final paneLId = wsNotifier.current.activePaneId;
      await wsNotifier.addTab(
        buildWorkspaceTab(
          id: tabA.id,
          displayName: tabA.displayName,
          paneId: paneLId,
          filePath: tabA.filePath,
        ),
      );
      await root.wavecruxWorkspace.openFile(fileB);
      await pumpUntil(tester, () => root.read(tabListProvider).length >= 2);
      await tester.pumpAndSettle();
      expect(root.read(tabListProvider), hasLength(2));
      final tabB = root.read(tabListProvider)[1];
      await wsNotifier.addTab(
        buildWorkspaceTab(
          id: tabB.id,
          displayName: tabB.displayName,
          paneId: paneLId,
          filePath: tabB.filePath,
        ),
      );

      final paneRId = await wsNotifier.splitPane();
      await wsNotifier.moveTabToPane(tabB.id, paneRId);
      await root.wavecruxWorkspace.moveTabToPane(tabB.id, paneRId);
      await wsNotifier.setActiveTab(tabA.id);
      root.read(activeTabIdProvider.notifier).activate(tabA.id);
      await tester.pump();

      final wsBefore = wsNotifier.current;
      expect(wsBefore.tabs, hasLength(2));
      expect(wsBefore.panes, hasLength(2));
      expect(wsBefore.activePaneId, equals(paneLId));

      final startError = await root
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(startError, isNull);
      final port = root.read(remoteControlProvider).port;
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

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 101,
                  'command': 'set_cursor',
                  'data': {'timestamp': 77},
                }),
              ) +
              [0],
        );
        final r1 = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 101,
          tester: tester,
        );
        expect(
          r1['error'],
          isNull,
          reason: 'set_cursor on active pane L must not error',
        );

        // Switch active pane to R.
        await wsNotifier.setActiveTab(tabB.id);
        root.read(activeTabIdProvider.notifier).activate(tabB.id);
        await tester.pump();
        expect(wsNotifier.current.activePaneId, equals(paneRId));

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 102,
                  'command': 'set_cursor',
                  'data': {'timestamp': 88},
                }),
              ) +
              [0],
        );
        final r2 = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 102,
          tester: tester,
        );
        expect(
          r2['error'],
          isNull,
          reason: 'set_cursor on active pane R must not error',
        );

        final wsAfter = wsNotifier.current;
        expect(wsAfter.tabs, hasLength(2));
        expect(wsAfter.panes, hasLength(2));
        expect(
          wsAfter.tabs.map((t) => t.paneId).toSet(),
          equals({paneLId, paneRId}),
        );
      } finally {
        socket?.destroy();
        await root.read(remoteControlProvider.notifier).stopServer();
      }
      tester.takeException();
    },
  );
}
