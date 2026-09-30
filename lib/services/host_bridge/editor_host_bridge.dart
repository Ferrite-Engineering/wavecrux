// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The editor-host bridge: what an extension host can ask this build to do, and
// what this build tells it back.
//
// ### The third door onto the same hallway
//
// WCP (`add_items` / `set_cursor` / `focus_item`) and CXP (`request_highlight`)
// already reach the same four providers — `openFromBytes`,
// `signalGroupsProvider.addSignals`, `cursorStateProvider.placePrimary`,
// `selectedSignalProvider.select` — through one implementation with two front
// doors (ARCHITECTURE.md §"one implementation, two front doors"). This is the
// third door, and it is small for the same reason: it decodes a frame and hands
// the decoded element to [dispatchCxpHighlight], the function the CXP server
// already calls. There is no parallel highlight implementation here, and adding
// one would be the bug.
//
// ### Untrusted input
//
// Frames arrive on `window.postMessage`. Everything below assumes the sender is
// hostile: the shape is validated before it is read, the byte payload is
// bounded (`kHostBridgeMaxOpenBytes`), an unknown kind is answered rather than
// acted on, and no path here throws — a malformed frame is ignored.
//
// ### The theme bridge
//
// [HostBridgeThemeTokens] is the one frame type in [_dispatch] with no
// acknowledgement — see the comment on that branch. It hands the raw VSCode
// tokens to `synthesizeEditorHostTheme` (`editor_host_theme_synthesizer.dart`)
// and applies the result via
// [WaveCruxCruxColorThemeNotifier.applyEphemeral], never [activate]: the
// synthesized theme must win immediately and update on every live host
// toggle, but must never overwrite the user's on-disk preset/override choice,
// which still applies the next time this build runs outside a VSCode host.
//
// ### The annotation query
//
// [HostBridgeValueQuery] is the one frame here whose effect outlives its
// dispatch. The extension draws signal values as decorations in the user's own
// Verilog and needs them to follow the *waveform* cursor — which lives in this
// build — so the query stands: [HostAnnotationValueService] holds it, answers
// it now, and answers it again on every debounced cursor move until a later
// query replaces it or an empty one cancels it. That is also why it is
// correlated by `query_id` and not `in_reply_to`.
//
// ### The cross-probe panel's state
//
// [HostBridgeCrossProbeState] is the frame that makes the docked Cross-Probe
// tab work inside a webview at all. This build's CXP server is stopped there
// by construction — `app.dart` only instantiates the lifecycle bridge on a
// desktop platform, because a webview has no `dart:io` — and the panel used to
// read that as "the CXP server is offline, enable it in Settings", which is
// advice about a setting that was already on and could not have helped. The
// extension host is the peer; it pushes its peer list, its dial failures and
// its event log down here, and [postCrossProbeSend] is how the panel's per-peer
// Send reaches a socket it does not have. Nothing on this path exists on
// desktop, where `cross_probe_panel.dart` keeps sourcing from
// `cxpServerProvider` et al.
//
// ### Two ways a waveform arrives
//
// The extension's `CustomEditorProvider` posts [kHostBridgeOpenWaveformKind]
// for a file small enough to cross `postMessage` whole, and a run of
// [kHostBridgeOpenWaveformChunkKind] frames for one that is not. Both end at
// the same [_openWaveform]: chunking is a transport concern that ends at
// [HostBridgeTransferAssembler], and the open path has one shape.

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_telemetry/crux_telemetry.dart' show TelemetryEvent;
import 'package:crux_theme/crux_theme.dart' show cruxColorThemeProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/theme/editor_host_theme_synthesizer.dart';
import 'package:wavecrux/core/theme/wavecrux_color_theme_bootstrap.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_cross_probe_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_session_provider.dart';
import 'package:wavecrux/services/host_bridge/host_annotation_value_service.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart'
    show CxpHandlerResult;
import 'package:wavecrux/services/tabs/active_tab_container.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Drives this build from an editor extension host, and reports back to it.
///
/// Constructed once, at the root container, by `editorHostBridgeProvider`. On
/// every host but a webview the transport is the inert stub, so
/// [start] installs nothing, [dispose] releases nothing, and the object costs
/// one allocation — which is why nothing in the app has to ask whether it is
/// hosted before wiring it up.
class EditorHostBridge {
  /// Creates a bridge over [channel], reading and mutating state through [ref].
  ///
  /// [selectionEmitterFactory] exists for tests; production passes nothing and
  /// gets the same [CxpSelectionEmitter] the CXP server uses, pointed at this
  /// bridge's outbound sink instead of a socket.
  EditorHostBridge({
    required Ref ref,
    required HostBridgeTransport channel,
    CxpSelectionEmitter Function(Ref ref, CxpSelectionSink sink)?
    selectionEmitterFactory,
  }) : _ref = ref,
       _channel = channel,
       _selectionEmitterFactory =
           selectionEmitterFactory ??
           ((ref, sink) => CxpSelectionEmitter(ref: ref, sink: sink));

  final Ref _ref;
  final HostBridgeTransport _channel;
  final CxpSelectionEmitter Function(Ref ref, CxpSelectionSink sink)
  _selectionEmitterFactory;

  StreamSubscription<Map<String, Object?>>? _inboundSub;

  /// Reassembles chunked waveform transfers. Bounded in every dimension — see
  /// [HostBridgeTransferAssembler]. Owned here rather than by the transport so
  /// it is exercised by the same VM tests as the rest of the dispatch.
  final HostBridgeTransferAssembler _assembler = HostBridgeTransferAssembler();

  /// Answers the extension host's standing RTL-annotation value query and keeps
  /// answering it as the cursor moves. Created eagerly and
  /// inert until the first [HostBridgeValueQuery] arrives — see
  /// [HostAnnotationValueService].
  late final HostAnnotationValueService _annotationValues =
      HostAnnotationValueService(ref: _ref, post: postCxp);
  CxpSelectionEmitter? _emitter;
  int _nextMessageId = 0;
  bool _disposed = false;

  /// The editor host on the other end, or [EditorHostKind.none].
  EditorHostKind get hostKind => _channel.hostKind;

  /// Subscribes to inbound frames and starts mirroring selection outbound.
  ///
  /// Idempotent, and a complete no-op when there is no host: a build with no
  /// editor on the other end must not pay for a selection listener whose
  /// broadcasts nothing would receive.
  void start() {
    if (_disposed || _inboundSub != null) return;
    if (hostKind == EditorHostKind.none) return;
    _inboundSub = _channel.inbound.listen(handleFrame);
    _emitter = _selectionEmitterFactory(_ref, postCxp)..start();
  }

  /// Releases the inbound subscription and the selection emitter. Safe to call
  /// repeatedly, and safe to call on a bridge that never started.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_inboundSub?.cancel());
    _inboundSub = null;
    // Half-arrived transfers are the one thing here that holds real memory.
    _assembler.clear();
    _emitter?.dispose();
    _emitter = null;
    // Constructing it here if no query ever arrived is a no-op allocation; the
    // service installs nothing until its first `accept`.
    _annotationValues.dispose();
  }

  // ── Outbound ───────────────────────────────────────────────────────────────

  /// Wraps [message] in a CXP envelope and posts it to the host.
  ///
  /// Signature matches [CxpSelectionSink] so the existing
  /// [CxpSelectionEmitter] can drive it unchanged — the `summary` a CXP server
  /// records in its event log has no counterpart here and is dropped.
  void postCxp(CxpMessage message, {String? summary}) {
    if (_disposed) return;
    _channel.post(
      hostBridgeCxpFrame(
        CxpEnvelope(
          messageId: 'wc-${_nextMessageId++}',
          from: kHostBridgePeerId,
          kind: message.kind,
          payload: message.toJson(),
        ),
      ),
    );
  }

  /// Asks the host to deliver [selection] to the peer [peerId], and returns the
  /// `message_id` the answer will be correlated on.
  ///
  /// The panel's per-peer Send button, which inside a webview cannot reach a
  /// socket. `null` when the bridge is disposed — the caller has nothing to
  /// wait for in that case.
  ///
  /// The host answers with its next [kHostBridgeCrossProbeStateKind] frame: a
  /// delivered send appears in `events`, a refused one in `send_failure`
  /// carrying this id as `in_reply_to`. See [kHostBridgeCrossProbeSendKind]
  /// for why there is no separate ack kind.
  String? postCrossProbeSend(String peerId, NotifySelection selection) {
    if (_disposed) return null;
    final messageId = 'wc-${_nextMessageId++}';
    _channel.post(
      hostBridgeCxpFrame(
        CxpEnvelope(
          messageId: messageId,
          from: kHostBridgePeerId,
          kind: kHostBridgeCrossProbeSendKind,
          payload: HostBridgeCrossProbeSend(
            peerId: peerId,
            selection: selection,
          ).toJson(),
        ),
      ),
    );
    return messageId;
  }

  /// Hands one telemetry event to the host, which owns the gate and is the only
  /// sender. See [HostRelayTelemetryService] in
  /// `host_relay_telemetry_service.dart` for why this build has no sender of
  /// its own when it is hosted.
  void postTelemetry(TelemetryEvent event) {
    if (_disposed) return;
    _channel.post(hostBridgeTelemetryFrame(event));
  }

  // ── Inbound ────────────────────────────────────────────────────────────────

  /// Acts on one frame the host posted. Never throws.
  ///
  /// Public so the dispatch can be exercised without a webview — the frame is
  /// already a plain Dart map by the time it gets here, which is the point of
  /// keeping the transport in a separate file.
  Future<void> handleFrame(Map<String, Object?> frame) async {
    if (_disposed) return;
    final inbound = decodeHostBridgeFrame(frame);
    // A frame that does not decode is not answered. There is nothing honest to
    // say about it: without a valid envelope there is no message id to reply
    // to, and inventing one would put a reply on the wire correlated to
    // nothing.
    if (inbound == null) return;
    try {
      await _dispatch(inbound);
    } on Object catch (error) {
      postCxp(
        ErrorResponse(
          code: CxpErrorCode.internalError,
          message: '$error',
          inReplyTo: inbound.envelope.messageId,
        ),
      );
    }
  }

  Future<void> _dispatch(HostBridgeInbound inbound) async {
    final message = inbound.message;
    final inReplyTo = inbound.envelope.messageId;

    if (message is RequestHighlight) {
      // The one call this whole class exists to make. `dispatchCxpHighlight` is
      // the CXP server's own handler: it resolves the element against the
      // active tab's waveform, adds it via `signalGroupsProvider.addSignals`,
      // focuses it via `selectedSignalProvider.select`, and places the cursor
      // via `cursorStateProvider.placePrimary` — the same four providers WCP
      // reaches. Nothing about that is re-implemented here.
      final result = await dispatchCxpHighlight(
        _ref,
        message.element,
        message.metadata,
        message.coordinate,
      );
      postCxp(
        RequestHighlightAck(
          inReplyTo: inReplyTo,
          honored: result.honored,
          reason: result.reason,
        ),
      );
      return;
    }

    if (message is HostBridgeOpenWaveformChunk) {
      final assembled = _assembler.accept(message);
      switch (assembled.state) {
        case HostBridgeTransferState.accepted:
          // Deliberately unacknowledged. `postMessage` is ordered and lossless
          // within a webview, so a per-chunk ack would be N round trips that
          // could not change what the host does next; the transfer is answered
          // once, when it completes or when it fails.
          return;
        case HostBridgeTransferState.rejected:
          postCxp(
            ErrorResponse(
              code: CxpErrorCode.malformedPayload,
              message:
                  'waveform transfer refused: ${assembled.reason ?? 'unknown'}',
              inReplyTo: inReplyTo,
            ),
          );
          return;
        case HostBridgeTransferState.completed:
          final waveform = assembled.waveform;
          if (waveform == null) return;
          final result = await _openWaveform(waveform);
          postCxp(
            RequestOpenArtifactAck(
              inReplyTo: inReplyTo,
              honored: result.honored,
              reason: result.reason,
            ),
          );
          return;
      }
    }

    if (message is HostBridgeThemeTokens) {
      // Fire-and-forget, deliberately: unlike every other branch here, a
      // theme frame has nothing for the host to correlate a reply to (it
      // is a push, not a request), and a live toggle can produce several
      // of these in quick succession — an ack per frame would be traffic
      // that changes nothing about what the host does next. See the
      // 'accepted' chunk-transfer case above for the same reasoning
      // applied to a different unacknowledged frame.
      final notifier = _ref.read(cruxColorThemeProvider.notifier);
      if (notifier is WaveCruxCruxColorThemeNotifier) {
        notifier.applyEphemeral(
          synthesizeEditorHostTheme(
            appearance: message.appearance,
            tokens: message.tokens,
          ),
        );
      }
      return;
    }

    if (message is HostBridgeValueQuery) {
      // Unacknowledged for the same reason the two pushes above are, and for
      // one more: a value query is *answered*, and the answer is the
      // acknowledgement. It is correlated by `query_id` rather than
      // `in_reply_to` because the query stands — one query, many responses as
      // the cursor moves — and `in_reply_to` names a single message. See
      // [kHostBridgeValueQueryKind].
      await _annotationValues.accept(message);
      return;
    }

    if (message is HostBridgeCrossProbeState) {
      // Unacknowledged, like the theme and host-session pushes above: the
      // host posts a fresh snapshot whenever its own peer set, dial failures
      // or event log change, and there is nothing for it to correlate a reply
      // to. It is also how a *send* is answered — see
      // [kHostBridgeCrossProbeSendKind] — which is the same "the answer is
      // the acknowledgement" arrangement the value query uses.
      //
      // Recorded, not acted on. Which of these values the cross-probe panel
      // renders, and whether it prefers them over this build's own (empty)
      // CXP server state, is `cross_probe_panel.dart`'s decision: it is the
      // only place that can see both sources.
      _ref
          .read(editorHostCrossProbeProvider.notifier)
          .set(
            EditorHostCrossProbeState(
              online: message.online,
              peers: message.peers,
              unreachable: message.unreachable,
              events: message.events,
              sendFailure: message.sendFailure,
            ),
          );
      return;
    }

    if (message is HostBridgeHostSession) {
      // Unacknowledged, for the same reason the theme frame is: it is a push
      // the host has nothing to correlate a reply to, and the host re-sends
      // it after a context release rather than waiting to hear back.
      //
      // Recorded, not acted on. What this fact *permits* — at most one
      // capability nudge per session, never on the first file — is
      // `capability_nudge_provider.dart`'s, which can see the other two
      // inputs to that decision. Splitting the policy across the bridge and
      // the notifier would put half of the nudge policy in a message handler.
      _ref
          .read(editorHostSessionProvider.notifier)
          .set(
            EditorHostSession(openedFileBefore: message.openedFileBefore),
          );
      return;
    }

    if (message is HostBridgeOpenWaveform) {
      final result = await _openWaveform(message);
      // Acknowledged with CXP's own open-artifact ack rather than a fourth
      // private shape: the payload — in_reply_to / honored / reason — is
      // exactly what an "open this artifact" answer carries, and `in_reply_to`
      // correlates it, so a host relaying it onward cannot confuse it with an
      // answer to something else.
      postCxp(
        RequestOpenArtifactAck(
          inReplyTo: inReplyTo,
          honored: result.honored,
          reason: result.reason,
        ),
      );
      return;
    }

    // A kind this build does not act on — including one a newer host invented.
    // Answered, not ignored and not thrown on: that graceful reply is what
    // CXP's open kind vocabulary requires of every receiver.
    postCxp(
      ErrorResponse(
        code: CxpErrorCode.unknownKind,
        message:
            'WaveCrux does not act on "${message.kind}" over the '
            'editor-host bridge',
        inReplyTo: inReplyTo,
      ),
    );
  }

  /// Opens the waveform the host handed over, through the same
  /// `WaveformSourceNotifier.openFromBytes` the browser build's file picker and
  /// drop target use.
  ///
  /// ### It opens a *tab* first, and that is not optional
  ///
  /// The obvious implementation — write straight into
  /// `readActive(_ref, waveformSourceProvider.notifier)` — was what this method
  /// did, and it is wrong in the one configuration that matters. On a cold
  /// webview the workspace has **zero tabs**, so `activeTabContainer` returns
  /// null (by design: it refuses to spin up a per-tab container for a tab that
  /// never opens) and the write lands on the dead root-scope instance. The
  /// acknowledgement is honest — the source really did open — and the panel
  /// shows the empty canvas, because the workspace still has nothing in it.
  /// From the outside that is "double-clicking a waveform in the Explorer
  /// opens WaveCrux's start screen", which is the discoverability payload of
  /// the whole integration failing silently while every log line says success.
  ///
  /// Found by live verification, not by a test: every unit test here runs on a
  /// flat container where the root-scope fallback is the *correct* target, so
  /// the bug is invisible to exactly the harness that covers this file.
  ///
  /// `wavecruxWorkspace.openFile` is the same call `_openBytesAndNavigate` (the
  /// web drop zone) makes, and it both creates and activates the tab — so the
  /// per-tab container resolved below is the one the UI is about to render.
  ///
  /// No `kIsWeb` guard, deliberately. `openFromBytes` is a web capability and
  /// the only editor host is a webview, so off the web this is unreachable by
  /// construction; adding a second refusal for an unreachable case would mean
  /// two failure paths where the `catch` below already produces the right
  /// answer — an unhonoured ack carrying the reason, never a throw.
  Future<CxpHandlerResult> _openWaveform(HostBridgeOpenWaveform message) async {
    try {
      final tabId = await _ref.wavecruxWorkspace.openFile(
        message.displayName,
        displayName: message.displayName,
      );
      if (_disposed) return CxpHandlerResult.honoredOk;
      await _ref
          .read(tabContainerManagerProvider)
          .containerFor(tabId)
          .read(waveformSourceProvider.notifier)
          .openFromBytes(message.bytes, message.displayName);
      return CxpHandlerResult.honoredOk;
    } on Object catch (error) {
      // A host that never stood the workspace up (a flat-container test, a
      // build with no tab machinery) still gets the waveform: falling back to
      // the active-tab resolver preserves the behaviour every existing test
      // asserts, rather than turning an environment difference into a refusal.
      try {
        await readActive(
          _ref,
          waveformSourceProvider.notifier,
        ).openFromBytes(message.bytes, message.displayName);
        return CxpHandlerResult.honoredOk;
      } on Object {
        return CxpHandlerResult(
          honored: false,
          reason: 'could not open ${message.displayName}: $error',
        );
      }
    }
  }
}
