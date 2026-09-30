// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' as cxp_ui;
import 'package:crux_ide_layout/crux_ide_layout.dart'
    show kCruxErrorSnackDuration, kCruxInfoSnackDuration;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/remote/providers/cross_probe_originate_gate_provider.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/host_bridge/editor_host_cross_probe_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

/// WaveCrux's docked cross-probe panel.
///
/// A thin `ConsumerStatefulWidget` host around the shared
/// `crux_cxp_ui.CrossProbePanel`: it owns a [WaveCruxCrossProbePanelController]
/// that bridges WaveCrux's live CXP Riverpod state into the panel's reactive
/// contract, and disposes it with the widget. WaveCrux's old modal `Dialog`
/// presentation of the panel is retired in favour of this docked side-panel,
/// which the viewer screen swaps into the right pane when
/// `PanelLayoutState.crossProbeVisible` is set.
///
/// Rendered inside the active tab's `ProviderScope`, so per-tab providers
/// (cursor, waveform source, panel layout) resolve to the focused tab; the
/// root-scoped CXP server/peers/events resolve via child-scope fall-through.
class WaveCruxCrossProbePanel extends ConsumerStatefulWidget {
  /// Creates the docked cross-probe panel.
  const WaveCruxCrossProbePanel({super.key});

  @override
  ConsumerState<WaveCruxCrossProbePanel> createState() =>
      _WaveCruxCrossProbePanelState();
}

class _WaveCruxCrossProbePanelState
    extends ConsumerState<WaveCruxCrossProbePanel> {
  late final WaveCruxCrossProbePanelController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WaveCruxCrossProbePanelController(ref);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return cxp_ui.CrossProbePanel(
      controller: _controller,
      // Docked as a CruxDock tab: the strip already carries the icon, the
      // label and the ×, so the panel's own header would duplicate all
      // three directly underneath.
      showHeader: false,
      strings: cxp_ui.CrossProbePanelStrings(
        title: l10n.crossProbePanelTitle,
        closeTooltip: l10n.crossProbeCloseTooltip,
        serverOffline: l10n.crossProbeServerOffline,
        peersSectionTitle: l10n.crossProbePeersListTitle,
        noPeers: l10n.crossProbeNoPeers,
        sendTooltip: l10n.crossProbeSendTooltip,
        unreachableSectionTitle: l10n.crossProbeUnreachableTitle,
        eventsSectionTitle: l10n.crossProbeEventsListTitle,
        noEvents: l10n.crossProbeNoEvents,
        clearEventsLabel: l10n.crossProbeClearEventsLabel,
        // The peer's reason arrives in the peer's own words; only the frame
        // around it is ours to translate. A send that never reached the peer
        // is not a toast here: it gets `crossProbeSendUnreachable`.
        sendRejected: (peer, reason) => reason == null || reason.isEmpty
            ? l10n.crossProbeSendFailed(peer)
            : l10n.crossProbeSendRefused(peer, reason),
      ),
    );
  }
}

/// Adapts WaveCrux's live CXP state onto the app-agnostic
/// [cxp_ui.CrossProbePanelController] the shared panel renders against.
///
/// This is the reference per-app adopter. It bridges four reactive sources into
/// the four [ValueListenable]s the panel wraps in `ValueListenableBuilder`s —
/// peers, the event log (mapped from WaveCrux's [CxpEventLogEntry] into the
/// shared [cxp_ui.CrossProbeEvent] superset), dial failures, and whether
/// cross-probing is live — and routes the panel's commands back out:
///
/// * [onSendTo] resolves the current selection + cursor time and sends it to
///   the chosen peer, tagging it with the reverse-flow `crux.design_id`
///   metadata so a receiver with no matching waveform open can resolve and
///   open this design's dump (reverse cross-probe).
/// * [onClose] / [onOpenPanel] toggle the per-tab `crossProbeVisible` flag.
/// * [onClearEvents] empties the event buffer.
///
/// ### Two sources, chosen once, and why the second one had to exist
///
/// On **desktop** the four sources are `cxpPeersProvider`,
/// `cxpEventLogProvider`, `cxpDialFailuresProvider` and `cxpServerProvider`'s
/// `isRunning`, all fed by this build's own CXP server. That is unchanged, and
/// [EditorHostKind.none] — every platform but a VSCode webview — takes exactly
/// that path.
///
/// Inside a **VSCode webview** all four are structurally empty. `app.dart`
/// instantiates the CXP lifecycle bridge only on linux/macOS/windows because a
/// webview has no `dart:io` and cannot bind a TCP socket; that gate is correct.
/// What was wrong was what this panel concluded from it: `isRunning` false drew
/// "the CXP server is offline — enable it in Settings → CXP Cross-Probe",
/// blaming a setting that was already on and could never have helped, the peer
/// list stayed permanently empty, and [onSendTo] returned at its first line
/// because there was no server to send through. Meanwhile the **extension
/// host** was a healthy CXP peer the whole time — its own `peer_id`, its own
/// published manifest, its own discovered peers.
///
/// So under an editor host the same four listenables are fed from
/// `editorHostCrossProbeProvider`, which the host pushes into over the existing
/// bridge, and [onSendTo] asks the host to deliver the announcement. The
/// editor-host path is an *alternative source*, not a replacement: nothing
/// below changes what a desktop build does.
class WaveCruxCrossProbePanelController
    implements cxp_ui.CrossProbePanelController {
  /// Creates a controller bound to [_ref] (the host widget's `ref`, scoped to
  /// the active tab). Wires the reactive bridges immediately.
  WaveCruxCrossProbePanelController(this._ref)
    : _hostKind = _ref.read(editorHostKindProvider) {
    if (_hostKind == EditorHostKind.none) {
      _bindToLocalCxpServer();
    } else {
      _bindToEditorHost();
    }
  }

  /// Desktop, mobile, a plain browser tab: this build's own CXP server is the
  /// only possible source, and it is the one that works there.
  void _bindToLocalCxpServer() {
    _peersSub = _ref.listenManual<List<PeerIdentity>>(
      cxpPeersProvider,
      (_, next) => _peers.value = next,
      fireImmediately: true,
    );
    _unreachableSub = _ref.listenManual<List<CxpDialFailure>>(
      cxpDialFailuresProvider,
      (_, next) => _unreachable.value = next,
      fireImmediately: true,
    );
    _runningSub = _ref.listenManual<bool>(
      cxpServerProvider.select((s) => s.isRunning),
      (_, next) => _serverRunning.value = next,
      fireImmediately: true,
    );
    _eventsSub = _ref.listenManual<List<CxpEventLogEntry>>(
      cxpEventLogProvider,
      (_, next) => _events.value = next.map(_toSharedEvent).toList(),
      fireImmediately: true,
    );
  }

  /// A VSCode webview: the extension host is the peer, and it pushes one
  /// snapshot carrying all four values.
  ///
  /// [cxp_ui.CrossProbePanelController.serverRunning] is pinned **true** and
  /// deliberately not wired to the snapshot's `online`. The listenable's only
  /// job is the offline banner, and that banner's text tells the user to
  /// enable a setting in a Settings screen whose CXP section governs *this
  /// build's* server — a server that cannot exist here and whose absence the
  /// user can do nothing about. Showing it would be advice that is impossible
  /// to follow. The honest signal about the host's own peer is the one the
  /// panel already renders: no peers, and whatever the unreachable section
  /// says.
  void _bindToEditorHost() {
    _serverRunning.value = true;
    _crossProbeSub = _ref.listenManual<EditorHostCrossProbeState>(
      editorHostCrossProbeProvider,
      (_, next) => _applyHostState(next),
      fireImmediately: true,
    );
  }

  void _applyHostState(EditorHostCrossProbeState next) {
    _peers.value = next.peers;
    _unreachable.value = next.unreachable;
    _events.value = next.events
        // "Clear events" has nothing local to empty when the log lives in the
        // extension host, and asking the host to forget its own log would
        // clear it for every waveform tab in the window. A watermark clears
        // *this panel's* view and lets the next real event through, which is
        // what the button means.
        .where((e) {
          final clearedAt = _eventsClearedBefore;
          return clearedAt == null || e.timestamp.isAfter(clearedAt);
        })
        .map(_toSharedEvent)
        .toList();
    final failure = next.sendFailure;
    // The host re-pushes its whole snapshot on every peer change, so a
    // failure with no identity would re-fire the toast each time. Correlated
    // on the `message_id` of the send it answers.
    if (failure != null && failure.inReplyTo != _lastSendFailureId) {
      _lastSendFailureId = failure.inReplyTo;
      _reportSendFailure(
        cxp_ui.CrossProbeSendFailure(
          peerLabel: failure.peerLabel,
          reason: failure.reason,
        ),
      );
    }
  }

  final WidgetRef _ref;

  /// Which editor host is driving this build, sampled once at construction.
  ///
  /// Safe to sample rather than watch: the host bridge sets it during
  /// bootstrap, before `runApp`, from a marker the extension's `index.html`
  /// shim froze into `window` before `main.dart.js` executed. It cannot change
  /// while a panel is mounted.
  final EditorHostKind _hostKind;

  /// Set by [onClearEvents] under an editor host. See [_applyHostState].
  DateTime? _eventsClearedBefore;

  /// `message_id` of the last refused send already surfaced as a toast.
  String? _lastSendFailureId;

  final ValueNotifier<List<PeerIdentity>> _peers =
      ValueNotifier<List<PeerIdentity>>(const <PeerIdentity>[]);
  final ValueNotifier<List<cxp_ui.CrossProbeEvent>> _events =
      ValueNotifier<List<cxp_ui.CrossProbeEvent>>(
        const <cxp_ui.CrossProbeEvent>[],
      );
  final ValueNotifier<List<CxpDialFailure>> _unreachable =
      ValueNotifier<List<CxpDialFailure>>(const <CxpDialFailure>[]);
  final ValueNotifier<bool> _serverRunning = ValueNotifier<bool>(false);

  ProviderSubscription<List<PeerIdentity>>? _peersSub;
  ProviderSubscription<List<CxpEventLogEntry>>? _eventsSub;
  ProviderSubscription<List<CxpDialFailure>>? _unreachableSub;
  ProviderSubscription<bool>? _runningSub;

  /// The editor-host path's single subscription — one snapshot carries all
  /// four values, so there is one listener rather than four.
  ProviderSubscription<EditorHostCrossProbeState>? _crossProbeSub;

  @override
  ValueListenable<List<PeerIdentity>> get peers => _peers;

  @override
  ValueListenable<List<cxp_ui.CrossProbeEvent>> get events => _events;

  @override
  ValueListenable<List<CxpDialFailure>> get unreachable => _unreachable;

  @override
  ValueListenable<bool> get serverRunning => _serverRunning;

  @override
  ValueListenable<cxp_ui.CrossProbeSendFailure?> get sendFailure =>
      _sendFailure;

  final ValueNotifier<cxp_ui.CrossProbeSendFailure?> _sendFailure =
      ValueNotifier<cxp_ui.CrossProbeSendFailure?>(null);

  @override
  void onSendTo(PeerIdentity peer) => unawaited(_sendTo(peer));

  /// Resolves the current signal selection and sends it to [peer], then
  /// surfaces a rejected or undelivered send — R8's "never a silent no-op".
  ///
  /// Which wire it goes down is [_hostKind]'s to decide, and the two arms
  /// differ only in the last step:
  ///
  /// * **Desktop** — an ack-bearing `request_highlight` through this
  ///   build's own CXP server. The automatic emitter still broadcasts
  ///   fire-and-forget `notify_selection`; the explicit panel send is directed
  ///   and wants confirmation, so it uses the acked form.
  /// * **Editor host** — a `notify_selection`
  ///   (https://edacrux.app/cxp#sec-9-3) the extension host
  ///   delivers on our behalf, because a webview has no socket to reach a peer
  ///   with. Answered by the host's next cross-probe state frame: the delivered
  ///   send appears in "Recent Events", a refused one as a toast.
  ///
  /// The hierarchical path, the cursor time and the `crux.design_id` are the
  /// same question on both paths and are resolved once, by
  /// [_resolveOutboundSelection]. What is deliberately **not** shared is the
  /// order of the guards: on desktop the reachability check comes before the
  /// path lookup, so a peer that cannot receive anything is reported as
  /// unreachable rather than as "nothing is selected".
  Future<void> _sendTo(PeerIdentity peer) async {
    // Origination is a Pro capability, and this button is a route to it that
    // ships in open core — so the tier is checked HERE, first, before the
    // selection is even resolved. A denied press has already been explained
    // by the gate (the shared upgrade dialog); an unselected row after an
    // admitted press is the existing quiet-no-op-turned-snackbar below, which
    // is a different situation from a refusal.
    if (!_ref.read(crossProbeOriginateGateProvider)(_ref.context)) return;

    // No selection → there is nothing to cross-probe. Tell the user instead of
    // a silent no-op (previously the send resolved an empty selection and
    // dropped it on the floor).
    final signalRef = _ref.read(selectedSignalProvider);
    if (signalRef == null) {
      _showSnackBar((l10n) => l10n.crossProbeSendNoSelection);
      return;
    }

    if (_hostKind != EditorHostKind.none) {
      // No reachability check here: which peers this window has a live link
      // to is the *host's* knowledge, and asking it is the send. A peer it
      // cannot reach comes back as a `send_failure`.
      final resolved = _resolveOutboundSelection(signalRef);
      if (resolved == null) return;
      final messageId = _ref
          .read(editorHostBridgeProvider)
          .postCrossProbeSend(
            peer.peerId,
            NotifySelection(
              elements: <ElementId>[
                ElementId(kind: ElementKind.signal, path: resolved.path),
              ],
              displayName: resolved.path,
              metadata: resolved.metadata,
            ),
          );
      // A disposed bridge is the one way this posts nothing, and it means the
      // webview is going away — there is no user left to tell.
      if (messageId == null) return;
      // Outbound either way, and `honored` is not knowable here: a
      // `notify_selection` has no ack in CXP, and the host's answer is a state
      // push rather than a per-send verdict. Reported as delivered-to-the-host,
      // which is what this build actually did.
      _recordCrossProbe(_ref.read(telemetryServiceProvider), honored: true);
      return;
    }

    final server = _ref.read(cxpServerProvider.notifier).server;
    if (server == null) return;

    // Only peers in the server's REACHABLE set (`connectedPeers` — the same set
    // `broadcast` reaches) can actually receive a direct send. The panel's peer
    // list unions discovered-but-not-connected peers in too, and `sendTo`
    // silently drops a message aimed at one of those. Surface the miss as a
    // snackbar rather than doing nothing.
    final reachable = server.connectedPeers.any(
      (p) => p.peerId == peer.peerId,
    );
    if (!reachable) {
      _showSnackBar(
        (l10n) => l10n.crossProbeSendUnreachable(_peerLabel(peer)),
        isError: true,
      );
      return;
    }

    final resolved = _resolveOutboundSelection(signalRef);
    if (resolved == null) return;

    // Read before the ack wait: the probe is counted whether or not the panel
    // is still open when the ack lands.
    final telemetry = _ref.read(telemetryServiceProvider);
    final result = await server.requestHighlight(
      peer.peerId,
      RequestHighlight(
        element: ElementId(kind: ElementKind.signal, path: resolved.path),
        metadata: resolved.metadata,
      ),
      summary: resolved.path,
    );
    final ack = result.ack;
    if (result.delivered) {
      // Past `delivered`, so a peer that was unreachable is an attempt, not a
      // cross-probe. A missing ack is a timeout — the peer never said yes, so
      // it counts as not honored, the same as an explicit refusal.
      _recordCrossProbe(telemetry, honored: ack?.honored ?? false);
    }
    // The ack wait runs up to five seconds, and the panel can close inside
    // it. Past that point `_ref` belongs to a disposed widget and the
    // failure notifier is disposed, so both would throw.
    if (_disposed) return;
    if (!result.delivered) {
      // The peer passed the reachability check above and went away before
      // the request reached it. It is the same situation, so the user gets
      // the same message — never a silent no-op.
      _showSnackBar(
        (l10n) => l10n.crossProbeSendUnreachable(_peerLabel(peer)),
        isError: true,
      );
      return;
    }
    if (ack == null || !ack.honored) {
      _reportSendFailure(
        cxp_ui.CrossProbeSendFailure(
          peerLabel: _peerLabel(peer),
          reason: ack?.reason,
        ),
      );
    }
  }

  /// Publishes [failure] for the panel to toast. Failures compare by value,
  /// so one equal to the last would not notify the panel and a second failed
  /// send to the same peer would be silent; clearing first makes each count.
  void _reportSendFailure(cxp_ui.CrossProbeSendFailure failure) {
    _sendFailure
      ..value = null
      ..value = failure;
  }

  /// [signalRef] as a peer can understand it, or `null` (having already told
  /// the user why).
  ///
  /// `selectedSignalProvider` holds a backend-local `signalRef` (a wellen u32 /
  /// VCD idcode) — meaningless to a peer. The canonical hierarchical PATH is
  /// what NetCrux and the other peers leaf-match against their own model; a raw
  /// ref matches nothing and the receiver replies "element not found" for every
  /// signal.
  ({String path, Map<String, Object?> metadata})? _resolveOutboundSelection(
    String signalRef,
  ) {
    final source = _ref.read(waveformSourceProvider).value;
    final signalPath = source == null
        ? null
        : fullPathForSignalRef(source, signalRef);
    if (signalPath == null) {
      _showSnackBar((l10n) => l10n.crossProbeSendNoSelection);
      return null;
    }
    final cursorTime = _ref.read(cursorStateProvider).primaryCursorTime;
    final filePath = _ref.read(waveformSourceProvider.notifier).currentFilePath;
    // The reverse-flow tag: a receiver with no matching waveform open
    // can resolve and open this design's dump from it.
    final designId = filePath == null ? null : cxpDesignIdForPath(filePath);
    return (
      path: signalPath,
      metadata: <String, Object?>{
        'wavecrux.cursor_time_fs': ?cursorTime,
        cxpDesignIdMetadataKey: ?designId,
      },
    );
  }

  /// Takes the service rather than reading it, so the desktop arm can read it
  /// before its ack wait, when `_ref` may no longer be usable after.
  static void _recordCrossProbe(
    TelemetryService telemetry, {
    required bool honored,
  }) => telemetry.record(
    TelemetryEvent(
      'cxp.crossprobe',
      properties: <String, Object?>{
        'direction': 'outbound',
        'honored': honored,
      },
    ),
  );

  /// Human-friendly label for [peer] in a snackbar — its product name, or the
  /// raw peer id when the product name is unknown.
  String _peerLabel(PeerIdentity peer) =>
      peer.productName.isEmpty ? peer.peerId : peer.productName;

  /// Surfaces a transient snackbar through the root messenger (the same idiom
  /// the inbound-selection "open a waveform" prompt uses). A no-op when no
  /// messenger is mounted (headless startup) or localization is unavailable.
  void _showSnackBar(
    String Function(L10N l10n) message, {
    bool isError = false,
  }) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null || !messenger.mounted) return;
    final l10n = Localizations.of<L10N>(messenger.context, L10N);
    if (l10n == null) return;
    final colorScheme = Theme.of(messenger.context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message(l10n),
            style: isError
                ? TextStyle(color: colorScheme.onErrorContainer)
                : null,
          ),
          backgroundColor: isError ? colorScheme.errorContainer : null,
          behavior: SnackBarBehavior.floating,
          duration: isError ? kCruxErrorSnackDuration : kCruxInfoSnackDuration,
        ),
      );
  }

  @override
  void onOpenPanel() => _ref
      .read(panelLayoutProvider.notifier)
      .setCrossProbeVisible(
        visible: true,
      );

  @override
  void onClose() => _ref
      .read(panelLayoutProvider.notifier)
      .setCrossProbeVisible(visible: false);

  @override
  void onClearEvents() {
    if (_hostKind == EditorHostKind.none) {
      _ref.read(cxpEventLogProvider.notifier).clear();
      return;
    }
    // The log lives in the extension host, which serves every waveform tab in
    // the window; emptying it there would clear another tab's panel too. The
    // watermark hides what is already shown and lets the next real event
    // through, which is what the button means to the person pressing it.
    _eventsClearedBefore = DateTime.now();
    _applyHostState(_ref.read(editorHostCrossProbeProvider));
  }

  /// Set by [dispose]. A send still awaiting its ack checks it before touching
  /// the widget's `ref` or the notifiers.
  bool _disposed = false;

  /// Releases the bridge subscriptions and backing notifiers.
  void dispose() {
    _disposed = true;
    _peersSub?.close();
    _eventsSub?.close();
    _unreachableSub?.close();
    _runningSub?.close();
    _crossProbeSub?.close();
    _peers.dispose();
    _events.dispose();
    _unreachable.dispose();
    _serverRunning.dispose();
    _sendFailure.dispose();
  }

  /// Maps a WaveCrux [CxpEventLogEntry] onto the shared, richer
  /// [cxp_ui.CrossProbeEvent] — folding the wire `messageKind` + direction into
  /// the panel's semantic categories (including the selection-received
  /// and open-artifact rows the per-app log never modelled).
  cxp_ui.CrossProbeEvent _toSharedEvent(CxpEventLogEntry e) {
    final outbound = e.direction == CxpEventDirection.outbound;
    final direction = outbound
        ? cxp_ui.CrossProbeEventDirection.outbound
        : cxp_ui.CrossProbeEventDirection.inbound;
    final (
      cxp_ui.CrossProbeEventKind kind,
      bool lifecycle,
    ) = switch (e.messageKind) {
      'peer_connected' => (cxp_ui.CrossProbeEventKind.peerConnected, true),
      'peer_disconnected' => (
        cxp_ui.CrossProbeEventKind.peerDisconnected,
        true,
      ),
      CxpMessageKind.notifySelection => (
        outbound
            ? cxp_ui.CrossProbeEventKind.selectionSent
            : cxp_ui.CrossProbeEventKind.selectionReceived,
        false,
      ),
      CxpMessageKind.requestHighlight => (
        outbound
            ? cxp_ui.CrossProbeEventKind.highlightSent
            : cxp_ui.CrossProbeEventKind.highlightReceived,
        false,
      ),
      CxpMessageKind.requestOpenArtifact ||
      CxpMessageKind.requestOpenArtifactAck => (
        cxp_ui.CrossProbeEventKind.openArtifact,
        false,
      ),
      _ => (cxp_ui.CrossProbeEventKind.other, false),
    };
    return cxp_ui.CrossProbeEvent(
      kind: kind,
      direction: lifecycle ? null : direction,
      peerLabel: e.peerLabel,
      timestamp: e.timestamp,
      summary: e.summary,
      messageKind: lifecycle ? null : e.messageKind,
    );
  }
}
