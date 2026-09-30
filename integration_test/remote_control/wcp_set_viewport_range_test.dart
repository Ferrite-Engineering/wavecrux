// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_set_viewport_range_test.dart
//
// WCP `set_viewport_range` integration test.
//
// Single-pane happy path: load a fixture, start the WCP server, send
// `set_viewport_range` for [0, 100] and verify the response frame is a
// non-error `response`.
//
// Split-pane variant: build a 2-tab / 2-pane workspace.
// Issue `set_viewport_range` while pane L is active, then activate pane
// R and issue a second range. Both commands must return a non-error
// response and the workspace pane/tab structure must survive the calls.
// The deeper per-pane assertion — that the active pane's active tab's
// `navigationProvider` updates while the inactive pane's stays
// unchanged — depends on the pending WCP → per-tab routing refactor
// (see the resolution note in wcp_load_test.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
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

  testWidgets('WCP set_viewport_range completes against a loaded file', (
    tester,
  ) async {
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
        timeout: const Duration(seconds: 5),
      );
      expect(greeting['type'], equals('greeting'));

      socket.add(
        utf8.encode(
              jsonEncode({
                'type': 'command',
                'id': 1,
                'command': 'set_viewport_range',
                'data': {'start': 0, 'end': 100},
              }),
            ) +
            [0],
      );
      final response = await waitForFrame(
        received,
        (m) => m['type'] == 'response' && m['id'] == 1,
        tester: tester,
      );
      expect(
        response['error'],
        isNull,
        reason: 'set_viewport_range against a loaded file must not error',
      );
    } finally {
      socket?.destroy();
      await container.read(remoteControlProvider.notifier).stopServer();
    }
  });

  testWidgets(
    'WCP set_viewport_range in a split-pane workspace completes for '
    'each active pane without disturbing pane layout',
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
                  'id': 301,
                  'command': 'set_viewport_range',
                  'data': {'start': 0, 'end': 50},
                }),
              ) +
              [0],
        );
        final r1 = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 301,
          tester: tester,
        );
        expect(
          r1['error'],
          isNull,
          reason: 'set_viewport_range on active pane L must not error',
        );

        await wsNotifier.setActiveTab(tabB.id);
        root.read(activeTabIdProvider.notifier).activate(tabB.id);
        await tester.pump();
        expect(wsNotifier.current.activePaneId, equals(paneRId));

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 302,
                  'command': 'set_viewport_range',
                  'data': {'start': 25, 'end': 75},
                }),
              ) +
              [0],
        );
        final r2 = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 302,
          tester: tester,
        );
        expect(
          r2['error'],
          isNull,
          reason: 'set_viewport_range on active pane R must not error',
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
