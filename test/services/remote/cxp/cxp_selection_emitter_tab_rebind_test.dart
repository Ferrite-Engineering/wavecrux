// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter.dart'
    show kCxpCursorDebounce;
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter_provider.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wait_for.dart';

/// The automatic cursor and marker broadcast follows the active tab.
///
/// The app reads `cxpSelectionEmitterProvider` once at launch and nothing
/// listens to it afterwards, so Riverpod pauses it. The emitter re-binds its
/// per-tab cursor and marker listens when the active tab changes; that
/// re-bind has to be driven by a subscription the container owns, because a
/// paused provider's own subscription to a derived provider such as
/// `activeTabIdProvider` is never flushed. Every test here drives the
/// production provider, read once, and then switches tabs.
void main() {
  const pathA = '/designs/alu/wave_a.vcd';
  const pathB = '/designs/fifo/wave_b.vcd';

  late _RecordingRuntime runtime;
  late Directory manifests;
  late ProviderContainer container;
  late TabId tabA;
  late TabId tabB;

  /// Every tab shows the same signal under the same ref; what tells the tabs
  /// apart on the wire is the design the tab's file belongs to.
  final tabFiles = <TabId, String>{};

  /// Activates [id] and lets the container deliver the change to its
  /// listeners, as the frames between a click and the next cursor move do.
  Future<void> switchTo(TabId id) async {
    await container.wavecruxWorkspace.setActiveTab(id);
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    tabFiles.clear();
    manifests = Directory.systemTemp.createTempSync('cxp_emitter_rebind_');
    runtime = _RecordingRuntime(manifests.path);
    final tcm = TabContainerManager(
      extraTabOverrides: [
        waveformSourceProvider.overrideWith(
          () => _TabSourceNotifier(tabFiles),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        ...testWorkspaceOverrides(),
        tabContainerManagerProvider.overrideWithValue(tcm),
        cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding),
        cruxCxpLaunchSettingsProvider.overrideWithValue(
          const CruxCxpSettings(enabled: true, port: 0),
        ),
        cruxCxpRuntimeProvider.overrideWith((_) async => runtime),
      ],
    );
    tcm.init(container);
    addTearDown(() {
      tcm.dispose();
      container.dispose();
      manifests.deleteSync(recursive: true);
    });
    await container.read(workspaceProvider.future);
    await container.read(cruxCxpRuntimeProvider.future);

    tabA = await container.wavecruxWorkspace.openFile(pathA);
    tabB = await container.wavecruxWorkspace.openFile(pathB);
    tabFiles[tabA] = pathA;
    tabFiles[tabB] = pathB;
    // Selection is app-wide; both tabs resolve it to `top.sig`.
    container.read(selectedSignalProvider.notifier).select('top.sig');

    // Launch order, as in the app: one read of the emitter, tab B active.
    expect(
      container.read(tabListProvider).map((t) => t.id).toList(),
      [tabA, tabB],
    );
    container.read(cxpSelectionEmitterProvider);
    runtime.sent.clear();
  });

  test('after switching tabs, a cursor move in the new tab is broadcast from '
      'that tab and the old tab broadcasts nothing', () async {
    // Nothing reads the active tab id between the switch and the cursor move,
    // so only a subscription the container owns can notice the switch.
    await switchTo(tabA);

    // The old tab (B) is no longer the one the user works in.
    container
        .read(tabContainerManagerProvider)
        .containerFor(tabB)
        .read(cursorStateProvider.notifier)
        .placePrimary(900);
    await Future<void>.delayed(kCxpCursorDebounce * 3);
    expect(runtime.sent, isEmpty, reason: 'the old tab must not broadcast');

    container
        .read(tabContainerManagerProvider)
        .containerFor(tabA)
        .read(cursorStateProvider.notifier)
        .placePrimary(777);
    await waitFor(
      () => runtime.sent.isNotEmpty,
      reason: 'the new tab’s cursor move should be broadcast',
    );
    await Future<void>.delayed(kCxpCursorDebounce * 3);

    expect(runtime.sent, hasLength(1));
    final sent = runtime.sent.single;
    expect(sent.elements.single.path, 'top.sig');
    expect(sent.metadata['wavecrux.cursor_time_fs'], 777);
    expect(sent.metadata[cxpDesignIdMetadataKey], cxpDesignIdForPath(pathA));
    expect(
      cxpDesignIdForPath(pathA),
      isNot(cxpDesignIdForPath(pathB)),
      reason: 'the two tabs must be distinguishable on the wire',
    );
  });

  test('after switching tabs, a marker placed in the new tab is broadcast '
      'from that tab', () async {
    await switchTo(tabA);

    container
        .read(tabContainerManagerProvider)
        .containerFor(tabB)
        .read(markerStateProvider.notifier)
        .setMarker('b', 40);
    container
        .read(tabContainerManagerProvider)
        .containerFor(tabA)
        .read(markerStateProvider.notifier)
        .setMarker('a', 555);
    await waitFor(
      () => runtime.sent.isNotEmpty,
      reason: 'the new tab’s marker should be broadcast',
    );
    await Future<void>.delayed(kCxpCursorDebounce);

    expect(runtime.sent, hasLength(1));
    final sent = runtime.sent.single;
    expect(sent.elements.single.kind, ElementKind.marker);
    expect(sent.elements.single.path, 'a');
    expect(sent.metadata['wavecrux.cursor_time_fs'], 555);
    expect(sent.metadata[cxpDesignIdMetadataKey], cxpDesignIdForPath(pathA));
  });

  test('switching back and forth keeps following the active tab', () async {
    await switchTo(tabA);
    await switchTo(tabB);

    container
        .read(tabContainerManagerProvider)
        .containerFor(tabB)
        .read(cursorStateProvider.notifier)
        .placePrimary(321);
    await waitFor(
      () => runtime.sent.isNotEmpty,
      reason: 'the cursor move in the re-activated tab should be broadcast',
    );
    final sent = runtime.sent.last;
    expect(sent.metadata['wavecrux.cursor_time_fs'], 321);
    expect(sent.metadata[cxpDesignIdMetadataKey], cxpDesignIdForPath(pathB));
  });
}

/// A runtime that records what it is asked to broadcast and never opens a
/// socket.
class _RecordingRuntime extends CruxCxpRuntime {
  _RecordingRuntime(String manifestDirectory)
    : super(
        binding: kWaveCruxCxpBinding,
        productVersion: 'test',
        manifestDirectory: manifestDirectory,
        port: 0,
        handler: CruxCxpRequestHandler.new,
      );

  final List<NotifySelection> sent = <NotifySelection>[];

  @override
  void broadcast(CxpMessage message, {String? summary}) {
    if (message is NotifySelection) sent.add(message);
  }
}

/// A per-tab waveform source whose file is the one the test assigned to the
/// tab, holding the same one-signal design in every tab.
class _TabSourceNotifier extends WaveformSourceNotifier {
  _TabSourceNotifier(this._files);
  final Map<TabId, String> _files;

  @override
  AsyncValue<FakeWaveformDataSource> build() {
    currentFilePath = _files[ref.read(tabIdProvider)];
    return AsyncData(FakeWaveformDataSource(scopes: [_scope]));
  }
}

const Scope _scope = Scope(
  name: 'top',
  path: 'top',
  type: ScopeType.module,
  variables: [
    Variable(
      name: 'sig',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: 'top.sig',
      scopePath: 'top',
      bitWidth: 1,
    ),
  ],
);
