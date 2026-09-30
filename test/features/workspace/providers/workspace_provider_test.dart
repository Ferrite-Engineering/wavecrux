// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import 'package:wavecrux/services/workspace/window_bounds_store.dart';

import '../../../helpers/product_telemetry_config.dart';

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_ws_provider_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

ProviderContainer _containerFor(Directory dir) => ProviderContainer(
  overrides: [
    productTelemetryConfig,
    workspaceServiceProvider.overrideWithValue(
      WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
        directoryFactory: () async => dir,
        logger: (_) {},
      ),
    ),
  ],
);

WorkspaceTab _tab({
  required PaneId paneId,
  String name = 'a.vcd',
  String path = '/tmp/a.vcd',
}) => buildWorkspaceTab(
  id: TabId.generate(),
  displayName: name,
  paneId: paneId,
  filePath: path,
);

void main() {
  group('WorkspaceNotifier', () {
    test(
      'initial build loads from WorkspaceService (empty disk → empty)',
      () async {
        await _withTempDir((dir) async {
          final c = _containerFor(dir);
          addTearDown(c.dispose);
          final ws = await c.read(workspaceProvider.future);
          expect(ws.isEmpty, isTrue);
        });
      },
    );

    test('addTab appends a tab, activates it, and persists', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final paneId = (await c.read(workspaceProvider.future)).activePaneId;
        final tab = _tab(paneId: paneId);
        await notifier.addTab(tab);
        await notifier.flushPendingSave();

        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.tabs.single, equals(tab));
        expect(ws.activePane.activeTabId, equals(tab.id));

        // Hit disk: a fresh service against the same dir sees the same state.
        final reloaded = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ).load();
        expect(reloaded.tabs, hasLength(1));
        expect(reloaded.tabs.first.id, equals(tab.id));
      });
    });

    test('removeTab drops the tab and picks an adjacent active tab', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final paneId = (await c.read(workspaceProvider.future)).activePaneId;
        final a = _tab(paneId: paneId);
        final b = _tab(paneId: paneId, name: 'b.vcd', path: '/tmp/b.vcd');
        await notifier.addTab(a);
        await notifier.addTab(b);
        await notifier.removeTab(b.id);
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.tabs.map((t) => t.id), [a.id]);
        expect(ws.activePane.activeTabId, equals(a.id));
      });
    });

    test('reorderTabs moves a tab to a new index', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final paneId = (await c.read(workspaceProvider.future)).activePaneId;
        final a = _tab(paneId: paneId);
        final b = _tab(paneId: paneId, name: 'b.vcd', path: '/tmp/b.vcd');
        final cTab = _tab(paneId: paneId, name: 'c.vcd', path: '/tmp/c.vcd');
        await notifier.addTab(a);
        await notifier.addTab(b);
        await notifier.addTab(cTab);
        await notifier.reorderTabs(a.id, 2);
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.tabs.map((t) => t.id), [b.id, cTab.id, a.id]);
      });
    });

    test('setActiveTab updates the hosting pane and focuses it', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final initial = await c.read(workspaceProvider.future);
        final a = _tab(paneId: initial.activePaneId);
        final b = _tab(
          paneId: initial.activePaneId,
          name: 'b.vcd',
          path: '/tmp/b.vcd',
        );
        await notifier.addTab(a);
        await notifier.addTab(b);
        await notifier.setActiveTab(a.id);
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.activeTabId, equals(a.id));
      });
    });

    test('splitPane creates a second pane and makes it active', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        await c.read(workspaceProvider.future);
        final newPaneId = await notifier.splitPane();
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.panes, hasLength(2));
        expect(ws.activePaneId, equals(newPaneId));
      });
    });

    test('splitPane is a no-op when already split', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        await c.read(workspaceProvider.future);
        await notifier.splitPane();
        final firstSplitIds = c.read(workspaceProvider).requireValue.panes;
        await notifier.splitPane();
        final secondSplitIds = c.read(workspaceProvider).requireValue.panes;
        expect(secondSplitIds.length, equals(firstSplitIds.length));
      });
    });

    test('closePane merges tabs back into the survivor', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final initial = await c.read(workspaceProvider.future);
        final firstPane = initial.activePaneId;
        final a = _tab(paneId: firstPane);
        await notifier.addTab(a);
        final secondPane = await notifier.splitPane();
        final b = _tab(paneId: secondPane, name: 'b.vcd', path: '/tmp/b.vcd');
        await notifier.addTab(b);

        await notifier.closePane(secondPane);
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.panes, hasLength(1));
        expect(ws.panes.first.id, equals(firstPane));
        expect(ws.tabs.map((t) => t.id), containsAll([a.id, b.id]));
        for (final t in ws.tabs) {
          expect(t.paneId, equals(firstPane));
        }
      });
    });

    test('closePane is a no-op when only one pane exists', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final initial = await c.read(workspaceProvider.future);
        await notifier.closePane(initial.activePaneId);
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.panes, hasLength(1));
        expect(ws.panes.first.id, equals(initial.activePaneId));
      });
    });

    test('moveTabToPane transfers a tab between panes', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final initial = await c.read(workspaceProvider.future);
        final firstPane = initial.activePaneId;
        final a = _tab(paneId: firstPane);
        await notifier.addTab(a);
        final secondPane = await notifier.splitPane();

        await notifier.moveTabToPane(a.id, secondPane);

        final ws = c.read(workspaceProvider).requireValue;
        final movedTab = ws.tabs.firstWhere((t) => t.id == a.id);
        expect(movedTab.paneId, equals(secondPane));
        expect(ws.tabsForPane(secondPane), hasLength(1));
        expect(ws.tabsForPane(firstPane), isEmpty);
      });
    });

    test('reset clears the workspace and persists', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final initial = await c.read(workspaceProvider.future);
        await notifier.addTab(_tab(paneId: initial.activePaneId));
        await notifier.reset();
        await notifier.flushPendingSave();
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.isEmpty, isTrue);
      });
    });

    test('replaceFromNamed swaps in a named workspace document', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        await c.read(workspaceProvider.future);

        final paneId = PaneId.generate();
        final tabId = TabId.generate();
        final named = Workspace(
          tabs: [
            buildWorkspaceTab(
              id: tabId,
              displayName: 'named.vcd',
              paneId: paneId,
              filePath: '/elsewhere/named.vcd',
            ),
          ],
          panes: [WorkspacePane(id: paneId, activeTabId: tabId)],
          activePaneId: paneId,
        );

        await notifier.replaceFromNamed(named);
        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.tabs.single.displayName, equals('named.vcd'));
        expect(ws.panes.single.id, equals(paneId));
      });
    });

    test(
      'save is triggered after mutations (manual flush makes it observable)',
      () async {
        await _withTempDir((dir) async {
          final c = _containerFor(dir);
          addTearDown(c.dispose);
          final notifier = c.wavecruxWorkspace;
          final initial = await c.read(workspaceProvider.future);
          await notifier.addTab(_tab(paneId: initial.activePaneId));
          // Before flush: nothing on disk yet because the debounced timer hasn't
          // fired. After flushPendingSave the disk contents match the live state.
          await notifier.flushPendingSave();
          final loaded = await WorkspaceService(
            codec: const WaveCruxWorkspaceCodec(),
            directoryFactory: () async => dir,
            logger: (_) {},
          ).load();
          expect(loaded.tabs, hasLength(1));
        });
      },
    );

    test('flushPendingSave is the lifecycle-paused flush hook', () async {
      // Simulates AppLifecycleState.paused / detached: the mutation is in
      // memory only until the lifecycle handler explicitly flushes.
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final initial = await c.read(workspaceProvider.future);
        await notifier.addTab(_tab(paneId: initial.activePaneId));

        // Without flush, the freshly-mutated workspace lives only in memory:
        // a sibling service reading from disk sees the prior good state
        // (empty, in this test's case).
        final beforeFlush = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ).load();
        expect(
          beforeFlush.tabs,
          isEmpty,
          reason:
              'Auto-save is debounced; the in-memory tab must not appear on '
              'disk until flushPendingSave runs.',
        );

        await notifier.flushPendingSave();

        final afterFlush = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ).load();
        expect(afterFlush.tabs, hasLength(1));
      });
    });

    test('missing-file restoration drops the tab from the workspace', () async {
      // Restoration policy: tabs whose backing file no longer
      // exists are silently dropped and surfaced via snackbar. The
      // provider itself just exposes the workspace as it loaded from
      // disk — the lifecycle hook in [_WaveCruxAppState._restoreFromWorkspace]
      // applies the filter. This test asserts the seam the lifecycle hook
      // relies on: a workspace with stale-file tabs hydrates losslessly,
      // so the hook can read it and filter on its own terms.
      await _withTempDir((dir) async {
        final paneId = PaneId.generate();
        final aliveId = TabId.generate();
        final missingId = TabId.generate();
        final aliveTab = buildWorkspaceTab(
          id: aliveId,
          displayName: 'alive.vcd',
          paneId: paneId,
          filePath: '/no/such/file/alive.vcd',
        );
        final missingTab = buildWorkspaceTab(
          id: missingId,
          displayName: 'missing.vcd',
          paneId: paneId,
          filePath: '/no/such/file/missing.vcd',
        );
        await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ).save(
          Workspace(
            tabs: [aliveTab, missingTab],
            panes: [WorkspacePane(id: paneId, activeTabId: aliveId)],
            activePaneId: paneId,
          ),
        );

        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final hydrated = await c.read(workspaceProvider.future);
        expect(hydrated.tabs, hasLength(2));
        expect(
          hydrated.tabs.map((t) => t.filePath).toList(),
          containsAll([aliveTab.filePath, missingTab.filePath]),
        );
      });
    });

    test(
      'build sanitizes a loaded workspace by dropping empty sibling panes '
      'when at least one pane is populated (heals legacy bad state)',
      () async {
        // Simulates the user-reported regression: a workspace.json that
        // ended up with two panes — one populated, one empty — because a
        // previous flush ran before the live-tab → workspace mirror could
        // collapse the stranded empty pane. Without sanitization on load
        // the user sees two panes after restart with no UI affordance to
        // close the empty one.
        await _withTempDir((dir) async {
          final populated = PaneId.generate();
          final empty = PaneId.generate();
          final tabId = TabId.generate();
          final tab = buildWorkspaceTab(
            id: tabId,
            displayName: 'a.vcd',
            paneId: populated,
            filePath: '/no/such/file/a.vcd',
          );
          await WorkspaceService(
            codec: const WaveCruxWorkspaceCodec(),
            directoryFactory: () async => dir,
            logger: (_) {},
          ).save(
            Workspace(
              tabs: [tab],
              panes: [
                WorkspacePane(id: populated, activeTabId: tabId),
                WorkspacePane(id: empty),
              ],
              activePaneId: empty,
            ),
          );

          final c = _containerFor(dir);
          addTearDown(c.dispose);
          final hydrated = await c.read(workspaceProvider.future);
          expect(
            hydrated.panes,
            hasLength(1),
            reason:
                'the empty sibling pane must be dropped — empty panes alongside '
                'populated ones cannot be closed from the UI and indicate a '
                'previous-session flush race',
          );
          expect(hydrated.panes.single.id, equals(populated));
          expect(
            hydrated.activePaneId,
            equals(populated),
            reason:
                'when the persisted activePaneId pointed at the dropped empty '
                'pane, activation must fall back to the surviving populated pane',
          );
        });
      },
    );

    test(
      'build keeps exactly one pane (no tabs) when the loaded workspace has '
      'multiple empty panes — the canonical empty-canvas state',
      () async {
        await _withTempDir((dir) async {
          final activePane = PaneId.generate();
          final otherPane = PaneId.generate();
          await WorkspaceService(
            codec: const WaveCruxWorkspaceCodec(),
            directoryFactory: () async => dir,
            logger: (_) {},
          ).save(
            Workspace(
              tabs: const [],
              panes: [
                WorkspacePane(id: activePane),
                WorkspacePane(id: otherPane),
              ],
              activePaneId: activePane,
            ),
          );

          final c = _containerFor(dir);
          addTearDown(c.dispose);
          final hydrated = await c.read(workspaceProvider.future);
          expect(hydrated.panes, hasLength(1));
          expect(hydrated.panes.single.id, equals(activePane));
          expect(hydrated.activePaneId, equals(activePane));
        });
      },
    );
  });

  group('setWindowBounds', () {
    test('stores bounds in extras and persists to disk', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        await c.read(workspaceProvider.future);

        const bounds = WindowBounds(
          left: 120,
          top: 80,
          width: 1600,
          height: 1000,
        );
        await notifier.setWindowBounds(bounds);
        await notifier.flushPendingSave();

        // In-memory extras updated.
        final ws = c.read(workspaceProvider).requireValue;
        expect(windowBoundsFromExtras(ws.extras), bounds);

        // Hit disk: a fresh service against the same dir sees the same bounds.
        final reloaded = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ).load();
        expect(windowBoundsFromExtras(reloaded.extras), bounds);
      });
    });

    test('preserves tabs/panes while recording window bounds', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final paneId = (await c.read(workspaceProvider.future)).activePaneId;
        final tab = _tab(paneId: paneId);
        await notifier.addTab(tab);

        await notifier.setWindowBounds(
          const WindowBounds(width: 1280, height: 720),
        );

        final ws = c.read(workspaceProvider).requireValue;
        expect(ws.tabs.single, equals(tab));
        expect(ws.activePane.activeTabId, equals(tab.id));
        expect(windowBoundsFromExtras(ws.extras)?.width, 1280);
      });
    });

    test('a later call overwrites the previous bounds', () async {
      await _withTempDir((dir) async {
        final c = _containerFor(dir);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        await c.read(workspaceProvider.future);

        await notifier.setWindowBounds(
          const WindowBounds(left: 0, top: 0, width: 800, height: 600),
        );
        await notifier.setWindowBounds(
          const WindowBounds(left: 50, top: 50, width: 1400, height: 900),
        );

        final ws = c.read(workspaceProvider).requireValue;
        expect(
          windowBoundsFromExtras(ws.extras),
          const WindowBounds(left: 50, top: 50, width: 1400, height: 900),
        );
      });
    });
  });
}
