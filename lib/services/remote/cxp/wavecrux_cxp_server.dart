// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_name_resolver.dart';

/// Application-layer wrapper around `package:crux_cxp`'s [LocalCxpServer].
///
/// Owns the CXP server lifecycle for one WaveCrux process: TCP socket,
/// peer identity, manifest writer, discovery service, and the wiring of
/// inbound messages into product-specific handlers. The Riverpod
/// `CxpServerNotifier` holds one of these and starts/stops it in response
/// to settings changes and app-lifecycle events.
///
/// The wrapper intentionally does *not* depend on Riverpod or Flutter so
/// it can be exercised under `dart:test` against a real `LocalCxpClient`
/// without standing up a `ProviderContainer`. Inbound message dispatch
/// is delegated to caller-supplied callbacks (`onHighlight`,
/// `onOpenSource`) which the provider layer wires up to
/// `RemoteControlNotifier`'s existing internal handlers — one
/// implementation, two front doors.
class WaveCruxCxpServer {
  /// Creates the server. `host` defaults to localhost; `port` of `0` lets
  /// the OS pick a free port (visible via [boundPort] after [start]
  /// resolves). The [manifestDirectory] should be the per-OS conventional
  /// location (`{appSupportDir}/crux/cxp/peers/`); the manifest writer
  /// creates the directory if necessary.
  WaveCruxCxpServer({
    required this.productVersion,
    required this.manifestDirectory,
    required this.onHighlight,
    required this.onOpenSource,
    this.onSelection,
    this.onOpenArtifact,
    this.host = '127.0.0.1',
    this.port = 54322,
    this.discoveryScanInterval = const Duration(seconds: 2),
    this.containment = const CxpPathContainment(),
    int? processId,
    int? startedAtMillis,
    NameResolver? nameResolver,
  }) : _processId = processId ?? pid,
       _startedAtMillis =
           startedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
       _nameResolver = nameResolver ?? const WaveCruxNameResolver();

  /// Product short name announced in the [PeerIdentity].
  static const String productName = 'wavecrux';

  /// WaveCrux's product version (from `applicationBuildInfoProvider`).
  final String productVersion;

  /// Directory the manifest writer publishes the peer's manifest into.
  final String manifestDirectory;

  /// Bind host. Localhost by default — CXP is a local-only protocol.
  final String host;

  /// Requested bind port (`0` = OS-assigned).
  final int port;

  /// How often [CxpDiscovery] rescans [manifestDirectory] for peer
  /// manifests. Production default matches [CxpDiscovery]'s own default
  /// (2 seconds); tests override it to a much shorter interval so
  /// discovery-driven assertions don't have to wait out a real 2-second
  /// tick.
  final Duration discoveryScanInterval;

  /// The receiver-side rule (CXP §11) [LocalCxpServer] screens a
  /// `request_open_source`'s `file_path` and a `request_open_artifact`'s
  /// hint against before either reaches a handler.
  ///
  /// The shared layer can only check the value that arrived on the wire; the
  /// value WaveCrux is *about to open* — after the workspace store resolved
  /// an artifact, or after a settings-configured editor command is
  /// assembled — is checked in the handlers, under the rule that route
  /// keeps. The default is the floor (absolute, well-formed), and the
  /// provider layer passes the floor too: one rule screens both requests
  /// here, and the artifact request's hint must not be rooted in the
  /// directories the user has opened (`kCxpOpenArtifactContainment`).
  final CxpPathContainment containment;

  /// Handler invoked when a peer sends `request_highlight`. The receiver
  /// is expected to perform the highlight action and return whether it
  /// was honored, optionally with a human-readable reason on failure.
  ///
  /// The message's product-local [metadata] is passed through so the handler
  /// can read the `crux.design_id` hint and open the design's waveform
  /// when the referenced element is not in any already-open waveform.
  ///
  /// The optional CXP §9.9 (https://edacrux.app/cxp#sec-9-9) semantic stream
  /// [CxpStreamCoordinate] is passed
  /// through too. `element` says *what to open*; the coordinate says *where
  /// to land inside it* — which retirement, transaction or frame. It is
  /// nullable and open-vocabulary: a handler that cannot resolve it must
  /// still honour the element (CXP §9.4) and say why in the reason.
  final Future<CxpHandlerResult> Function(
    ElementId element,
    Map<String, Object?> metadata,
    CxpStreamCoordinate? coordinate,
  )
  onHighlight;

  /// Handler invoked when a peer sends `request_open_source`.
  final Future<CxpHandlerResult> Function(
    String filePath,
    int line,
    int? column,
  )
  onOpenSource;

  /// Handler invoked when a peer sends `request_open_artifact`. Receives
  /// the shared [designId], the requested [artifactKind] (e.g. `waveform`), and
  /// an optional sender [path] hint. Expected to resolve the concrete file
  /// through the shared workspace, open it, and report whether it was honored.
  /// Optional; a null handler acks honored=false.
  final Future<CxpHandlerResult> Function(
    String designId,
    String artifactKind,
    String? path,
  )?
  onOpenArtifact;

  /// Handler invoked when a peer sends `notify_selection`. Receives both the
  /// selected [ElementId]s and the message's product-local [metadata] map so
  /// the receiver can stash the suggestion for a subsequent action — e.g. the
  /// "Debug in WaveCrux" handoff, which arrives immediately before the
  /// `request_highlight(source)` that opens the waveform and carries the
  /// signals-to-show glob(s) in `metadata` (not `elements`). Optional; a null
  /// handler means selection notifications trigger no automatic action beyond
  /// the cross-probe event-log entry.
  final void Function(
    List<ElementId> elements,
    Map<String, Object?> metadata,
  )?
  onSelection;

  final int _processId;
  final int _startedAtMillis;
  final NameResolver _nameResolver;

  LocalCxpServer? _server;
  CxpManifestWriter? _manifestWriter;
  CxpDiscovery? _discovery;
  CxpPeerConnector? _connector;
  StreamSubscription<InboundCxpMessage>? _inboundSub;
  StreamSubscription<CxpDialFailure>? _dialFailureSub;

  final StreamController<CxpDiscoveryEvent> _discoveryEvents =
      StreamController<CxpDiscoveryEvent>.broadcast();
  final StreamController<WaveCruxCxpServerEvent> _serverEvents =
      StreamController<WaveCruxCxpServerEvent>.broadcast();
  final StreamController<CxpDialFailure> _dialFailures =
      StreamController<CxpDialFailure>.broadcast();

  /// Per-process [PeerIdentity] embedded into outbound Hellos and the
  /// manifest file. The peer ID is `wavecrux-<pid>-<startedAtMillis>` per
  /// the [PeerIdentity] convention.
  PeerIdentity get selfIdentity => PeerIdentity(
    peerId: 'wavecrux-$_processId-$_startedAtMillis',
    productName: productName,
    productVersion: productVersion,
    capabilities: const {
      'wavecrux.signal_value',
      'wavecrux.cursor_time_fs',
    },
  );

  /// True once [start] has resolved successfully and the server is
  /// accepting connections. Goes back to `false` after [stop].
  bool get isRunning => _server != null;

  /// Effective bound port after [start]. Null before start or after stop.
  int? get boundPort => _server?.boundPort;

  /// Snapshot of currently connected peers (CXP servers that have
  /// completed the Hello handshake with us).
  List<PeerIdentity> get connectedPeers =>
      _server?.connectedPeers ?? const <PeerIdentity>[];

  /// Stream of peer-presence + inbound-message events emitted as the
  /// CXP server runs. The provider layer consumes this stream to feed
  /// the cross-probe panel's rolling event buffer.
  Stream<WaveCruxCxpServerEvent> get serverEvents => _serverEvents.stream;

  /// Stream of peer-discovery events emitted by [CxpDiscovery] as peer
  /// manifests appear and disappear in [manifestDirectory].
  Stream<CxpDiscoveryEvent> get discoveryEvents => _discoveryEvents.stream;

  /// Stream of outbound dial failures re-broadcast from the internal
  /// [CxpPeerConnector], one event per failed connection attempt.
  ///
  /// A dial failure means we discovered a peer's manifest but could not
  /// open a CXP socket to it — one-way connectivity that is otherwise
  /// invisible (the peer can still appear "connected" if it dialed us).
  /// The provider layer consumes this to keep the cross-probe panel's
  /// unreachable-peer indicator current.
  Stream<CxpDialFailure> get dialFailures => _dialFailures.stream;

  /// Snapshot of peers we have dialed but cannot currently reach — the
  /// connector's most-recent failure per peer, for peers that are not
  /// connected over our outbound link. An entry clears when the peer's
  /// handshake finally succeeds or its manifest is removed. Empty when
  /// the server is stopped or every discovered peer is reachable.
  List<CxpDialFailure> get unreachablePeers =>
      List<CxpDialFailure>.unmodifiable(
        _connector?.lastDialFailures.values ?? const <CxpDialFailure>[],
      );

  /// Snapshot of currently known peers (across the manifest watcher and
  /// the live socket peers). Discovered peers may or may not have an
  /// open socket to us.
  ///
  /// Excludes our own manifest: the manifest directory is suite-shared
  /// (`sharedCxpManifestDirectory()`), so the raw scan always contains
  /// the manifest this server wrote for itself.
  List<CxpPeerManifest> get discoveredPeers => [
    for (final m in _discovery?.peers ?? const <CxpPeerManifest>[])
      if (m.identity.peerId != selfIdentity.peerId) m,
  ];

  /// Start the server, write the manifest, and begin discovery.
  ///
  /// Returns `null` on success; an error string on failure (port in use,
  /// permission denied, …). Failures leave the server in a stopped state
  /// — call [start] again with a different port to retry.
  Future<String?> start() async {
    if (_server != null) return null;
    try {
      final server = LocalCxpServer(
        selfIdentity: selfIdentity,
        host: host,
        port: port,
        nameResolver: _nameResolver,
        containment: containment,
      );
      await server.start();
      _server = server;
      _inboundSub = server.inbound.listen(_handleInbound);

      // Re-broadcast presence + inbound onto our combined event stream so
      // the provider layer only listens to one Stream.
      unawaited(
        server.presence.forEach((event) {
          if (_serverEvents.isClosed) return;
          _serverEvents.add(
            WaveCruxCxpServerEvent.presence(event),
          );
        }),
      );

      // Manifest + discovery.
      _manifestWriter = CxpManifestWriter(manifestDirectory: manifestDirectory);
      await _manifestWriter!.write(
        identity: selfIdentity,
        host: host,
        port: server.boundPort ?? port,
      );
      _discovery = CxpDiscovery(
        manifestDirectory: manifestDirectory,
        scanInterval: discoveryScanInterval,
      );
      unawaited(
        _discovery!.events.forEach((event) {
          if (event.manifest.identity.peerId == selfIdentity.peerId) {
            // Ignore self-discovery — we already know about ourselves.
            return;
          }
          if (_discoveryEvents.isClosed) return;
          _discoveryEvents.add(event);
        }),
      );
      await _discovery!.start();
      // Dial every discovered peer so BOTH sides' servers see a live
      // connection (the connector skips our own manifest). Discovery alone
      // only proves a manifest file exists; without an active dialer
      // nothing ever opens a CXP socket, so every product's
      // `connectedPeers` stays empty forever regardless of how many peers
      // discovery finds. Symmetric: the peer's connector dials us back,
      // which is what populates OUR [connectedPeers] via its inbound
      // Hello.
      //
      // `server: server` is required, not optional: with two symmetric
      // dialers, a message we send via `server.sendTo`/`broadcast` always
      // travels over the socket the OTHER side's connector dialed, so the
      // receiving side only ever sees it arrive on its *connector's*
      // client link, never on its own accept loop. Without this wire-up
      // `CxpPeerConnector` degrades to presence-only dialing: sockets
      // connect (`connectedPeers` looks fine) but every request, ack, and
      // notify_selection gossip arriving over a connector-dialed link is
      // silently dropped before it ever reaches [_handleInbound]. See
      // `CxpPeerConnector`'s class doc ("the connector<->server seam") and
      // the crux_cxp e2e conformance suite this mirrors
      // (peer_connectivity_test.dart's "end-to-end product traffic" case).
      final connector = CxpPeerConnector(
        selfIdentity: selfIdentity,
        discovery: _discovery!,
        server: server,
      );
      // Subscribe before start() so the very first dial's failure — the
      // connector dials on discovery's seed/add events — is re-broadcast,
      // not lost to the broadcast stream's no-late-listener semantics.
      _dialFailureSub = connector.dialFailures.listen((failure) {
        if (!_dialFailures.isClosed) _dialFailures.add(failure);
      });
      _connector = connector..start();
      return null;
    } on Object catch (e) {
      // Clean up any partial state.
      await stop();
      return e.toString();
    }
  }

  /// Stop the server, remove the manifest, and tear down discovery.
  /// Idempotent — calling twice is a no-op the second time.
  Future<void> stop() async {
    await _inboundSub?.cancel();
    _inboundSub = null;
    await _dialFailureSub?.cancel();
    _dialFailureSub = null;
    final connector = _connector;
    _connector = null;
    if (connector != null) {
      await connector.stop();
    }
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      await discovery.stop();
    }
    final manifestWriter = _manifestWriter;
    _manifestWriter = null;
    if (manifestWriter != null) {
      await manifestWriter.remove();
    }
    final server = _server;
    _server = null;
    if (server != null) {
      // Send Goodbye to every connected peer before closing the sockets.
      try {
        server.broadcast(const Goodbye(reason: 'server_stopping'));
      } on Object {
        // Best effort.
      }
      await server.stop();
    }
  }

  /// Broadcast [message] to every subscribed peer. Records the broadcast
  /// in the [serverEvents] stream for the cross-probe panel.
  void broadcast(CxpMessage message, {String? summary}) {
    final server = _server;
    if (server == null) return;
    server.broadcast(message);
    if (!_serverEvents.isClosed) {
      _serverEvents.add(
        WaveCruxCxpServerEvent.outbound(
          kind: message.kind,
          peerLabel: '(broadcast)',
          summary: summary,
        ),
      );
    }
  }

  /// Send [message] to the peer with [peerId]. Returns `true` if the
  /// peer was connected, otherwise `false`.
  bool sendTo(String peerId, CxpMessage message, {String? summary}) {
    final server = _server;
    if (server == null) return false;
    final delivered = server.sendTo(peerId, message);
    if (delivered && !_serverEvents.isClosed) {
      _serverEvents.add(
        WaveCruxCxpServerEvent.outbound(
          kind: message.kind,
          peerLabel: peerId,
          summary: summary,
        ),
      );
    }
    return delivered;
  }

  /// Sends [request] to [peerId] and waits for the peer's
  /// [RequestHighlightAck], so the cross-probe panel can surface a rejected
  /// send. Returns `(delivered: false, ack: null)` when the peer is
  /// unreachable, and `(delivered: true, ack: null)` when the send left but no
  /// ack arrived within [timeout]. Correlates by "the next RequestHighlightAck
  /// from [peerId]", which is unambiguous because such an ack is only ever a
  /// reply to a request_highlight and directed panel sends are the sole source.
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request, {
    Duration timeout = const Duration(seconds: 5),
    String? summary,
  }) async {
    final server = _server;
    if (server == null) return (delivered: false, ack: null);
    final completer = Completer<RequestHighlightAck>();
    final sub = server.inbound.listen((inbound) {
      if (inbound.from.peerId == peerId &&
          inbound.message is RequestHighlightAck &&
          !completer.isCompleted) {
        completer.complete(inbound.message as RequestHighlightAck);
      }
    });
    final delivered = sendTo(peerId, request, summary: summary);
    if (!delivered) {
      await sub.cancel();
      return (delivered: false, ack: null);
    }
    RequestHighlightAck? ack;
    try {
      ack = await completer.future.timeout(timeout);
    } on TimeoutException {
      ack = null;
    } finally {
      await sub.cancel();
    }
    return (delivered: true, ack: ack);
  }

  /// Release the event-stream controllers. After [dispose] the server
  /// must not be restarted; create a new instance instead.
  Future<void> dispose() async {
    await stop();
    if (!_serverEvents.isClosed) await _serverEvents.close();
    if (!_discoveryEvents.isClosed) await _discoveryEvents.close();
    if (!_dialFailures.isClosed) await _dialFailures.close();
  }

  // ── inbound dispatch ────────────────────────────────────────────────────────

  Future<void> _handleInbound(InboundCxpMessage inbound) async {
    final message = inbound.message;
    final fromPeer = inbound.from.productName.isEmpty
        ? inbound.from.peerId
        : inbound.from.productName;

    if (!_serverEvents.isClosed) {
      _serverEvents.add(
        WaveCruxCxpServerEvent.inbound(
          kind: message.kind,
          peerLabel: fromPeer,
          summary: _summarize(message),
        ),
      );
    }

    if (message is RequestHighlight) {
      final result = await _safeInvoke(
        () => onHighlight(
          message.element,
          message.metadata,
          message.coordinate,
        ),
      );
      sendTo(
        inbound.from.peerId,
        RequestHighlightAck(
          inReplyTo: inbound.envelope.messageId,
          honored: result.honored,
          reason: result.reason,
        ),
      );
    } else if (message is RequestOpenArtifact) {
      final handler = onOpenArtifact;
      final result = handler == null
          ? const CxpHandlerResult(
              honored: false,
              reason: 'open-artifact not supported',
            )
          : await _safeInvoke(
              () => handler(
                message.designId,
                message.artifactKind,
                message.path,
              ),
            );
      sendTo(
        inbound.from.peerId,
        RequestOpenArtifactAck(
          inReplyTo: inbound.envelope.messageId,
          honored: result.honored,
          reason: result.reason,
        ),
      );
    } else if (message is RequestOpenSource) {
      final result = await _safeInvoke(
        () => onOpenSource(message.filePath, message.line, message.column),
      );
      sendTo(
        inbound.from.peerId,
        RequestOpenSourceAck(
          inReplyTo: inbound.envelope.messageId,
          honored: result.honored,
          reason: result.reason,
        ),
      );
    } else if (message is NotifySelection) {
      // No ack in the protocol — hand the selection (elements + product-local
      // metadata) to the optional handler so it can be stashed for a
      // following source-open handoff. The handoff's signal globs travel in
      // metadata, not elements.
      onSelection?.call(message.elements, message.metadata);
    }
    // Other inbound messages flow through to subscribers (e.g. the
    // cross-probe panel's event log) but require no automatic action.
  }

  Future<CxpHandlerResult> _safeInvoke(
    Future<CxpHandlerResult> Function() body,
  ) async {
    try {
      return await body();
    } on Object catch (e) {
      return CxpHandlerResult(honored: false, reason: e.toString());
    }
  }

  String? _summarize(CxpMessage message) {
    if (message is NotifySelection && message.elements.isNotEmpty) {
      return message.displayName ?? message.elements.first.path;
    }
    if (message is RequestHighlight) {
      return message.element.path;
    }
    if (message is RequestOpenSource) {
      return '${message.filePath}:${message.line}';
    }
    if (message is RequestOpenArtifact) {
      return '${message.designId} · ${message.artifactKind}';
    }
    return null;
  }
}

/// Result of an inbound CXP handler invocation.
///
/// Maps directly onto the `honored` / `reason` fields of
/// [RequestHighlightAck] and [RequestOpenSourceAck].
@immutable
class CxpHandlerResult {
  /// Creates a result.
  const CxpHandlerResult({required this.honored, this.reason});

  /// Convenience for an honoured request with no reason.
  static const honoredOk = CxpHandlerResult(honored: true);

  /// Whether the request was satisfied.
  final bool honored;

  /// Optional human-readable reason — typically populated when
  /// [honored] is false.
  final String? reason;
}

/// Compact union over the two kinds of internal events the
/// [WaveCruxCxpServer] surfaces on its [WaveCruxCxpServer.serverEvents]
/// stream.
///
/// One of three flavours per the named constructor:
///
/// * [WaveCruxCxpServerEvent.presence] — a peer connected or disconnected.
/// * [WaveCruxCxpServerEvent.inbound] — a peer sent us a message.
/// * [WaveCruxCxpServerEvent.outbound] — we sent a message (broadcast or
///   targeted via `sendTo`).
@immutable
class WaveCruxCxpServerEvent {
  /// Records a peer-presence change (connected / disconnected).
  WaveCruxCxpServerEvent.presence(PeerPresenceEvent event)
    : kind = event.connected ? 'peer_connected' : 'peer_disconnected',
      peerLabel = event.peer.productName.isEmpty
          ? event.peer.peerId
          : event.peer.productName,
      summary = null,
      isOutbound = false,
      presence = event;

  /// Records an inbound message we received from a peer.
  const WaveCruxCxpServerEvent.inbound({
    required this.kind,
    required this.peerLabel,
    this.summary,
  }) : isOutbound = false,
       presence = null;

  /// Records an outbound message we sent.
  const WaveCruxCxpServerEvent.outbound({
    required this.kind,
    required this.peerLabel,
    this.summary,
  }) : isOutbound = true,
       presence = null;

  /// Wire-format kind discriminator OR pseudo-kind for presence events
  /// (`peer_connected` / `peer_disconnected`).
  final String kind;

  /// Peer label (productName fallback to peerId) for display.
  final String peerLabel;

  /// Optional one-line summary the panel can show next to the kind.
  final String? summary;

  /// Whether the event is an outbound message we sent.
  final bool isOutbound;

  /// Underlying presence event when this entry was produced by
  /// [WaveCruxCxpServerEvent.presence]; null otherwise.
  final PeerPresenceEvent? presence;

  /// Whether this entry records a presence change.
  bool get isPresence => presence != null;
}
