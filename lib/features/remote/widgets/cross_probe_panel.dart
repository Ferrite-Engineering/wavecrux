// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' as cxp_ui;
import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxToasts;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/host_bridge/editor_host_cross_probe_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

/// What the user has selected in the active tab, as a cross-probe selection:
/// the selected signal's hierarchical path with the cursor time and the
/// design id a receiver needs to open this design's waveform. Null when no
/// signal is selected or the waveform cannot name it.
///
/// [read] is `ref.read` of a widget scoped to the active tab, so the
/// per-tab providers resolve to the focused tab.
cxp_ui.CrossProbeSelection? resolveWaveCruxCrossProbeSelection(
  cxp_ui.CruxCxpReader read,
) {
  final signalRef = read(selectedSignalProvider);
  if (signalRef == null) return null;
  final source = read(waveformSourceProvider).value;
  final signalPath = source == null
      ? null
      : fullPathForSignalRef(source, signalRef);
  if (signalPath == null) return null;
  return waveCruxSignalSelection(read, signalPath);
}

/// A cross-probe selection naming the signal at [fullPath] in the active
/// tab: what a signal row's "Cross-probe to" menu sends.
///
/// The hierarchical path is what the other products leaf-match against their
/// own model. A backend-local `signalRef` means nothing to a peer, so it
/// never goes on the wire.
cxp_ui.CrossProbeSelection waveCruxSignalSelection(
  cxp_ui.CruxCxpReader read,
  String fullPath,
) {
  final cursorTime = read(cursorStateProvider).primaryCursorTime;
  final filePath = read(waveformSourceProvider.notifier).currentFilePath;
  // The reverse-flow tag: a receiver with no matching waveform open can
  // resolve and open this design's dump from it.
  final designId = filePath == null ? null : cxpDesignIdForPath(filePath);
  return cxp_ui.CrossProbeSelection(
    candidates: <ElementId>[
      ElementId(kind: ElementKind.signal, path: fullPath),
    ],
    displayName: fullPath,
    metadata: <String, Object?>{
      'wavecrux.cursor_time_fs': ?cursorTime,
      cxpDesignIdMetadataKey: ?designId,
    },
  );
}

/// WaveCrux's docked cross-probe panel.
///
/// Outside an editor host the panel is the suite-shared
/// [cxp_ui.CruxCrossProbePanel], bound to the shared CXP runtime. Inside a
/// VSCode webview there is no socket to bind and the extension host is the
/// peer, so the panel renders the same widget over a controller fed from the
/// host bridge.
///
/// Rendered inside the active tab's `ProviderScope`, so per-tab providers
/// (cursor, waveform source, panel layout) resolve to the focused tab; the
/// root-scoped CXP runtime resolves via child-scope fall-through.
class WaveCruxCrossProbePanel extends ConsumerStatefulWidget {
  /// Creates the docked cross-probe panel.
  const WaveCruxCrossProbePanel({super.key});

  @override
  ConsumerState<WaveCruxCrossProbePanel> createState() =>
      _WaveCruxCrossProbePanelState();
}

class _WaveCruxCrossProbePanelState
    extends ConsumerState<WaveCruxCrossProbePanel> {
  WaveCruxCrossProbePanelController? _hostController;

  @override
  void initState() {
    super.initState();
    if (ref.read(editorHostKindProvider) != EditorHostKind.none) {
      _hostController = WaveCruxCrossProbePanelController(
        ref,
        nothingSelectedMessage: () =>
            cxp_ui.cruxCxpStringsOf(context, ref.read).outcomeNothingSelected,
      );
    }
  }

  @override
  void dispose() {
    _hostController?.dispose();
    super.dispose();
  }

  void _close() => ref
      .read(panelLayoutProvider.notifier)
      .setCrossProbeVisible(visible: false);

  @override
  Widget build(BuildContext context) {
    final host = _hostController;
    if (host == null) {
      return cxp_ui.CruxCrossProbePanel(
        selection: () => resolveWaveCruxCrossProbeSelection(ref.read),
        onClose: _close,
      );
    }
    // Docked as a CruxDock tab: the strip already carries the icon, the
    // label and the close button, so the panel's own header would duplicate
    // all three directly underneath (the bound panel above has none by
    // default).
    return cxp_ui.CrossProbePanel(
      controller: host,
      showHeader: false,
      strings: cxp_ui.cruxCxpStringsOf(context, ref.read).panel,
    );
  }
}

/// Adapts the editor host's cross-probe state onto the app-agnostic
/// [cxp_ui.CrossProbePanelController] the shared panel renders against, for a
/// VSCode webview.
///
/// A webview has no `dart:io` and cannot bind a TCP socket, so the shared
/// runtime never starts there. The **extension host** is a healthy CXP peer
/// the whole time, with its own `peer_id`, its own published manifest and its
/// own discovered peers. The host pushes one snapshot over the bridge carrying
/// peers, unreachable peers, events and the last send failure, and this
/// controller exposes them; [onSendTo] asks the host to deliver the
/// announcement, because the webview has no socket to reach a peer with.
///
/// * [onClose] / [onOpenPanel] toggle the per-tab `crossProbeVisible` flag.
/// * [onClearEvents] hides what is shown with a watermark and lets the next
///   real event through, because the log lives in the extension host, which
///   serves every waveform tab in the window.
class WaveCruxCrossProbePanelController
    implements cxp_ui.CrossProbePanelController {
  /// Creates a controller bound to [_ref] (the host widget's `ref`, scoped to
  /// the active tab). Wires the editor-host bridge immediately.
  ///
  /// [nothingSelectedMessage] is the localized "select something first" text,
  /// read when a send finds no selection.
  WaveCruxCrossProbePanelController(
    this._ref, {
    required String Function() nothingSelectedMessage,
  }) : _nothingSelectedMessage = nothingSelectedMessage {
    _bindToEditorHost();
  }

  final WidgetRef _ref;
  final String Function() _nothingSelectedMessage;

  /// A VSCode webview: the extension host is the peer, and it pushes one
  /// snapshot carrying all four values.
  ///
  /// [cxp_ui.CrossProbePanelController.serverRunning] is pinned **true** and
  /// deliberately not wired to the snapshot's `online`. The listenable's only
  /// job is the offline banner, and that banner's text tells the user to
  /// enable a setting in a Settings screen whose CXP section governs *this
  /// build's* server, a server that cannot exist here and whose absence the
  /// user can do nothing about. The signal about the host's own peer is the
  /// one the panel already renders: no peers, and whatever the unreachable
  /// section says.
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

  /// Set by [onClearEvents]. See [_applyHostState].
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
  final ValueNotifier<cxp_ui.CrossProbeSendFailure?> _sendFailure =
      ValueNotifier<cxp_ui.CrossProbeSendFailure?>(null);

  /// The editor-host path's single subscription: one snapshot carries all
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

  @override
  void onSendTo(PeerIdentity peer) => unawaited(_sendTo(peer));

  /// Resolves the current signal selection and asks the extension host to
  /// deliver it to [peer] as a `notify_selection`
  /// (https://edacrux.app/cxp#sec-9-3). Answered by the host's next
  /// cross-probe state frame: the delivered send appears in "Recent events",
  /// a refused one as a toast.
  ///
  /// No reachability check here: which peers this window has a live link to
  /// is the *host's* knowledge, and asking it is the send. A peer it cannot
  /// reach comes back as a `send_failure`.
  ///
  /// Sending is free in every tier, as receiving is: there is no tier check
  /// on this path.
  Future<void> _sendTo(PeerIdentity peer) async {
    final selection = resolveWaveCruxCrossProbeSelection(_ref.read);
    if (selection == null) {
      CruxToasts.showInfo(_nothingSelectedMessage());
      return;
    }
    final messageId = _ref
        .read(editorHostBridgeProvider)
        .postCrossProbeSend(
          peer.peerId,
          NotifySelection(
            elements: selection.candidates,
            displayName: selection.displayName,
            metadata: selection.metadata,
          ),
        );
    // A disposed bridge is the one way this posts nothing, and it means the
    // webview is going away: there is no user left to tell.
    if (messageId == null) return;
    // Outbound, and `honored` is not knowable here: a `notify_selection` has
    // no ack in CXP, and the host's answer is a state push rather than a
    // per-send verdict. Reported as delivered-to-the-host, which is what this
    // build actually did.
    _ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'cxp.crossprobe',
            properties: const <String, Object?>{
              'direction': 'outbound',
              'honored': true,
            },
          ),
        );
  }

  /// Publishes [failure] for the panel to toast. Failures compare by value,
  /// so one equal to the last would not notify the panel and a second failed
  /// send to the same peer would be silent; clearing first makes each count.
  void _reportSendFailure(cxp_ui.CrossProbeSendFailure failure) {
    _sendFailure
      ..value = null
      ..value = failure;
  }

  @override
  void onOpenPanel() => _ref
      .read(panelLayoutProvider.notifier)
      .setCrossProbeVisible(visible: true);

  @override
  void onClose() => _ref
      .read(panelLayoutProvider.notifier)
      .setCrossProbeVisible(visible: false);

  @override
  void onClearEvents() {
    // The log lives in the extension host, which serves every waveform tab in
    // the window; emptying it there would clear another tab's panel too. The
    // watermark hides what is already shown and lets the next real event
    // through, which is what the button means to the person pressing it.
    _eventsClearedBefore = DateTime.now();
    _applyHostState(_ref.read(editorHostCrossProbeProvider));
  }

  /// Releases the bridge subscription and backing notifiers.
  void dispose() {
    _crossProbeSub?.close();
    _peers.dispose();
    _events.dispose();
    _unreachable.dispose();
    _serverRunning.dispose();
    _sendFailure.dispose();
  }

  /// Maps a WaveCrux [CxpEventLogEntry] onto the shared, richer
  /// [cxp_ui.CrossProbeEvent], folding the wire `messageKind` + direction into
  /// the panel's semantic categories (including the selection-received
  /// and open-artifact rows the host's log never modelled).
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
