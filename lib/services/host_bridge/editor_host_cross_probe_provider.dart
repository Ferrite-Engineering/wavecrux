// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';

part 'editor_host_cross_probe_provider.g.dart';

/// The cross-probe state an editor host has pushed down the bridge.
///
/// The editor-host counterpart of `cxpPeersProvider` + `cxpDialFailuresProvider`
/// + `cxpEventLogProvider` + `cxpServerProvider.isRunning` — the four sources
/// the cross-probe panel renders from on desktop, which inside a VSCode webview
/// are all structurally empty because this build has no CXP server there and
/// cannot have one (no `dart:io`, no listening socket).
///
/// Under an editor host the extension host **is** the peer, so these values
/// come from it. See [kHostBridgeCrossProbeStateKind].
@immutable
class EditorHostCrossProbeState {
  /// Creates a snapshot.
  const EditorHostCrossProbeState({
    required this.online,
    this.peers = const <PeerIdentity>[],
    this.unreachable = const <CxpDialFailure>[],
    this.events = const <CxpEventLogEntry>[],
    this.sendFailure,
  });

  /// Before the host has said anything.
  ///
  /// `online: false` is the conservative default and it is *not* what draws
  /// the offline banner — the panel suppresses that banner outright under an
  /// editor host, because a webview's own CXP server being stopped is a
  /// permanent, correct fact that a user cannot and should not act on. This
  /// flag only reports whether the **host's** peer is up.
  static const EditorHostCrossProbeState unknown = EditorHostCrossProbeState(
    online: false,
  );

  /// Whether the host's CXP peer is listening.
  final bool online;

  /// Peers the host has discovered.
  final List<PeerIdentity> peers;

  /// Peers the host discovered and could not dial.
  final List<CxpDialFailure> unreachable;

  /// The host's cross-probe event log, oldest-first.
  final List<CxpEventLogEntry> events;

  /// The most recent send the host refused, or `null`.
  final HostBridgeCrossProbeSendFailure? sendFailure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditorHostCrossProbeState &&
          other.online == online &&
          listEquals(other.peers, peers) &&
          listEquals(other.events, events) &&
          other.sendFailure == sendFailure &&
          _sameFailures(other.unreachable, unreachable));

  @override
  int get hashCode => Object.hash(
    online,
    Object.hashAll(peers),
    Object.hashAll(events),
    Object.hashAll(unreachable.map((f) => f.peerId)),
    sendFailure,
  );

  @override
  String toString() =>
      'EditorHostCrossProbeState(online: $online, ${peers.length} peers, '
      '${unreachable.length} unreachable, ${events.length} events)';

  /// `CxpDialFailure` has no `==`, so identity would make every push a
  /// change. Compared on the fields the panel actually renders.
  static bool _sameFailures(
    List<CxpDialFailure> a,
    List<CxpDialFailure> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].peerId != b[i].peerId ||
          a[i].host != b[i].host ||
          a[i].port != b[i].port ||
          '${a[i].error}' != '${b[i].error}' ||
          a[i].consecutiveFailures != b[i].consecutiveFailures) {
        return false;
      }
    }
    return true;
  }
}

/// The host-supplied cross-probe state, or [EditorHostCrossProbeState.unknown].
///
/// `keepAlive` and root-scoped, exactly like `editorHostSessionProvider` and
/// for the same reason: the frames arrive on the one bridge, which is
/// root-scoped, and a per-tab copy would be `unknown` in every tab but
/// whichever happened to be mounted when a push landed.
@Riverpod(keepAlive: true)
class EditorHostCrossProbeNotifier extends _$EditorHostCrossProbeNotifier {
  @override
  EditorHostCrossProbeState build() => EditorHostCrossProbeState.unknown;

  /// Records what the host said. Idempotent — the host pushes on change, but
  /// a re-push of an identical snapshot (a reconnect, a context release and
  /// rebuild) must not rebuild the panel.
  void set(EditorHostCrossProbeState next) {
    if (state == next) return;
    state = next;
  }
}
