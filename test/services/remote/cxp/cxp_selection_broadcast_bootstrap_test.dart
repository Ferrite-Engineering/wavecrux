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
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wait_for.dart';

/// The live selection broadcast, started the way the app starts it.
///
/// The app reads `cxpLifecycleBridgeProvider` and then
/// `cxpSelectionEmitterProvider` once at launch. The bridge starts the server
/// asynchronously, so that read happens while the server is still stopped.
/// Nothing reads the emitter provider again, so the emitter built by that one
/// read has to broadcast through the server once it is up. An emitter that
/// waited for a rebuild after the server started would never run: no selection
/// broadcast at all, while the per-peer send (which does not go through the
/// emitter) keeps working.
///
/// The receiving side is a second, independent CXP node wired the way the peer
/// products wire theirs: a `LocalCxpServer`, a manifest in the shared peers
/// directory, `CxpDiscovery`, and a `CxpPeerConnector` that dials every
/// discovered peer and subscribes on the link. Nothing here subscribes by hand.
void main() {
  late Directory peersDir;
  late ProviderContainer container;

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
    peersDir = await Directory.systemTemp.createTemp('wavecrux_cxp_boot_');
    container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        cxpManifestDirectoryProvider.overrideWith((_) async => peersDir.path),
        // Port 0: let the OS pick, so parallel test runs never collide.
        settingsServiceProvider.overrideWithValue(
          const _FakeSettingsService(AppSettings(cxpServerPort: 0)),
        ),
        waveformSourceProvider.overrideWith(
          () => _PreloadedSourceNotifier(
            FakeWaveformDataSource(scopes: [_scope]),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    await container.read(cxpServerProvider.notifier).stopServer();
    container.dispose();
    if (peersDir.existsSync()) peersDir.deleteSync(recursive: true);
  });

  test(
    'a selection made after launch reaches a discovered peer node',
    () async {
      // Launch order, as in the app: bridge first, then one read of the
      // emitter while the server is still starting.
      container
        ..read(cxpLifecycleBridgeProvider)
        ..read(cxpSelectionEmitterProvider);
      await waitFor(
        () => container.read(cxpServerProvider).isRunning,
        timeout: const Duration(seconds: 10),
        reason: 'the lifecycle bridge should start the CXP server',
      );

      final peer = await _PeerNode.start(peersDir.path);
      addTearDown(peer.stop);
      final notifySelections = <NotifySelection>[];
      final sub = peer.server.inbound.listen((m) {
        final body = m.message;
        if (body is NotifySelection) notifySelections.add(body);
      });
      addTearDown(sub.cancel);

      // Both directions dialled and subscribed: the peer is known to
      // WaveCrux's server and WaveCrux is known to the peer's.
      await waitFor(
        () =>
            (container
                        .read(cxpServerProvider.notifier)
                        .server
                        ?.connectedPeers ??
                    const <PeerIdentity>[])
                .any((p) => p.peerId == peer.identity.peerId) &&
            peer.server.connectedPeers.any(
              (p) => p.productName == 'wavecrux',
            ),
        timeout: const Duration(seconds: 15),
        reason: 'the two nodes should find and dial each other',
      );
      // The selection the issue describes: clk_a focused by the handoff,
      // then a click on captured_b.
      container.read(selectedSignalProvider.notifier).select('top.clk_a');
      container.read(selectedSignalProvider.notifier).select('top.captured_b');

      // The peer's Subscribe travels on its own link and may land just after
      // the handshake the wait above observed. Rather than guess how long
      // that takes, click captured_b again on each poll (a click re-notifies
      // even when the focus is unchanged) until one broadcast arrives. An
      // emitter that never runs fails this however often it is clicked.
      await waitFor(
        () {
          if (notifySelections.any(
            (n) => n.elements.single.path == 'top.captured_b',
          )) {
            return true;
          }
          container
              .read(selectedSignalProvider.notifier)
              .select('top.captured_b', notifyIfUnchanged: true);
          return false;
        },
        interval: const Duration(milliseconds: 100),
        reason:
            'the selection change must be broadcast to the subscribed peer '
            'without anything re-reading the emitter provider',
      );
    },
  );
}

const Scope _scope = Scope(
  name: 'top',
  path: 'top',
  type: ScopeType.module,
  variables: [
    Variable(
      name: 'clk_a',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: 'top.clk_a',
      scopePath: 'top',
      bitWidth: 1,
    ),
    Variable(
      name: 'captured_b',
      varType: VarType.reg,
      direction: VarDirection.output,
      signalRef: 'top.captured_b',
      scopePath: 'top',
      bitWidth: 1,
    ),
  ],
);

/// A CXP node wired like a peer product: server, manifest, discovery, and a
/// connector that dials every discovered peer with the default subscription.
class _PeerNode {
  _PeerNode._(
    this.identity,
    this.server,
    this._writer,
    this._discovery,
    this._connector,
  );

  static Future<_PeerNode> start(String peersDir) async {
    const identity = PeerIdentity(
      peerId: 'peercrux-test-1',
      productName: 'peercrux',
      productVersion: '0.0.0',
    );
    final server = LocalCxpServer(selfIdentity: identity);
    await server.start();
    final writer = CxpManifestWriter(manifestDirectory: peersDir);
    await writer.write(
      identity: identity,
      host: '127.0.0.1',
      port: server.boundPort!,
    );
    final discovery = CxpDiscovery(
      manifestDirectory: peersDir,
      scanInterval: const Duration(milliseconds: 100),
    );
    await discovery.start();
    final connector = CxpPeerConnector(
      selfIdentity: identity,
      discovery: discovery,
      server: server,
      retryInterval: const Duration(milliseconds: 200),
    )..start();
    return _PeerNode._(identity, server, writer, discovery, connector);
  }

  final PeerIdentity identity;
  final LocalCxpServer server;
  final CxpManifestWriter _writer;
  final CxpDiscovery _discovery;
  final CxpPeerConnector _connector;

  Future<void> stop() async {
    await _connector.dispose();
    await _discovery.stop();
    await _writer.remove();
    await server.stop();
  }
}

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
