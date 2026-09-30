// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/policy/org_server_policy.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';

part 'cxp_server_provider.g.dart';

/// Maximum number of cross-probe events the rolling buffer retains for
/// display in the cross-probe panel.
const int kCxpEventLogMaxEntries = 50;

/// Resolves the suite-shared manifest directory for CXP peer discovery
/// via `sharedCxpManifestDirectory()` (crux_cxp). Override in tests to
/// redirect the manifest writer and discovery service to a temp
/// directory.
///
/// This MUST be the bundle-independent shared location — the previous
/// `getApplicationSupportDirectory()/crux/cxp/peers` resolution put the
/// manifest inside WaveCrux's own app container, which no other suite
/// product ever scanned, so cross-product discovery ("No CXP peers
/// connected" everywhere) was structurally impossible: every product
/// wrote and watched a different directory. Kept async for
/// override-compatibility even though the shared resolver is synchronous.
@Riverpod(keepAlive: true)
Future<String> cxpManifestDirectory(Ref ref) async =>
    sharedCxpManifestDirectory();

/// Snapshot of [WaveCruxCxpServer] runtime state surfaced to the UI.
@immutable
class CxpServerState {
  /// Creates a [CxpServerState].
  const CxpServerState({
    this.isRunning = false,
    this.port = 54322,
    this.connectedPeerCount = 0,
    this.lastError,
  });

  /// True iff the server is currently bound to a TCP port.
  final bool isRunning;

  /// Currently bound port (or the configured port when stopped).
  final int port;

  /// Number of peers currently connected over a CXP socket.
  final int connectedPeerCount;

  /// Last lifecycle error string, or null if none.
  final String? lastError;

  /// Returns a copy with overridden fields.
  CxpServerState copyWith({
    bool? isRunning,
    int? port,
    int? connectedPeerCount,
    String? lastError,
    bool clearLastError = false,
  }) => CxpServerState(
    isRunning: isRunning ?? this.isRunning,
    port: port ?? this.port,
    connectedPeerCount: connectedPeerCount ?? this.connectedPeerCount,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpServerState &&
          other.isRunning == isRunning &&
          other.port == port &&
          other.connectedPeerCount == connectedPeerCount &&
          other.lastError == lastError);

  @override
  int get hashCode =>
      Object.hash(isRunning, port, connectedPeerCount, lastError);

  @override
  String toString() =>
      'CxpServerState(isRunning: $isRunning, port: $port, '
      'peers: $connectedPeerCount, lastError: $lastError)';
}

/// Riverpod-owned lifecycle for the WaveCrux CXP peer cross-probe server.
///
/// Mirrors the existing `RemoteControlNotifier` (WCP) pattern: holds the
/// underlying [WaveCruxCxpServer] instance, exposes a [CxpServerState]
/// for UI consumption, and bridges inbound message dispatch to
/// [dispatchCxpHighlight] / [dispatchCxpOpenSource] which reuse the
/// existing WCP internal code paths — one implementation, two front doors.
@Riverpod(keepAlive: true)
class CxpServerNotifier extends _$CxpServerNotifier {
  WaveCruxCxpServer? _server;
  StreamSubscription<WaveCruxCxpServerEvent>? _serverEventSub;
  StreamSubscription<CxpDialFailure>? _dialFailureSub;

  @override
  CxpServerState build() {
    ref.onDispose(() async {
      await _serverEventSub?.cancel();
      _serverEventSub = null;
      await _dialFailureSub?.cancel();
      _dialFailureSub = null;
      await _server?.dispose();
      _server = null;
    });
    return const CxpServerState();
  }

  /// Currently-running underlying server, or null when stopped. Exposed
  /// so the selection-emitter (Part E) can call
  /// [WaveCruxCxpServer.broadcast] directly without going through state.
  WaveCruxCxpServer? get server => _server;

  /// Starts the CXP server on [port]. Returns `null` on success, an
  /// error string otherwise. If the server is already running, stops
  /// it first.
  Future<String?> startServer(int port) async {
    // A browser can neither bind a socket nor publish into the shared manifest
    // directory, which `sharedCxpManifestDirectory()` reports as unavailable
    // there. The launch bridge is not started on the web; this answers any
    // other caller with the not-available error before it resolves the
    // manifest directory at all.
    if (kIsWeb) return 'CXP is not available in the browser';
    if (state.isRunning) await stopServer();

    final manifestDir = await ref.read(cxpManifestDirectoryProvider.future);
    final buildInfo = await ref.read(applicationBuildInfoProvider.future);

    final server = WaveCruxCxpServer(
      productVersion: buildInfo.version,
      manifestDirectory: manifestDir,
      port: port,
      onHighlight: (element, metadata, coordinate) =>
          dispatchCxpHighlight(ref, element, metadata, coordinate),
      onOpenSource: (path, line, column) =>
          dispatchCxpOpenSource(ref, path, line, column),
      onSelection: (elements, metadata) =>
          handleInboundSelection(ref, elements, metadata),
      onOpenArtifact: (designId, kind, path) =>
          dispatchCxpOpenArtifact(ref, designId, kind, path),
      // The floor, not the directories the user has opened. `LocalCxpServer`
      // holds one rule for both requests it screens, and a rooted one strips
      // the path hint from a `request_open_artifact` for a waveform WaveCrux
      // has never opened — the very request that route exists to honour. A
      // `request_open_source` keeps its roots: `dispatchCxpOpenSource`
      // applies the rooted rule to the path it is about to hand an editor.
      // Named although it is the server's default, so the decision is
      // visible where the server is built.
      // ignore: avoid_redundant_argument_values
      containment: kCxpOpenArtifactContainment,
    );
    final error = await server.start();
    if (error != null) {
      state = state.copyWith(lastError: error);
      return error;
    }
    _server = server;
    _serverEventSub = server.serverEvents.listen(_onServerEvent);
    _dialFailureSub = server.dialFailures.listen((_) => _refreshDialFailures());
    state = CxpServerState(
      isRunning: true,
      port: server.boundPort ?? port,
    );
    return null;
  }

  /// Stops the CXP server, removes its manifest, and clears state.
  Future<void> stopServer() async {
    await _serverEventSub?.cancel();
    _serverEventSub = null;
    await _dialFailureSub?.cancel();
    _dialFailureSub = null;
    await _server?.dispose();
    _server = null;
    ref.read(cxpDialFailuresProvider.notifier).clear();
    state = state.copyWith(
      isRunning: false,
      connectedPeerCount: 0,
      clearLastError: true,
    );
  }

  /// Pushes the server's current unreachable-peer snapshot into
  /// [cxpDialFailuresProvider]. Driven by the dial-failure stream (a new
  /// failure) and by presence changes (a peer that just connected clears
  /// its recorded failure) — the two together bound how stale the
  /// indicator can be without a polling timer.
  void _refreshDialFailures() {
    ref
        .read(cxpDialFailuresProvider.notifier)
        .set(_server?.unreachablePeers ?? const <CxpDialFailure>[]);
  }

  void _onServerEvent(WaveCruxCxpServerEvent event) {
    if (event.isPresence) {
      state = state.copyWith(
        connectedPeerCount: _server?.connectedPeers.length ?? 0,
      );
      // A peer that just connected may have cleared a prior dial failure;
      // re-sync so a recovered peer drops out of the unreachable list.
      _refreshDialFailures();
    }
    ref
        .read(cxpEventLogProvider.notifier)
        .append(
          CxpEventLogEntry(
            timestamp: DateTime.now(),
            direction: event.isOutbound
                ? CxpEventDirection.outbound
                : CxpEventDirection.inbound,
            messageKind: event.kind,
            peerLabel: event.peerLabel,
            summary: event.summary,
          ),
        );
  }
}

/// Snapshot of currently-known peers as a sorted list, computed from
/// the [WaveCruxCxpServer.discoveredPeers] + live socket peers union.
/// Watched by the cross-probe panel.
@Riverpod(keepAlive: true)
class CxpPeers extends _$CxpPeers {
  @override
  List<PeerIdentity> build() {
    final running = ref.watch(
      cxpServerProvider.select((s) => s.isRunning),
    );
    if (!running) return const <PeerIdentity>[];
    final notifier = ref.read(cxpServerProvider.notifier);
    final server = notifier.server;
    if (server == null) return const <PeerIdentity>[];
    // Rebuild on connect/disconnect so the panel reflects live churn.
    ref.watch(
      cxpServerProvider.select((s) => s.connectedPeerCount),
    );
    final connected = server.connectedPeers;
    // Unify discovered (manifest) + connected (Hello-handshake) peers by
    // peerId so a peer that appears in both lists is counted once.
    final byPeerId = <String, PeerIdentity>{
      for (final m in server.discoveredPeers) m.identity.peerId: m.identity,
    };
    for (final peer in connected) {
      byPeerId[peer.peerId] = peer;
    }
    final list = byPeerId.values.toList()
      ..sort((a, b) => a.peerId.compareTo(b.peerId));
    return List<PeerIdentity>.unmodifiable(list);
  }
}

/// Peers WaveCrux has dialed but cannot currently reach — the connector's
/// most-recent outbound-dial failure per peer. Watched by the cross-probe
/// panel to render a persistent "Couldn't reach `<peer>`" indicator.
///
/// A peer can be in this list AND in [CxpPeers] at once: that is exactly
/// one-way connectivity — the peer's connector reached us (so its Hello
/// populated our `connectedPeers`) while our own outbound dial to it keeps
/// failing. Surfacing it is the whole point; the failure would otherwise
/// be invisible. Fed by [CxpServerNotifier], which recomputes the snapshot
/// on each dial failure and on peer-presence changes.
@Riverpod(keepAlive: true)
class CxpDialFailures extends _$CxpDialFailures {
  @override
  List<CxpDialFailure> build() => const <CxpDialFailure>[];

  /// Replace the snapshot with the server's current unreachable-peer set.
  void set(List<CxpDialFailure> failures) {
    state = List<CxpDialFailure>.unmodifiable(failures);
  }

  /// Empties the snapshot. Called when the server stops.
  void clear() {
    state = const <CxpDialFailure>[];
  }
}

/// Rolling buffer of recent cross-probe events. Capped at
/// [kCxpEventLogMaxEntries] (~50) so the cross-probe panel does not grow
/// unbounded. New entries are appended; once the buffer is full the
/// oldest entry is dropped.
@Riverpod(keepAlive: true)
class CxpEventLog extends _$CxpEventLog {
  @override
  List<CxpEventLogEntry> build() => const <CxpEventLogEntry>[];

  /// Append [entry] to the rolling buffer, evicting the oldest entry when
  /// the buffer is full.
  void append(CxpEventLogEntry entry) {
    final next = <CxpEventLogEntry>[...state, entry];
    if (next.length > kCxpEventLogMaxEntries) {
      next.removeRange(0, next.length - kCxpEventLogMaxEntries);
    }
    state = List<CxpEventLogEntry>.unmodifiable(next);
  }

  /// Empties the event log. Used by the cross-probe panel's clear button.
  void clear() {
    state = const <CxpEventLogEntry>[];
  }
}

// ── Selection emitter ─────────────────────────────────────────────────────────

/// Bridges WaveCrux's per-tab selection providers (signal, cursor,
/// markers) to outbound CXP `notify_selection` broadcasts. Rebuilds
/// whenever the underlying server starts or stops so the emitter is
/// always bound to the live server instance (and never broadcasts when
/// the server is stopped).
@Riverpod(keepAlive: true)
CxpSelectionEmitter? cxpSelectionEmitter(Ref ref) {
  final running = ref.watch(
    cxpServerProvider.select((s) => s.isRunning),
  );
  if (!running) return null;
  final notifier = ref.read(cxpServerProvider.notifier);
  final server = notifier.server;
  if (server == null) return null;
  final emitter = CxpSelectionEmitter(ref: ref, sink: server.broadcast)
    ..start();
  ref.onDispose(emitter.dispose);
  return emitter;
}

// ── App-lifecycle bridge ──────────────────────────────────────────────────────

/// Mirrors `AppSettings.cxpServerEnabled` into the CXP server lifecycle.
///
/// Starts the server on launch when the setting is true and reacts to
/// settings changes (toggle off → stop; toggle on → start; port change →
/// restart). Hosted as a `keepAlive: true` provider so the bridge stays
/// active for the lifetime of the app; consumers `ref.read` it once at
/// bootstrap to instantiate the listener.
@Riverpod(keepAlive: true)
CxpLifecycleBridge cxpLifecycleBridge(Ref ref) {
  return CxpLifecycleBridge(ref)..start();
}

/// Tracks [AppSettings.cxpServerEnabled] + [AppSettings.cxpServerPort]
/// and drives [CxpServerNotifier.startServer] / [stopServer] accordingly.
class CxpLifecycleBridge {
  /// Creates a bridge bound to [ref]. Call [start] to begin listening.
  CxpLifecycleBridge(this._ref);

  final Ref _ref;
  ProviderSubscription<AsyncValue<AppSettings>>? _settingsSub;
  bool _started = false;

  /// Begin listening for settings changes. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _settingsSub = _ref.listen<AsyncValue<AppSettings>>(
      appSettingsProvider,
      _onSettings,
      fireImmediately: true,
    );
    _ref.onDispose(() {
      _settingsSub?.close();
      _settingsSub = null;
    });
  }

  bool _previouslyEnabled = false;
  int _previousPort = -1;
  bool? _previousAttention;

  void _onSettings(
    AsyncValue<AppSettings>? previous,
    AsyncValue<AppSettings> next,
  ) {
    final settings = next.value;
    if (settings == null) return;

    // Attention gate. Swap the global attention requester to the no-op
    // backend when "request attention on cross-probe" is off, and back to the
    // method-channel backend when on. Handled before the server-enable early
    // return below so a change to *only* this setting still takes effect.
    final attention = settings.requestAttentionOnCrossProbe;
    if (attention != _previousAttention) {
      _previousAttention = attention;
      windowAttentionRequester = attention
          ? const MethodChannelWindowAttentionRequester()
          : const NoopWindowAttentionRequester();
    }

    // The ORG's answer, not just the engineer's — see the WCP bridge.
    final enabled = resolveCxpServerPolicy(
      _ref.read(cruxPolicyProvider).document,
      userSetting: settings.cxpServerEnabled,
    ).value;
    final port = settings.cxpServerPort;
    if (enabled == _previouslyEnabled && port == _previousPort) return;
    _previouslyEnabled = enabled;
    _previousPort = port;
    final notifier = _ref.read(cxpServerProvider.notifier);
    if (enabled) {
      unawaited(notifier.startServer(port));
    } else {
      unawaited(notifier.stopServer());
    }
  }
}
