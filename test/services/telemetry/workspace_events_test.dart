// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

/// Captures every recorded [TelemetryEvent] in memory for assertions.
class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = [];

  @override
  void record(TelemetryEvent event) {
    events.add(event);
  }

  Iterable<String> get names => events.map((e) => e.name);
}

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_ws_telemetry_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

ProviderContainer _containerFor(
  Directory dir,
  _RecordingTelemetryService telemetry,
) => ProviderContainer(
  overrides: [
    workspaceServiceProvider.overrideWithValue(
      WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
        directoryFactory: () async => dir,
        logger: (_) {},
      ),
    ),
    telemetryServiceProvider.overrideWithValue(telemetry),
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
  group('Workspace telemetry instrumentation', () {
    test('build emits workspace.restored with tab and pane counts', () async {
      await _withTempDir((dir) async {
        final telemetry = _RecordingTelemetryService();
        final c = _containerFor(dir, telemetry);
        addTearDown(c.dispose);

        await c.read(workspaceProvider.future);
        final restored = telemetry.events
            .where((e) => e.name == 'workspace.restored')
            .toList();
        expect(restored, hasLength(1));
        expect(restored.single.properties['tabs'], 0);
        expect(restored.single.properties['panes'], 1);
      });
    });

    test('addTab emits tab.opened with tab and pane counts', () async {
      await _withTempDir((dir) async {
        final telemetry = _RecordingTelemetryService();
        final c = _containerFor(dir, telemetry);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final paneId = (await c.read(workspaceProvider.future)).activePaneId;
        telemetry.events.clear();
        await notifier.addTab(_tab(paneId: paneId));
        await notifier.flushPendingSave();
        final opened = telemetry.events
            .where((e) => e.name == 'tab.opened')
            .toList();
        expect(opened, hasLength(1));
        expect(opened.single.properties['tabs'], 1);
        expect(opened.single.properties['panes'], 1);
      });
    });

    test(
      'addTab does not re-emit tab.opened on a duplicate-id no-op',
      () async {
        await _withTempDir((dir) async {
          final telemetry = _RecordingTelemetryService();
          final c = _containerFor(dir, telemetry);
          addTearDown(c.dispose);
          final notifier = c.wavecruxWorkspace;
          final paneId = (await c.read(workspaceProvider.future)).activePaneId;
          final tab = _tab(paneId: paneId);
          await notifier.addTab(tab);
          telemetry.events.clear();
          // Re-adding the same tab id is a no-op and must not record an event.
          await notifier.addTab(tab);
          await notifier.flushPendingSave();
          expect(
            telemetry.events.where((e) => e.name == 'tab.opened'),
            isEmpty,
          );
        });
      },
    );

    test('reset emits workspace.reset', () async {
      await _withTempDir((dir) async {
        final telemetry = _RecordingTelemetryService();
        final c = _containerFor(dir, telemetry);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final paneId = (await c.read(workspaceProvider.future)).activePaneId;
        await notifier.addTab(_tab(paneId: paneId));
        telemetry.events.clear();
        await notifier.reset();
        await notifier.flushPendingSave();
        expect(telemetry.names, contains('workspace.reset'));
      });
    });

    test('splitPane emits pane.split once per actual split', () async {
      await _withTempDir((dir) async {
        final telemetry = _RecordingTelemetryService();
        final c = _containerFor(dir, telemetry);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        await c.read(workspaceProvider.future);
        telemetry.events.clear();
        await notifier.splitPane();
        // A second split() call when already split is a no-op and must NOT
        // re-emit pane.split.
        await notifier.splitPane();
        await notifier.flushPendingSave();
        expect(
          telemetry.events.where((e) => e.name == 'pane.split'),
          hasLength(1),
        );
      });
    });

    test('closePane emits pane.closed', () async {
      await _withTempDir((dir) async {
        final telemetry = _RecordingTelemetryService();
        final c = _containerFor(dir, telemetry);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        await c.read(workspaceProvider.future);
        final secondaryId = await notifier.splitPane();
        telemetry.events.clear();
        await notifier.closePane(secondaryId);
        await notifier.flushPendingSave();
        expect(telemetry.names, contains('pane.closed'));
      });
    });

    test('moveTabToPane emits tab.dragged_to_pane', () async {
      await _withTempDir((dir) async {
        final telemetry = _RecordingTelemetryService();
        final c = _containerFor(dir, telemetry);
        addTearDown(c.dispose);
        final notifier = c.wavecruxWorkspace;
        final paneId = (await c.read(workspaceProvider.future)).activePaneId;
        final tab = _tab(paneId: paneId);
        await notifier.addTab(tab);
        final otherPaneId = await notifier.splitPane();
        telemetry.events.clear();
        await notifier.moveTabToPane(tab.id, otherPaneId);
        await notifier.flushPendingSave();
        expect(telemetry.names, contains('tab.dragged_to_pane'));
      });
    });

    test(
      'replaceFromNamed emits workspace.named.opened with tab/pane counts',
      () async {
        await _withTempDir((dir) async {
          final telemetry = _RecordingTelemetryService();
          final c = _containerFor(dir, telemetry);
          addTearDown(c.dispose);
          final notifier = c.wavecruxWorkspace;
          await c.read(workspaceProvider.future);
          final paneId = PaneId.generate();
          final tab = buildWorkspaceTab(
            id: TabId.generate(),
            displayName: 'demo.vcd',
            paneId: paneId,
            filePath: '/tmp/demo.vcd',
          );
          final replacement = Workspace(
            tabs: [tab],
            panes: [WorkspacePane(id: paneId, activeTabId: tab.id)],
            activePaneId: paneId,
          );
          telemetry.events.clear();
          await notifier.replaceFromNamed(replacement);
          await notifier.flushPendingSave();
          final emitted = telemetry.events.firstWhere(
            (e) => e.name == 'workspace.named.opened',
          );
          expect(emitted.properties['tabs'], 1);
          expect(emitted.properties['panes'], 1);
        });
      },
    );
  });
}
