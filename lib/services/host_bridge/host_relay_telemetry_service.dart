// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The telemetry service a webview-hosted build resolves: a relay, not a sender.
//
// ### Why the webview must not be a sender
//
// A VSCode extension is bound by `vscode.env.isTelemetryEnabled` — the user's
// single, editor-wide answer. host-core applies it at send time and is the only
// thing in the pack that transmits. If the Dart half kept its own pipeline it
// would answer to `crux_telemetry`'s consent store instead, and a user who
// turned telemetry off in VSCode would still be reported on by the panel inside
// it. That is not a bug that gets filed; it is the finding that gets an
// extension pulled from the Marketplace.
//
// So under an editor host this replaces `telemetryServiceProvider` outright.
// The live service is never constructed, the on-disk queue is never opened, the
// ingestion endpoint is never resolved, and there is no code path from a
// `record()` call to an HTTP request. `wavecrux_telemetry_overrides.dart` binds
// it; `test/services/host_bridge/host_relay_telemetry_service_test.dart` and
// `test/features/telemetry/wavecrux_telemetry_overrides_test.dart` assert the
// absence of traffic rather than the presence of this class name.
//
// ### What crosses, and what does not
//
// Only `{name, properties}` — the event descriptor. The envelope is host-core's
// to assemble, which is what makes `installation_id`, `os`, `form_factor` and
// the license tier unspoofable from here: a webview never constructs one. The
// host stamps `form_factor: 'vscode'` itself, which is the same answer
// `telemetryFormFactorFor` gives for `EditorHostKind.vscode` — the two agree by
// construction rather than by coincidence, and the Dart-side mapping remains
// the honest answer for any envelope this build ever assembles itself.
//
// host-core treats what arrives here as **untrusted**: `recordFromWebview`
// re-validates the descriptor against the same closed vocabularies it applies
// to its own events. Nothing about this class is a trust boundary.

import 'package:crux_telemetry/crux_telemetry.dart'
    show TelemetryEvent, TelemetryService;
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';

/// [TelemetryService] that hands every event to the extension host and keeps
/// none of it.
class HostRelayTelemetryService implements TelemetryService {
  /// Relays through [channel].
  const HostRelayTelemetryService(this.channel);

  /// The bridge transport. When it cannot post — a host whose shim has not
  /// published the outbound seam — events are dropped.
  ///
  /// Dropping is the correct failure. The alternative, falling back to this
  /// build's own sender, is precisely the behaviour the host gate exists to
  /// prevent, and it would appear only in the configuration nobody tests.
  final HostBridgeTransport channel;

  @override
  void record(TelemetryEvent event) {
    // `HostBridgeChannel.post` never throws — telemetry must not break a
    // feature flow, and this method is called from ordinary UI paths.
    channel.post(hostBridgeTelemetryFrame(event));
  }
}
