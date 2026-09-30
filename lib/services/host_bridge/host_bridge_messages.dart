// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The host-bridge wire contract: what crosses `window.postMessage` between a
// VSCode extension host and this build, and nothing about *how* it crosses.
//
// Pure Dart — no Flutter, no `dart:js_interop`. The platform half lives behind
// the conditional export in [host_bridge.dart]; everything here is shared by
// both sides of that split and is therefore testable on the VM, which is the
// whole reason it is a separate file. See ARCHITECTURE.md's conditional-export
// section and the sibling shims (`wellen_provider.dart`,
// `wellen_wasm_provider.dart`, `lxt2fst_converter.dart`).
//
// ### Why CXP shapes rather than a private envelope
//
// The bridge carries `CxpEnvelope`s. A VSCode extension that also speaks CXP to
// the other three Crux apps is then a *relay*: it forwards what it receives
// without translating, and the Dart side gains no second protocol to keep in
// step with the first. The one message the protocol has no shape for is
// "here are the bytes of a waveform" — a webview has no filesystem, so
// `request_open_artifact`'s path-based resolution cannot help it — and that is
// carried as a product-defined kind, which is exactly what `CxpMessageKind`'s
// open string vocabulary exists for.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_telemetry/crux_telemetry.dart' show TelemetryEvent;
import 'package:flutter/foundation.dart' show immutable, listEquals, mapEquals;
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';

// ── The marker the extension's index.html shim sets ──────────────────────────

/// Name of the global the extension's `index.html` shim freezes into `window`
/// **before** the Dart entry point loads.
///
/// Mirrors `EDITOR_HOST_MARKER_GLOBAL` in crux-vscode's
/// `packages/wavecrux/src/webview/html.ts`. Renaming it on one side and not the
/// other fails silently — the build reports `form_factor: 'web'` forever after
/// — so both sides name the constant and a test on each side pins it.
const String kEditorHostMarkerGlobal = 'cruxEditorHost';

/// Value of `cruxEditorHost.kind` that means "a VSCode extension host".
const String kEditorHostMarkerKindVscode = 'vscode';

/// Version of the marker contract this build understands.
const int kEditorHostMarkerProtocol = 1;

// ── The frame types the host and the webview exchange ────────────────────────

/// `type` of a frame carrying a [CxpEnvelope] in its `envelope` field.
///
/// Both directions use it: the host relays inbound peer gossip down, and this
/// build's selection changes and acknowledgements go back up.
const String kHostBridgeCxpFrameType = 'crux.cxp';

/// `type` of a frame carrying one telemetry event descriptor in its `event`
/// field.
///
/// Matches `TELEMETRY_MESSAGE_TYPE` in crux-vscode's
/// `packages/wavecrux/src/webview/panel.ts`, which hands `event` to host-core's
/// `TelemetryClient.recordFromWebview`. The descriptor is deliberately just
/// `{name, properties}`: the envelope — `installation_id`, `os`, `form_factor`,
/// the license tier — is the host's to assemble, so there is no envelope field
/// a webview could get wrong or spoof.
const String kHostBridgeTelemetryFrameType = 'crux.telemetry';

/// Bridge framing version, carried on every outbound frame. Distinct from
/// [cxpProtocolVersion], which versions the payload inside the frame.
const int kHostBridgeProtocolVersion = 1;

/// The `from` peer id this build stamps on envelopes it posts to the host.
///
/// A webview has no CXP manifest and no port, so it has no discovered peer
/// identity; the host substitutes its own when it relays onward. This is a
/// stable label, not an identifier anything routes on.
const String kHostBridgePeerId = 'wavecrux.webview';

/// Product-defined CXP message kind: "open the waveform whose bytes are in this
/// payload".
///
/// `CxpMessageKind` is a class of string constants rather than an enum
/// precisely so a product can define a kind without a protocol revision, and
/// this is that case: a webview cannot open a path, so the host — which holds
/// the `TextDocument`/`CustomDocument` — hands over the bytes instead. A CXP
/// peer that does not know the kind answers `unknown_kind` and stays connected,
/// which is the behaviour the open vocabulary is designed around.
const String kHostBridgeOpenWaveformKind = 'crux.open_waveform_bytes';

/// Product-defined CXP message kind: "here is one slice of a waveform whose
/// bytes are too large to cross `postMessage` in a single frame".
///
/// A structured clone of a several-hundred-megabyte `Uint8Array` is one
/// allocation of that size in the extension host, one more in the webview, and
/// a main-thread stall in both while it happens; a multi-gigabyte one simply
/// fails. So the host slices, and [HostBridgeTransferAssembler] reassembles.
/// The completed transfer becomes an ordinary [HostBridgeOpenWaveform] — the
/// open path has one shape, and chunking is a transport concern that ends at
/// the assembler.
///
/// Mirrors `OPEN_WAVEFORM_CHUNK_KIND` in crux-vscode's
/// `packages/wavecrux/src/webview/open-waveform.ts`.
const String kHostBridgeOpenWaveformChunkKind = 'crux.open_waveform_chunk';

/// Largest number of chunks one transfer may declare.
///
/// [kHostBridgeMaxOpenBytes] over the host's 4 MiB chunk size is 64 chunks;
/// 4096 leaves a host free to pick a much smaller chunk and still bounds the
/// bookkeeping. A `count` above this is refused before a single byte is
/// buffered, so a hostile frame cannot make the app hold a transfer open
/// waiting for chunks that will never come.
const int kHostBridgeMaxChunksPerTransfer = 4096;

/// How many transfers [HostBridgeTransferAssembler] will hold open at once.
///
/// Two, not one: VSCode can restore a whole editor group at startup, and a
/// second waveform beginning while the first is still arriving must not
/// discard the first. Beyond that the least-recently-touched transfer is
/// dropped — memory is the scarce resource here, and an abandoned transfer
/// (a webview reload mid-stream) has no other way to be collected.
const int kHostBridgeMaxConcurrentTransfers = 2;

/// Product-defined CXP message kind: "here is the active VSCode color theme,
/// as raw color tokens plus its appearance kind".
///
/// Pushed by the extension's webview shim (`html.ts`) — not the extension
/// host process, which is Node.js and has no DOM, and therefore no access to
/// VSCode's resolved theme colors. VSCode injects them as `--vscode-*` CSS
/// custom properties on the webview document and keeps them live-updated on
/// every theme change, so the shim reads a curated set of them and relays a
/// fresh frame through the very channel this build already listens on — no
/// extension-host code is involved in the read. See
/// `packages/wavecrux/src/webview/html.ts` (crux-vscode) for the curated
/// token list and the `MutationObserver` that detects a live toggle, and
/// `editor_host_theme_synthesizer.dart` for what this build does with the
/// result.
const String kHostBridgeThemeKind = 'crux.theme_tokens';

/// Largest number of raw color tokens accepted in one [HostBridgeThemeTokens]
/// frame. The shim's curated list is a few dozen entries; this is headroom
/// against a malformed or hostile host, not a working budget.
const int kHostBridgeMaxThemeTokens = 128;

/// The `appearance` values a [HostBridgeThemeTokens] frame may carry —
/// mirrors `vscode.ColorThemeKind` exactly, including both high-contrast
/// variants. Neither high-contrast kind is folded into `dark`:
/// `editor_host_theme_synthesizer.dart` resolves `highContrast` to
/// [Brightness.dark] and `highContrastLight` to [Brightness.light], and
/// applies a stricter contrast floor to both than the two ordinary kinds get.
const Set<String> kHostBridgeThemeAppearances = <String>{
  'light',
  'dark',
  'highContrast',
  'highContrastLight',
};

/// "Here is the active VSCode color theme" — the frame the webview shim
/// posts once on load and again on every live theme change. See
/// [kHostBridgeThemeKind].
@immutable
class HostBridgeThemeTokens extends CxpMessage {
  /// Creates the message.
  const HostBridgeThemeTokens({required this.appearance, required this.tokens});

  /// Decodes the payload, or returns `null` when malformed.
  ///
  /// Deliberately lenient on individual token values: a value this build
  /// cannot parse as a hex color is dropped from [tokens] rather than
  /// failing the whole frame, so one VSCode color id whose value this build
  /// does not recognize cannot blank out every token that did parse.
  /// `appearance` and the map shape are the only hard requirements.
  static HostBridgeThemeTokens? tryFromJson(Map<String, Object?> json) {
    final appearance = json['appearance'];
    if (appearance is! String ||
        !kHostBridgeThemeAppearances.contains(appearance)) {
      return null;
    }
    final rawTokens = hostBridgeStringMap(json['tokens']);
    if (rawTokens == null || rawTokens.length > kHostBridgeMaxThemeTokens) {
      return null;
    }
    final tokens = <String, String>{};
    for (final entry in rawTokens.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) tokens[entry.key] = value;
    }
    return HostBridgeThemeTokens(appearance: appearance, tokens: tokens);
  }

  /// `vscode.ColorThemeKind`, lower-camel-cased: one of
  /// [kHostBridgeThemeAppearances].
  final String appearance;

  /// Raw `#RRGGBB`/`#RRGGBBAA` values keyed by VSCode's dotted color id
  /// (e.g. `editor.background`) — the same hex form `ThemePackCodec` reads
  /// and writes, so the synthesizer parses them with
  /// `ThemePackCodec.tryParseColor` rather than a second color parser.
  final Map<String, String> tokens;

  @override
  String get kind => kHostBridgeThemeKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'appearance': appearance,
    'tokens': Map<String, Object?>.of(tokens),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostBridgeThemeTokens &&
          other.appearance == appearance &&
          mapEquals(other.tokens, tokens));

  @override
  int get hashCode => Object.hash(
    appearance,
    Object.hashAllUnordered(
      tokens.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'HostBridgeThemeTokens($appearance, ${tokens.length} tokens)';
}

/// Product-defined CXP message kind: "here is what I know about the
/// installation you are running in".
///
/// One fact today — whether this installation has opened a waveform before —
/// and it is here because it is the one thing the webview structurally cannot
/// work out. The nudge policy forbids a capability nudge on the first file a user
/// opens; deciding that needs state that outlives the window, and only the
/// extension host has any (`ExtensionContext.globalState`, where the extension
/// already persists the same fact for `file.first_opened`).
///
/// A push, not a request: like [kHostBridgeThemeKind] it carries nothing the
/// host could correlate a reply to, and it is answered by the app's behaviour
/// rather than by an ack.
///
/// Mirrors `HOST_SESSION_KIND` in crux-vscode's
/// `packages/wavecrux/src/webview/host-session.ts`. A rename on one side only
/// fails **silently and safely**: this build answers `unknown_kind`, the
/// session provider keeps [EditorHostSession.unknown], and that default
/// suppresses the nudge rather than misfiring it. A test on each side pins
/// the literal.
const String kHostBridgeHostSessionKind = 'crux.host_session';

/// "Here is what the host knows about this installation." See
/// [kHostBridgeHostSessionKind].
@immutable
class HostBridgeHostSession extends CxpMessage {
  /// Creates the message.
  const HostBridgeHostSession({required this.openedFileBefore});

  /// Decodes the payload, or returns `null` when it is malformed.
  ///
  /// Strict on the type: a missing or non-boolean `opened_file_before` is a
  /// frame this build cannot act on, and coercing a truthy value would invent
  /// a `true` — the one value that *enables* a nudge — out of a malformed
  /// frame.
  static HostBridgeHostSession? tryFromJson(Map<String, Object?> json) {
    final openedFileBefore = json['opened_file_before'];
    if (openedFileBefore is! bool) return null;
    return HostBridgeHostSession(openedFileBefore: openedFileBefore);
  }

  /// Whether this installation had opened a waveform before the one now
  /// arriving. Sampled by the host *before* it marks the installation as
  /// having opened one, so the very first open reports `false`.
  final bool openedFileBefore;

  @override
  String get kind => kHostBridgeHostSessionKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'opened_file_before': openedFileBefore,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostBridgeHostSession &&
          other.openedFileBefore == openedFileBefore);

  @override
  int get hashCode => openedFileBefore.hashCode;

  @override
  String toString() => 'HostBridgeHostSession($openedFileBefore)';
}

/// Product-defined CXP message kind: "tell me what these signals are worth at
/// the cursor, and keep telling me".
///
/// The extension's RTL annotation renders
/// signal values as decorations in the user's own Verilog. The waveform, the
/// cursor and the translators all live here; the decorations live in the
/// extension host. So the host names the paths it has resolved for the lines
/// currently on screen, and this build answers with their formatted values.
///
/// **A standing query, not a one-shot.** The host cannot know when the cursor
/// moves — the cursor is ours — and a host that polled for it would either lag
/// the drag or burn a frame budget asking. So the most recent query stays the
/// active one: it is answered immediately and again on every (debounced) cursor
/// move, until a later query replaces its path list or an empty one cancels it.
/// That puts the cursor-follow debounce on the side that owns the cursor, which
/// is the same reason [kCxpCursorDebounce] lives where it does.
///
/// Answered with [kHostBridgeValueResponseKind], correlated by `query_id`
/// rather than by `in_reply_to`: a standing query produces many responses, and
/// `in_reply_to` names one message. Mirrors `VALUE_QUERY_KIND` in crux-vscode's
/// `packages/wavecrux/src/webview/value-query.ts`.
const String kHostBridgeValueQueryKind = 'crux.value_query';

/// Product-defined CXP message kind: the answer to a [kHostBridgeValueQueryKind].
///
/// Mirrors `VALUE_RESPONSE_KIND` in crux-vscode's
/// `packages/wavecrux/src/webview/value-query.ts`.
const String kHostBridgeValueResponseKind = 'crux.value_response';

/// Largest number of design paths one [HostBridgeValueQuery] may name.
///
/// A viewport is forty-odd lines and the host caps itself well under this;
/// the bound is against a malformed or hostile host, since every path costs a
/// hierarchy lookup and possibly a signal load. Over the cap the frame does not
/// decode at all, so no work is started.
const int kHostBridgeMaxValueQueryPaths = 256;

/// "What are these signals worth at the cursor?" See [kHostBridgeValueQueryKind].
@immutable
class HostBridgeValueQuery extends CxpMessage {
  /// Creates the message.
  const HostBridgeValueQuery({required this.queryId, required this.paths});

  /// Decodes the payload, or returns `null` when malformed.
  ///
  /// Strict on `query_id` and on the list shape; lenient within the list, where
  /// a non-string or blank entry is dropped rather than failing the frame. One
  /// unresolvable line in a viewport must not cost the other thirty-nine their
  /// annotations — and an empty list after filtering is still a valid query: it
  /// is how the host cancels.
  static HostBridgeValueQuery? tryFromJson(Map<String, Object?> json) {
    final queryId = json['query_id'];
    if (queryId is! String || queryId.isEmpty) return null;
    final rawPaths = json['paths'];
    if (rawPaths is! List) return null;
    if (rawPaths.length > kHostBridgeMaxValueQueryPaths) return null;
    final paths = <String>[];
    for (final raw in rawPaths) {
      if (raw is! String) continue;
      final path = raw.trim();
      if (path.isEmpty || paths.contains(path)) continue;
      paths.add(path);
    }
    return HostBridgeValueQuery(queryId: queryId, paths: paths);
  }

  /// Correlates the responses. Opaque to this build.
  final String queryId;

  /// Hierarchical design paths, de-duplicated, in the host's order.
  final List<String> paths;

  @override
  String get kind => kHostBridgeValueQueryKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'query_id': queryId,
    'paths': List<Object?>.of(paths),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostBridgeValueQuery &&
          other.queryId == queryId &&
          listEquals(other.paths, paths));

  @override
  int get hashCode => Object.hash(queryId, Object.hashAll(paths));

  @override
  String toString() => 'HostBridgeValueQuery($queryId, ${paths.length} paths)';
}

/// "Here is what they are worth." See [kHostBridgeValueResponseKind].
@immutable
class HostBridgeValueResponse extends CxpMessage {
  /// Creates the message.
  const HostBridgeValueResponse({
    required this.queryId,
    required this.values,
    this.cursorLabel,
  });

  /// The query this answers.
  final String queryId;

  /// Formatted value per design path, rendered by this build's own translators
  /// so an annotation reads exactly like the waveform's value column.
  ///
  /// A path with no entry is a path this build could not answer for — not in
  /// the design, or with no transition at or before the cursor. Absence is a
  /// normal answer; the host annotates nothing rather than showing a blank.
  final Map<String, String> values;

  /// The cursor time these values were sampled at, formatted with the file's
  /// timescale. Shown in the host's hover so an annotation can never be read as
  /// "now" when it means "at the cursor".
  final String? cursorLabel;

  @override
  String get kind => kHostBridgeValueResponseKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'query_id': queryId,
    'values': Map<String, Object?>.of(values),
    if (cursorLabel != null) 'cursor_label': cursorLabel,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostBridgeValueResponse &&
          other.queryId == queryId &&
          other.cursorLabel == cursorLabel &&
          mapEquals(other.values, values));

  @override
  int get hashCode => Object.hash(
    queryId,
    cursorLabel,
    Object.hashAllUnordered(
      values.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'HostBridgeValueResponse($queryId, ${values.length} values)';
}

/// Product-defined CXP message kind: "here is everything the cross-probe
/// panel needs to render, as of now".
///
/// ### Why the panel needs this at all
///
/// `app.dart` instantiates the CXP lifecycle bridge only on a desktop
/// platform, because a webview has no `dart:io` and cannot bind a TCP socket.
/// That gate is correct and stays. What was wrong was the conclusion the
/// panel drew from it: `cxpServerProvider.isRunning` is false inside VSCode,
/// so the panel showed "the CXP server is offline — enable it in Settings",
/// blaming a setting that was already on and could never have helped, while
/// the *extension host* was a healthy CXP peer the whole time, with its own
/// `peer_id`, its own manifest and its own live peer list.
///
/// So under an editor host the panel's four reactive sources come from the
/// host instead of from this build's (absent) CXP server. One frame carries
/// all of them, because they are one consistent snapshot and shipping them
/// as four independent pushes would let the panel render a peer list from
/// one instant against an event log from another.
///
/// **A push, not a request**, exactly like [kHostBridgeThemeKind]: the host
/// posts a fresh frame whenever its own state changes and this build never
/// polls. See `packages/host-core/src/cross-probe/` (crux-vscode) for the
/// producing half and `CROSS_PROBE_STATE_KIND` in
/// `packages/wavecrux/src/webview/cross-probe.ts` for the literal, which a
/// test on each side pins.
const String kHostBridgeCrossProbeStateKind = 'crux.cross_probe_state';

/// Product-defined CXP message kind: "send this selection to that one peer".
///
/// The reverse direction of [kHostBridgeCrossProbeStateKind]: the panel's
/// per-peer Send button. A webview cannot reach a peer's socket, so the host
/// does it — the payload is CXP §9.3's own `notify_selection` shape
/// (https://edacrux.app/cxp#sec-9-3) under
/// `selection`, decoded on the host with the shared decoder rather than by
/// hand, plus the `peer_id` naming which discovered peer to send it to
/// (CXP §9.3 has no addressee field because a `notify_selection` is normally
/// broadcast; a *directed* send needs one).
///
/// Answered by the host's next [kHostBridgeCrossProbeStateKind] frame — the
/// send appears in `events` when it was delivered, and in `send_failure`
/// correlated on this frame's `message_id` when it was not. There is no
/// separate ack kind for the same reason [kHostBridgeValueQueryKind] has
/// none: the answer *is* the acknowledgement, and the answer already has a
/// frame.
const String kHostBridgeCrossProbeSendKind = 'crux.cross_probe_send';

/// Largest number of peers, unreachable-peer records or events one
/// [HostBridgeCrossProbeState] frame may carry.
///
/// The event ceiling matches `kCxpEventLogMaxEntries` (50) so a hosted panel
/// shows the same depth of history as a desktop one. The peer ceilings are
/// far above any real manifest directory and exist only so a malformed or
/// hostile host cannot make this build allocate without bound; over the cap
/// the list is **truncated**, not rejected, because a panel showing the first
/// fifty of an absurd peer list is a better answer than a panel showing
/// nothing.
const int kHostBridgeMaxCrossProbePeers = 64;

/// See [kHostBridgeMaxCrossProbePeers].
const int kHostBridgeMaxCrossProbeEvents = 50;

/// "Here is the cross-probe state" — see [kHostBridgeCrossProbeStateKind].
@immutable
class HostBridgeCrossProbeState extends CxpMessage {
  /// Creates the message.
  const HostBridgeCrossProbeState({
    required this.online,
    this.peers = const <PeerIdentity>[],
    this.unreachable = const <CxpDialFailure>[],
    this.events = const <CxpEventLogEntry>[],
    this.sendFailure,
  });

  /// Decodes the payload, or returns `null` when malformed.
  ///
  /// Strict on `online` — it drives whether the offline banner shows, and
  /// coercing a truthy value would invent an answer to the exact question
  /// this whole frame exists to answer honestly. Lenient inside the three
  /// lists: an entry this build cannot decode is dropped rather than failing
  /// the frame, because one peer with a malformed identity must not cost the
  /// user their whole peer list.
  static HostBridgeCrossProbeState? tryFromJson(Map<String, Object?> json) {
    final online = json['online'];
    if (online is! bool) return null;
    return HostBridgeCrossProbeState(
      online: online,
      peers: _decodeList(
        json['peers'],
        kHostBridgeMaxCrossProbePeers,
        _peerFromJson,
      ),
      unreachable: _decodeList(
        json['unreachable'],
        kHostBridgeMaxCrossProbePeers,
        _dialFailureFromJson,
      ),
      events: _decodeList(
        json['events'],
        kHostBridgeMaxCrossProbeEvents,
        _eventFromJson,
      ),
      sendFailure: _sendFailureFromJson(json['send_failure']),
    );
  }

  /// Whether cross-probing is live. Under an editor host this is the *host's*
  /// peer, never this build's CXP server — which is stopped by construction
  /// and whose `isRunning` is exactly the flag that produced the false
  /// "server is offline" banner.
  final bool online;

  /// Discovered peers, decoded from their `PeerIdentity` JSON
  /// (https://edacrux.app/cxp#sec-8-1).
  final List<PeerIdentity> peers;

  /// Peers the host discovered and could not dial.
  final List<CxpDialFailure> unreachable;

  /// The host's cross-probe event log, oldest-first — the same ordering
  /// `cxpEventLogProvider` uses, so the panel's controller maps both through
  /// one function.
  final List<CxpEventLogEntry> events;

  /// The send this frame is refusing, when it is refusing one. See
  /// [kHostBridgeCrossProbeSendKind].
  final HostBridgeCrossProbeSendFailure? sendFailure;

  @override
  String get kind => kHostBridgeCrossProbeStateKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'online': online,
    'peers': peers.map((p) => p.toJson()).toList(growable: false),
    'unreachable': unreachable
        .map(
          (f) => <String, Object?>{
            'peer_id': f.peerId,
            'host': f.host,
            'port': f.port,
            'error': '${f.error}',
            'consecutive_failures': f.consecutiveFailures,
            'next_retry_after_ticks': f.nextRetryAfterTicks,
          },
        )
        .toList(growable: false),
    'events': events
        .map(
          (e) => <String, Object?>{
            'message_kind': e.messageKind,
            'direction': e.direction.name,
            'peer_label': e.peerLabel,
            'timestamp_ms': e.timestamp.millisecondsSinceEpoch,
            if (e.summary != null) 'summary': e.summary,
          },
        )
        .toList(growable: false),
    if (sendFailure != null) 'send_failure': sendFailure!.toJson(),
  };

  @override
  String toString() =>
      'HostBridgeCrossProbeState(online: $online, ${peers.length} peers, '
      '${unreachable.length} unreachable, ${events.length} events)';
}

/// A directed panel send the host could not deliver.
///
/// [inReplyTo] is the `message_id` of the [HostBridgeCrossProbeSend] frame
/// this answers, which is what lets the panel show one toast per rejected
/// send rather than one per state push — the host re-sends its state on every
/// peer change, and a failure with no identity would re-fire the toast each
/// time.
@immutable
class HostBridgeCrossProbeSendFailure {
  /// Creates a send-failure record.
  const HostBridgeCrossProbeSendFailure({
    required this.inReplyTo,
    required this.peerLabel,
    this.reason,
  });

  /// The `message_id` of the send frame this refuses.
  final String inReplyTo;

  /// Human-readable label of the peer the send was aimed at.
  final String peerLabel;

  /// Why it failed, in the host's words, or `null` when there is nothing to
  /// add beyond "it did not go".
  final String? reason;

  /// JSON encoding.
  Map<String, Object?> toJson() => <String, Object?>{
    'in_reply_to': inReplyTo,
    'peer_label': peerLabel,
    if (reason != null) 'reason': reason,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostBridgeCrossProbeSendFailure &&
          other.inReplyTo == inReplyTo &&
          other.peerLabel == peerLabel &&
          other.reason == reason);

  @override
  int get hashCode => Object.hash(inReplyTo, peerLabel, reason);

  @override
  String toString() =>
      'HostBridgeCrossProbeSendFailure($peerLabel, $inReplyTo, $reason)';
}

/// "Send this selection to that peer" — see [kHostBridgeCrossProbeSendKind].
///
/// Outbound only: this build constructs it, the host decodes it. There is
/// deliberately no `tryFromJson`, and therefore no branch for it in
/// [decodeHostBridgePayload] — a host that posted one *down* would be asking
/// the webview to reach a socket it does not have, and answering
/// `unknown_kind` is the honest reply.
@immutable
class HostBridgeCrossProbeSend extends CxpMessage {
  /// Creates the message.
  const HostBridgeCrossProbeSend({
    required this.peerId,
    required this.selection,
  });

  /// `peer_id` of the discovered peer to send to.
  final String peerId;

  /// The CXP §9.3 announcement itself, encoded by `crux_cxp`'s own
  /// [NotifySelection] rather than by a shape invented here.
  final NotifySelection selection;

  @override
  String get kind => kHostBridgeCrossProbeSendKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'peer_id': peerId,
    'selection': selection.toJson(),
  };

  @override
  String toString() =>
      'HostBridgeCrossProbeSend($peerId, ${selection.elements.length} elements)';
}

/// Decodes at most [max] entries of [raw] with [decode], dropping the ones
/// that fail. See [HostBridgeCrossProbeState.tryFromJson] for why a bad entry
/// is dropped rather than fatal.
List<T> _decodeList<T>(
  Object? raw,
  int max,
  T? Function(Map<String, Object?> json) decode,
) {
  if (raw is! List) return <T>[];
  final out = <T>[];
  for (final entry in raw) {
    if (out.length >= max) break;
    final json = hostBridgeStringMap(entry);
    if (json == null) continue;
    final decoded = decode(json);
    if (decoded != null) out.add(decoded);
  }
  return out;
}

PeerIdentity? _peerFromJson(Map<String, Object?> json) {
  try {
    return PeerIdentity.fromJson(json);
  } on FormatException {
    return null;
  }
}

CxpDialFailure? _dialFailureFromJson(Map<String, Object?> json) {
  final peerId = json['peer_id'];
  if (peerId is! String || peerId.isEmpty) return null;
  final host = json['host'];
  final port = json['port'];
  return CxpDialFailure(
    peerId: peerId,
    host: host is String ? host : '',
    port: port is int ? port : 0,
    // The host's `error` is a string it already stringified; keeping it as
    // one rather than re-wrapping it in an exception preserves exactly what
    // the panel renders on desktop, where `error.toString()` is what is
    // shown.
    error: json['error'] is String ? json['error']! : 'unreachable',
    consecutiveFailures: json['consecutive_failures'] is int
        ? json['consecutive_failures']! as int
        : 1,
    nextRetryAfterTicks: json['next_retry_after_ticks'] is int
        ? json['next_retry_after_ticks']! as int
        : 0,
  );
}

CxpEventLogEntry? _eventFromJson(Map<String, Object?> json) {
  final messageKind = json['message_kind'];
  if (messageKind is! String || messageKind.isEmpty) return null;
  final peerLabel = json['peer_label'];
  if (peerLabel is! String) return null;
  final timestampMs = json['timestamp_ms'];
  final summary = json['summary'];
  return CxpEventLogEntry(
    timestamp: timestampMs is int
        ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
        : DateTime.now(),
    direction: json['direction'] == 'outbound'
        ? CxpEventDirection.outbound
        : CxpEventDirection.inbound,
    messageKind: messageKind,
    peerLabel: peerLabel,
    summary: summary is String && summary.isNotEmpty ? summary : null,
  );
}

HostBridgeCrossProbeSendFailure? _sendFailureFromJson(Object? raw) {
  final json = hostBridgeStringMap(raw);
  if (json == null) return null;
  final inReplyTo = json['in_reply_to'];
  if (inReplyTo is! String || inReplyTo.isEmpty) return null;
  final peerLabel = json['peer_label'];
  final reason = json['reason'];
  return HostBridgeCrossProbeSendFailure(
    inReplyTo: inReplyTo,
    peerLabel: peerLabel is String ? peerLabel : '',
    reason: reason is String && reason.isNotEmpty ? reason : null,
  );
}

/// Largest payload [HostBridgeOpenWaveform] will decode, in bytes.
///
/// Inbound `postMessage` data is untrusted (a frame is a JS value the app did
/// not construct), and the one field here that can be made arbitrarily large is
/// the waveform buffer. 256 MiB is well above any trace the single-threaded
/// WASM parser finishes in a usable time and well below the point where
/// decoding the frame is itself the failure. Over the cap the message does not
/// decode at all, so the app never allocates the buffer.
const int kHostBridgeMaxOpenBytes = 256 * 1024 * 1024;

// ── Inbound decoding ─────────────────────────────────────────────────────────

/// A decoded inbound frame: the envelope's routing metadata plus its payload.
@immutable
class HostBridgeInbound {
  /// Creates a decoded inbound frame.
  const HostBridgeInbound({required this.envelope, required this.message});

  /// The envelope, needed for `in_reply_to` on the acknowledgement.
  final CxpEnvelope envelope;

  /// The decoded payload — a CXP message type, or [HostBridgeOpenWaveform].
  final CxpMessage message;
}

/// Coerces [raw] to a string-keyed map, or returns `null`.
///
/// Strict on purpose: `dartify()` yields `Map<Object?, Object?>` for a JS
/// object, and a lazy `cast` would defer the type failure to the first read —
/// inside message handling, where a throw is exactly what must not happen. A
/// non-string key means the value did not come from JSON and is rejected whole.
Map<String, Object?>? hostBridgeStringMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is! Map) return null;
  final out = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) return null;
    out[key] = entry.value;
  }
  return out;
}

/// Decodes a frame the host posted into an envelope and its payload, or returns
/// `null` when [raw] is not a well-formed [kHostBridgeCxpFrameType] frame this
/// build can act on.
///
/// Every rejection is silent and total — a malformed frame is ignored, never
/// partially applied and never thrown out of. The checks, in order:
///
///  1. the frame is a string-keyed map whose `type` is the CXP frame type;
///  2. `envelope` decodes as a [CxpEnvelope] (missing required fields throw
///     [FormatException] inside [CxpEnvelope.fromJson], which is caught here);
///  3. the envelope's major version is compatible with ours — CXP's own
///     version policy, applied at the bridge rather than re-invented;
///  4. the payload decodes for its kind, including the bounds on
///     [HostBridgeOpenWaveform].
HostBridgeInbound? decodeHostBridgeFrame(Object? raw) {
  final frame = hostBridgeStringMap(raw);
  if (frame == null) return null;
  if (frame['type'] != kHostBridgeCxpFrameType) return null;
  final envelopeJson = hostBridgeStringMap(frame['envelope']);
  if (envelopeJson == null) return null;
  try {
    final envelope = CxpEnvelope.fromJson(envelopeJson);
    if (!isCompatibleCxpVersion(envelope.cxpVersion)) return null;
    final message = decodeHostBridgePayload(envelope.kind, envelope.payload);
    if (message == null) return null;
    return HostBridgeInbound(envelope: envelope, message: message);
  } on FormatException {
    return null;
  } on Object {
    return null;
  }
}

/// Decodes an envelope payload of [kind], adding this bridge's product-defined
/// kinds to the ones [decodeCxpMessage] already knows.
///
/// Returns `null` for a kind this build does not model and for a payload that
/// does not decode — the caller answers `unknown_kind` rather than crashing,
/// which is what CXP's open kind vocabulary requires of every receiver.
CxpMessage? decodeHostBridgePayload(String kind, Map<String, Object?> payload) {
  if (kind == kHostBridgeOpenWaveformKind) {
    return HostBridgeOpenWaveform.tryFromJson(payload);
  }
  if (kind == kHostBridgeOpenWaveformChunkKind) {
    return HostBridgeOpenWaveformChunk.tryFromJson(payload);
  }
  if (kind == kHostBridgeThemeKind) {
    return HostBridgeThemeTokens.tryFromJson(payload);
  }
  if (kind == kHostBridgeHostSessionKind) {
    return HostBridgeHostSession.tryFromJson(payload);
  }
  if (kind == kHostBridgeValueQueryKind) {
    return HostBridgeValueQuery.tryFromJson(payload);
  }
  if (kind == kHostBridgeCrossProbeStateKind) {
    return HostBridgeCrossProbeState.tryFromJson(payload);
  }
  try {
    return decodeCxpMessage(kind, payload);
  } on FormatException {
    return null;
  }
}

/// Decodes a waveform buffer from a payload field, or returns `null` when the
/// value is not bytes or exceeds [kHostBridgeMaxOpenBytes].
///
/// Four shapes are accepted because the host may reach us by either route: the
/// VSCode webview channel is a structured clone, which preserves a `Uint8Array`
/// (arriving as [Uint8List] or a [ByteBuffer] after `dartify()`), while a
/// JSON-only relay has to base64 it. Both are the same bytes; refusing one of
/// them would make the bridge depend on which transport the host happened to
/// pick.
/// [maxBytes] defaults to [kHostBridgeMaxOpenBytes] and is a parameter only so
/// the cap can be exercised with a small buffer — asserting a 256 MiB refusal
/// by allocating 256 MiB would be a strange way to test the check that exists
/// to avoid the allocation.
Uint8List? hostBridgeBytesFrom(
  Object? raw, {
  int maxBytes = kHostBridgeMaxOpenBytes,
}) {
  Uint8List? bytes;
  if (raw is Uint8List) {
    bytes = raw;
  } else if (raw is ByteBuffer) {
    bytes = raw.asUint8List();
  } else if (raw is List<int>) {
    if (raw.length > maxBytes) return null;
    bytes = Uint8List.fromList(raw);
  } else if (raw is String) {
    // Length-check the encoded form first: base64 expands 3 bytes to 4, so a
    // string over 4/3 of the cap cannot decode under it, and this refuses the
    // oversize buffer without ever allocating it.
    if (raw.length > (maxBytes ~/ 3) * 4 + 4) return null;
    try {
      bytes = base64Decode(raw);
    } on FormatException {
      return null;
    }
  }
  if (bytes == null) return null;
  if (bytes.lengthInBytes > maxBytes) return null;
  return bytes;
}

/// "Open this waveform from the bytes I am handing you" — the one message the
/// bridge carries that CXP has no shape for. See
/// [kHostBridgeOpenWaveformKind].
@immutable
class HostBridgeOpenWaveform extends CxpMessage {
  /// Creates the message.
  const HostBridgeOpenWaveform({
    required this.displayName,
    required this.bytes,
  });

  /// Decodes the payload, or returns `null` when it is malformed or the buffer
  /// exceeds [kHostBridgeMaxOpenBytes].
  ///
  /// Returns `null` rather than throwing because every other rejection on this
  /// path is a `null`, and a message that asks for too much is not a different
  /// class of event from one that asks for nonsense.
  static HostBridgeOpenWaveform? tryFromJson(
    Map<String, Object?> json, {
    int maxBytes = kHostBridgeMaxOpenBytes,
  }) {
    final displayName = json['display_name'];
    if (displayName is! String || displayName.isEmpty) return null;
    final bytes = hostBridgeBytesFrom(
      json['bytes'] ?? json['bytes_base64'],
      maxBytes: maxBytes,
    );
    if (bytes == null) return null;
    return HostBridgeOpenWaveform(displayName: displayName, bytes: bytes);
  }

  /// The file's basename — used for format detection and as the tab label.
  final String displayName;

  /// The waveform's raw bytes, at most [kHostBridgeMaxOpenBytes] of them.
  final Uint8List bytes;

  @override
  String get kind => kHostBridgeOpenWaveformKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'display_name': displayName,
    'bytes_base64': base64Encode(bytes),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostBridgeOpenWaveform &&
          other.displayName == displayName &&
          other.bytes.lengthInBytes == bytes.lengthInBytes &&
          identical(other.bytes, bytes));

  @override
  int get hashCode => Object.hash(displayName, bytes.lengthInBytes);

  @override
  String toString() =>
      'HostBridgeOpenWaveform($displayName, ${bytes.lengthInBytes} bytes)';
}

/// One slice of a chunked waveform transfer. See
/// [kHostBridgeOpenWaveformChunkKind].
///
/// Every field the assembler needs to validate a chunk *without consulting the
/// transfer it belongs to* is carried on the chunk itself — `count`,
/// `total_bytes` and `display_name` are repeated on all of them. That
/// redundancy is what lets a chunk be rejected on its own terms (an impossible
/// index, a total over the cap) before it is buffered, and lets a chunk that
/// disagrees with its transfer be detected rather than blended into it.
@immutable
class HostBridgeOpenWaveformChunk extends CxpMessage {
  /// Creates one slice of a transfer.
  const HostBridgeOpenWaveformChunk({
    required this.transferId,
    required this.index,
    required this.count,
    required this.displayName,
    required this.totalBytes,
    required this.bytes,
  });

  /// Decodes a chunk payload, or returns `null` when any bound is violated.
  ///
  /// The bounds, in the order they are applied — each one before the
  /// allocation it protects against:
  ///
  ///  1. `transfer_id` is a non-empty string of at most
  ///     [maxTransferIdLength] characters (it is a map key the app holds);
  ///  2. `count` is `1..`[kHostBridgeMaxChunksPerTransfer];
  ///  3. `index` is `0..count - 1`;
  ///  4. `total_bytes` is `1..maxBytes`;
  ///  5. the chunk's own bytes decode under `maxBytes` and do not exceed
  ///     `total_bytes` — a single chunk claiming more than the whole transfer
  ///     is malformed by construction.
  static HostBridgeOpenWaveformChunk? tryFromJson(
    Map<String, Object?> json, {
    int maxBytes = kHostBridgeMaxOpenBytes,
  }) {
    final transferId = json['transfer_id'];
    if (transferId is! String ||
        transferId.isEmpty ||
        transferId.length > maxTransferIdLength) {
      return null;
    }
    final displayName = json['display_name'];
    if (displayName is! String || displayName.isEmpty) return null;
    final count = json['count'];
    if (count is! int || count < 1 || count > kHostBridgeMaxChunksPerTransfer) {
      return null;
    }
    final index = json['index'];
    if (index is! int || index < 0 || index >= count) return null;
    final totalBytes = json['total_bytes'];
    if (totalBytes is! int || totalBytes < 1 || totalBytes > maxBytes) {
      return null;
    }
    final bytes = hostBridgeBytesFrom(
      json['bytes'] ?? json['bytes_base64'],
      maxBytes: maxBytes,
    );
    if (bytes == null || bytes.lengthInBytes > totalBytes) return null;
    return HostBridgeOpenWaveformChunk(
      transferId: transferId,
      index: index,
      count: count,
      displayName: displayName,
      totalBytes: totalBytes,
      bytes: bytes,
    );
  }

  /// Longest `transfer_id` accepted. The host's is a short opaque token; the
  /// cap exists because the value becomes a key in a map this build holds.
  static const int maxTransferIdLength = 64;

  /// Opaque token grouping the chunks of one transfer.
  final String transferId;

  /// This chunk's position, `0`-based.
  final int index;

  /// How many chunks the whole transfer has.
  final int count;

  /// The file's basename, repeated on every chunk. See the class docs.
  final String displayName;

  /// The assembled length the transfer will have, repeated on every chunk.
  final int totalBytes;

  /// This slice's bytes.
  final Uint8List bytes;

  /// Whether this is the slice that completes the transfer.
  bool get isLast => index == count - 1;

  @override
  String get kind => kHostBridgeOpenWaveformChunkKind;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'transfer_id': transferId,
    'index': index,
    'count': count,
    'display_name': displayName,
    'total_bytes': totalBytes,
    'bytes_base64': base64Encode(bytes),
  };

  @override
  String toString() =>
      'HostBridgeOpenWaveformChunk($displayName, $transferId '
      '${index + 1}/$count, ${bytes.lengthInBytes} of $totalBytes bytes)';
}

/// What [HostBridgeTransferAssembler.accept] decided about one chunk.
enum HostBridgeTransferState {
  /// Buffered; the transfer is still incomplete.
  accepted,

  /// This chunk completed the transfer — [HostBridgeTransferResult.waveform]
  /// carries the assembled bytes.
  completed,

  /// The chunk was refused and the transfer it named (if any) discarded.
  /// [HostBridgeTransferResult.reason] says why.
  rejected,
}

/// The outcome of offering one chunk to the assembler.
@immutable
class HostBridgeTransferResult {
  /// Creates a result.
  const HostBridgeTransferResult(this.state, {this.waveform, this.reason});

  /// What happened.
  final HostBridgeTransferState state;

  /// Set only when [state] is [HostBridgeTransferState.completed].
  final HostBridgeOpenWaveform? waveform;

  /// Set only when [state] is [HostBridgeTransferState.rejected]. Short and
  /// machine-ish: it travels back to the host as an `ErrorResponse` message.
  final String? reason;
}

/// Reassembles chunked waveform transfers, bounded in every dimension that a
/// hostile or merely broken host could otherwise grow without limit.
///
/// ### What "bounded" means here, concretely
///
/// * **Per transfer**: at most [kHostBridgeMaxOpenBytes], enforced against the
///   declared `total_bytes` before the first chunk is buffered *and* against
///   the running total as each chunk arrives.
/// * **Across transfers**: at most [kHostBridgeMaxConcurrentTransfers] open,
///   and at most [kHostBridgeMaxOpenBytes] buffered in total — a host cannot
///   open two transfers to hold twice the cap.
/// * **In time**: chunks must arrive **strictly in order**. `postMessage`
///   preserves ordering, so an out-of-order index means the stream is not the
///   one this assembler is reassembling, and the transfer is discarded rather
///   than held open indefinitely waiting for a gap to fill. This is also what
///   removes any need for a timer: nothing here expires, because nothing here
///   can be left half-open by anything but abandonment, which the
///   least-recently-touched eviction collects.
/// * **In agreement**: `count`, `total_bytes` and `display_name` must match
///   what the transfer's first chunk declared. A mid-stream change is a
///   different transfer wearing the same id.
///
/// A rejection always discards the whole transfer. There is no partial-open:
/// half a waveform is not a smaller waveform, it is a corrupt one.
class HostBridgeTransferAssembler {
  /// Creates an assembler. [maxBytes] is a parameter only so the caps can be
  /// exercised with small buffers — asserting a 256 MiB refusal by allocating
  /// 256 MiB would be a strange way to test the check that exists to avoid the
  /// allocation.
  HostBridgeTransferAssembler({this.maxBytes = kHostBridgeMaxOpenBytes});

  /// The per-transfer and total buffered ceiling, in bytes.
  final int maxBytes;

  /// Open transfers, in least-recently-touched-first order (Dart's `Map`
  /// preserves insertion order, and a touched transfer is re-inserted).
  final Map<String, _HostBridgeTransfer> _open =
      <String, _HostBridgeTransfer>{};

  /// How many transfers are currently open. Inspection seam for tests.
  int get openTransferCount => _open.length;

  /// Total bytes currently buffered across all open transfers.
  int get bufferedBytes =>
      _open.values.fold(0, (sum, transfer) => sum + transfer.received);

  /// Offers [chunk] to the assembler.
  ///
  /// Never throws. See the class docs for every way this can return
  /// [HostBridgeTransferState.rejected].
  HostBridgeTransferResult accept(HostBridgeOpenWaveformChunk chunk) {
    if (chunk.totalBytes > maxBytes) {
      return _reject(chunk.transferId, 'transfer exceeds the byte cap');
    }

    var transfer = _open[chunk.transferId];
    if (transfer == null) {
      if (chunk.index != 0) {
        // A transfer this build never saw the start of. Nothing to append to,
        // and inventing a prefix of zeroes would produce a corrupt waveform
        // that looks like a successful open.
        return _reject(chunk.transferId, 'chunk arrived before its transfer');
      }
      if (bufferedBytes + chunk.totalBytes > maxBytes) {
        return _reject(
          chunk.transferId,
          'transfer would exceed the total buffered cap',
        );
      }
      _evictWhileOverConcurrencyLimit();
      transfer = _HostBridgeTransfer(
        displayName: chunk.displayName,
        count: chunk.count,
        totalBytes: chunk.totalBytes,
      );
      _open[chunk.transferId] = transfer;
    } else if (!transfer.agreesWith(chunk)) {
      return _reject(chunk.transferId, 'chunk disagrees with its transfer');
    } else if (chunk.index != transfer.nextIndex) {
      return _reject(chunk.transferId, 'chunk out of order');
    }

    if (transfer.received + chunk.bytes.lengthInBytes > transfer.totalBytes) {
      return _reject(chunk.transferId, 'transfer overran its declared length');
    }
    transfer.append(chunk.bytes);

    if (!chunk.isLast) {
      // Touch: re-inserting moves it to the end of the eviction order.
      _open
        ..remove(chunk.transferId)
        ..[chunk.transferId] = transfer;
      return const HostBridgeTransferResult(HostBridgeTransferState.accepted);
    }

    if (transfer.received != transfer.totalBytes) {
      return _reject(chunk.transferId, 'transfer ended short of its length');
    }
    _open.remove(chunk.transferId);
    return HostBridgeTransferResult(
      HostBridgeTransferState.completed,
      waveform: HostBridgeOpenWaveform(
        displayName: transfer.displayName,
        bytes: transfer.take(),
      ),
    );
  }

  /// Drops every open transfer and the memory behind it.
  void clear() => _open.clear();

  HostBridgeTransferResult _reject(String transferId, String reason) {
    _open.remove(transferId);
    return HostBridgeTransferResult(
      HostBridgeTransferState.rejected,
      reason: reason,
    );
  }

  void _evictWhileOverConcurrencyLimit() {
    while (_open.length >= kHostBridgeMaxConcurrentTransfers) {
      _open.remove(_open.keys.first);
    }
  }
}

/// One in-flight transfer's accumulated state.
class _HostBridgeTransfer {
  _HostBridgeTransfer({
    required this.displayName,
    required this.count,
    required this.totalBytes,
  });

  final String displayName;
  final int count;
  final int totalBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  int received = 0;
  int nextIndex = 0;

  bool agreesWith(HostBridgeOpenWaveformChunk chunk) =>
      chunk.count == count &&
      chunk.totalBytes == totalBytes &&
      chunk.displayName == displayName;

  void append(Uint8List bytes) {
    _builder.add(bytes);
    received += bytes.lengthInBytes;
    nextIndex += 1;
  }

  Uint8List take() => _builder.takeBytes();
}

// ── Outbound framing ─────────────────────────────────────────────────────────

/// Wraps [envelope] in the frame shape the host's message router expects.
Map<String, Object?> hostBridgeCxpFrame(CxpEnvelope envelope) =>
    <String, Object?>{
      'type': kHostBridgeCxpFrameType,
      'protocol': kHostBridgeProtocolVersion,
      'envelope': envelope.toJson(),
    };

/// Wraps [event] in the frame host-core's `recordFromWebview` reads.
///
/// Carries the event *descriptor* only. The timestamp is deliberately dropped:
/// `crux_telemetry` never transmits it either (per-event client timestamps
/// amount to an interaction sequence), and the host's queue ages on its own
/// clock.
Map<String, Object?> hostBridgeTelemetryFrame(TelemetryEvent event) =>
    <String, Object?>{
      'type': kHostBridgeTelemetryFrameType,
      'protocol': kHostBridgeProtocolVersion,
      'event': <String, Object?>{
        'name': event.name,
        if (event.properties.isNotEmpty)
          'properties': Map<String, Object?>.of(event.properties),
      },
    };
