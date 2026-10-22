// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_active_document.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';

import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

/// The window's active document reaches the shared CXP runtime
/// ([CruxCxpRuntime.setActiveDocument], CXP §8.1), so a peer's "Cross-probe
/// to" menu names the waveform this window shows, and it follows the active
/// tab.
void main() {
  late Directory manifests;

  setUp(() {
    manifests = Directory.systemTemp.createTempSync('cxp_active_document_');
  });
  tearDown(() => manifests.deleteSync(recursive: true));

  CruxCxpRuntime runtime() => CruxCxpRuntime(
    binding: kWaveCruxCxpBinding,
    productVersion: 'test',
    manifestDirectory: manifests.path,
    port: 0,
    handler: CruxCxpRequestHandler.new,
  );

  Future<ProviderContainer> containerWith(
    Future<CruxCxpRuntime?> Function() runtime,
  ) async {
    final container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        ...testWorkspaceOverrides(),
        cruxCxpRuntimeProvider.overrideWith((ref) => runtime()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(workspaceProvider.future);
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('follows the active tab, by file name only', () async {
    final rt = runtime();
    final container = await containerWith(() async => rt);
    await container.read(cruxCxpRuntimeProvider.future);
    container.read(cxpActiveDocumentPublisherProvider);
    await settle();
    expect(rt.activeDocument, isNull, reason: 'no tab is open');

    final first = await container.wavecruxWorkspace.openFile(
      '/designs/alu/gold_vs_gate.vcd',
    );
    await settle();
    expect(rt.activeDocument, 'gold_vs_gate.vcd');

    await container.wavecruxWorkspace.openFile('/designs/fifo/trace.vcd');
    await settle();
    expect(rt.activeDocument, 'trace.vcd');

    await container.wavecruxWorkspace.setActiveTab(first);
    await settle();
    expect(rt.activeDocument, 'gold_vs_gate.vcd');
  });

  test('a runtime that starts after the tab opened is told at once', () async {
    final rt = runtime();
    final started = Completer<CruxCxpRuntime?>();
    final container = await containerWith(() => started.future);
    container.read(cxpActiveDocumentPublisherProvider);
    await container.wavecruxWorkspace.openFile('/designs/alu/trace.vcd');
    await settle();

    started.complete(rt);
    await container.read(cruxCxpRuntimeProvider.future);
    await settle();
    expect(rt.activeDocument, 'trace.vcd');
  });

  test('the document is the active tab’s, read from the tab list', () async {
    final container = await containerWith(() async => null);
    expect(container.read(cxpActiveDocumentProvider), isNull);
    await container.wavecruxWorkspace.openFile('/designs/a.vcd');
    expect(container.read(cxpActiveDocumentProvider), '/designs/a.vcd');
    expect(container.read(tabListProvider), hasLength(1));
  });
}
