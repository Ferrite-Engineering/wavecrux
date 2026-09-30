// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression guard: persisting window geometry must NOT evict live scopes.
//
// The window-geometry persister (`buildWindowGeometryPersister` in app.dart)
// calls `setWindowBounds` on every resize / move / maximize, debounced. That
// write lands in the workspace document's `extras`, so it used to go through
// `crux.WorkspaceNotifier.replaceWith` — a *wholesale document replacement*
// which emits an empty scope snapshot first, disposing every per-tab and
// per-pane `ProviderContainer`.
//
// The visible failure: maximizing the window with a waveform open threw
//
//     Unsupported operation: ProviderScope was rebuilt with a different
//     ProviderScope ancestor
//
// mid-layout, from the nested `ProviderScope` in `_PaneScopedCanvas`. PaneHost
// keys each tab's subtree on the tab id, so the elements survived the swap
// while the per-tab `UncontrolledProviderScope` above them re-resolved to a
// brand-new container. In release mode (where the Riverpod assert is compiled
// out) the same write silently discarded every tab's per-tab state — cursors,
// zoom, signal groups, decoders, loaded waveform — on each resize.
//
// The fix routes incremental edits through `crux.WorkspaceNotifier.mutate`,
// which reconciles scopes against the new document instead of clearing them.
// These tests pin container *identity* across the incremental paths, and
// re-assert that the genuine document-replacement paths still evict.

import 'dart:io';

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';
import 'package:wavecrux/services/workspace/window_bounds_store.dart';

import '../../../helpers/product_telemetry_config.dart';

/// Everything bootstrap() wires up that matters here: the two container
/// managers, rooted in the container and registered as scope reconcilers on
/// the workspace notifier.
class _Harness {
  _Harness(this.container, this.tcm, this.pcm);

  final ProviderContainer container;
  final TabContainerManager tcm;
  final PaneContainerManager pcm;

  WaveCruxWorkspaceNotifier get notifier => container.wavecruxWorkspace;
}

Future<T> _withHarness<T>(Future<T> Function(_Harness h) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_ws_scope_');
  final tcm = TabContainerManager();
  final pcm = PaneContainerManager();
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      workspaceServiceProvider.overrideWithValue(
        WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ),
      ),
      tabContainerManagerProvider.overrideWithValue(tcm),
      paneContainerManagerProvider.overrideWithValue(pcm),
    ],
  );
  tcm.init(container);
  pcm.init(container);
  await container.read(workspaceProvider.future);
  container.wavecruxWorkspace
    ..addScopeReconciler(tcm)
    ..addScopeReconciler(pcm);
  try {
    return await fn(_Harness(container, tcm, pcm));
  } finally {
    container.dispose();
    tcm.dispose();
    pcm.dispose();
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

void main() {
  group('setWindowBounds preserves live scopes', () {
    test('a resize keeps the open tab and pane containers identical', () async {
      await _withHarness((h) async {
        final paneId = (await h.container.read(
          workspaceProvider.future,
        )).activePaneId;
        final tab = buildWorkspaceTab(
          id: TabId.generate(),
          displayName: 'a.vcd',
          paneId: paneId,
          filePath: '/tmp/a.vcd',
        );
        await h.notifier.addTab(tab);

        final tabContainer = h.tcm.containerFor(tab.id);
        final paneContainer = h.pcm.containerFor(paneId);

        // One drag of the window edge fires this many times over.
        for (var width = 1200.0; width <= 1204.0; width += 1) {
          await h.notifier.setWindowBounds(
            WindowBounds(width: width, height: 800),
          );
        }

        expect(
          identical(h.tcm.containerFor(tab.id), tabContainer),
          isTrue,
          reason:
              'the open tab was handed a fresh container mid-resize — the '
              '"ProviderScope was rebuilt with a different ProviderScope '
              'ancestor" crash',
        );
        expect(
          identical(h.pcm.containerFor(paneId), paneContainer),
          isTrue,
          reason: 'the hosting pane was handed a fresh container mid-resize',
        );
        // The geometry still landed.
        final ws = h.container.read(workspaceProvider).requireValue;
        expect(windowBoundsFromExtras(ws.extras)?.width, 1204);
      });
    });

    test(
      'adding a second tab leaves the first tab’s container alone',
      () async {
        await _withHarness((h) async {
          final paneId = (await h.container.read(
            workspaceProvider.future,
          )).activePaneId;
          final first = buildWorkspaceTab(
            id: TabId.generate(),
            displayName: 'a.vcd',
            paneId: paneId,
            filePath: '/tmp/a.vcd',
          );
          await h.notifier.addTab(first);
          final firstContainer = h.tcm.containerFor(first.id);

          await h.notifier.addTab(
            buildWorkspaceTab(
              id: TabId.generate(),
              displayName: 'b.vcd',
              paneId: paneId,
              filePath: '/tmp/b.vcd',
            ),
          );

          expect(
            identical(h.tcm.containerFor(first.id), firstContainer),
            isTrue,
          );
        });
      },
    );

    test('splitting the pane leaves the existing scopes alone', () async {
      await _withHarness((h) async {
        final paneId = (await h.container.read(
          workspaceProvider.future,
        )).activePaneId;
        final tab = buildWorkspaceTab(
          id: TabId.generate(),
          displayName: 'a.vcd',
          paneId: paneId,
          filePath: '/tmp/a.vcd',
        );
        await h.notifier.addTab(tab);
        final tabContainer = h.tcm.containerFor(tab.id);
        final paneContainer = h.pcm.containerFor(paneId);

        await h.notifier.splitPane();

        expect(identical(h.tcm.containerFor(tab.id), tabContainer), isTrue);
        expect(identical(h.pcm.containerFor(paneId), paneContainer), isTrue);
      });
    });
  });

  group('document replacement still evicts', () {
    test('reset() drops every tab and pane container', () async {
      await _withHarness((h) async {
        final paneId = (await h.container.read(
          workspaceProvider.future,
        )).activePaneId;
        final tab = buildWorkspaceTab(
          id: TabId.generate(),
          displayName: 'a.vcd',
          paneId: paneId,
          filePath: '/tmp/a.vcd',
        );
        await h.notifier.addTab(tab);
        final tabContainer = h.tcm.containerFor(tab.id);
        final paneContainer = h.pcm.containerFor(paneId);

        await h.notifier.reset();

        expect(identical(h.tcm.containerFor(tab.id), tabContainer), isFalse);
        expect(identical(h.pcm.containerFor(paneId), paneContainer), isFalse);
      });
    });

    test('replaceFromNamed gives a reused tab id a FRESH container', () async {
      await _withHarness((h) async {
        final paneId = (await h.container.read(
          workspaceProvider.future,
        )).activePaneId;
        final tab = buildWorkspaceTab(
          id: TabId.generate(),
          displayName: 'a.vcd',
          paneId: paneId,
          filePath: '/tmp/a.vcd',
        );
        await h.notifier.addTab(tab);
        final before = h.tcm.containerFor(tab.id);

        // A named workspace document that reuses the same tab id — the
        // resurrection case `replaceWith`'s unconditional eviction exists for.
        await h.notifier.replaceFromNamed(
          h.container.read(workspaceProvider).requireValue,
        );

        expect(identical(h.tcm.containerFor(tab.id), before), isFalse);
      });
    });
  });
}
