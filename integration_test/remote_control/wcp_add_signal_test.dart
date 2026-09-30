// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_add_signal_test.dart
//
// WCP `add_items` integration test.
//
// Single-pane happy path: load `scalar_basics.vcd`, start the WCP server
// on an ephemeral port, connect a test client, send `add_items` for
// `top.clk`, and assert the signal appears in the root-scope
// `signalGroupsProvider`.
//
// Split-pane variant: build a 2-tab / 2-pane workspace.
// Issue `add_items` while pane L is active, then switch active pane to
// R and issue a second `add_items`. The variant verifies that both
// commands return a non-error `response` frame and that the workspace
// pane/tab structure survives the calls intact. The deeper per-pane
// assertion — that the new signal lands in the active pane's active
// tab's per-tab signal-groups provider, not the root-scope one — depends
// on the WCP → per-tab routing refactor tracked separately in the Phase
// 19.4 plan resolution note. The variant locks in the structural surface
// today so the routing refactor's regression net is in place.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
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

  testWidgets('WCP add_items adds signal to signal groups', (tester) async {
    await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

    final container = rootContainer(tester);
    // The WCP add_items handler routes through the active tab's container
    // (issue #44 — `RemoteControlNotifier._activeTab`), so the signal lands in
    // the per-tab `signalGroupsProvider`. Read the active tab's container.
    final activeTab = activeTabContainer(tester);

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

      // The WCP → per-tab routing refactor (issue #44) has landed: both `load`
      // and `add_items` now resolve `RemoteControlNotifier._activeTab`, so they
      // target the active tab's own source — already populated by the CLI open
      // above. This explicit `load` re-asserts the active tab's source and keeps
      // the frame sequence the assertions wait on; it is no longer needed to
      // bridge a root-vs-per-tab gap.
      socket.add(
        utf8.encode(
              jsonEncode({
                'type': 'command',
                'id': 100,
                'command': 'load',
                'data': {
                  'source': _fixturePath('vcd/scalar_basics.vcd'),
                },
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

      const signalPath = 'top.clk';
      final cmd = jsonEncode({
        'type': 'command',
        'id': 1,
        'command': 'add_items',
        'data': {'item_path': signalPath},
      });
      socket.add(utf8.encode(cmd) + [0]);

      final response = await waitForFrame(
        received,
        (m) => m['type'] == 'response' && m['id'] == 1,
        tester: tester,
      );
      expect(response['type'], equals('response'));

      final groups = activeTab.read(signalGroupsProvider);
      expect(
        groups.signalCount,
        greaterThan(0),
        reason: 'Signal should have been added via add_items',
      );
    } finally {
      socket?.destroy();
      await container.read(remoteControlProvider.notifier).stopServer();
    }
  });

  testWidgets(
    'WCP add_items in a split-pane workspace completes for each '
    'active pane without disturbing pane layout',
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

        // Re-assert the active tab's (pane L / tabA = scalar_basics) source —
        // see preamble note on the single-pane test above. WCP commands route
        // through `RemoteControlNotifier._activeTab` (issue #44), so add_items
        // below resolves item paths against whichever pane is active.
        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 200,
                  'command': 'load',
                  'data': {'source': fileA},
                }),
              ) +
              [0],
        );
        final loadResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 200,
          tester: tester,
        );
        expect(loadResp['error'], isNull);

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 201,
                  'command': 'add_items',
                  'data': {'item_path': 'top.clk'},
                }),
              ) +
              [0],
        );
        final r1 = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 201,
          tester: tester,
        );
        expect(
          r1['error'],
          isNull,
          reason: 'add_items on active pane L must not error',
        );

        await wsNotifier.setActiveTab(tabB.id);
        root.read(activeTabIdProvider.notifier).activate(tabB.id);
        await tester.pump();
        expect(wsNotifier.current.activePaneId, equals(paneRId));

        // tabB lives in the previously-inactive pane R; ViewerScreen
        // lazy-loads only each pane's active tab, so tabB's per-tab source may
        // still be empty here. WCP commands route through the active tab's
        // container (issue #44), so a wcp.load now populates tabB's source —
        // mirroring the pane-L preamble above — before add_items resolves a
        // path against it.
        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 202,
                  'command': 'load',
                  'data': {'source': fileB},
                }),
              ) +
              [0],
        );
        final loadBResp = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 202,
          tester: tester,
        );
        expect(
          loadBResp['error'],
          isNull,
          reason: 'load(fileB) on active pane R must not error',
        );

        socket.add(
          utf8.encode(
                jsonEncode({
                  'type': 'command',
                  'id': 203,
                  'command': 'add_items',
                  // Pane R hosts tabB = vector_formats.vcd; add_items routes to
                  // tabB's own source (issue #44), so the path must name a signal
                  // that exists there (scalar_basics' top.rst does not).
                  'data': {'item_path': 'top.bit1'},
                }),
              ) +
              [0],
        );
        final r2 = await waitForFrame(
          received,
          (m) => m['type'] == 'response' && m['id'] == 203,
          tester: tester,
        );
        expect(
          r2['error'],
          isNull,
          reason: 'add_items on active pane R must not error',
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
