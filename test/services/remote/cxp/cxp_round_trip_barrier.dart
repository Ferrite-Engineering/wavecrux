// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// In-band synchronization barrier for CXP socket tests.
//
// Replaces the "sleep and hope" pattern after fire-and-forget sends
// (`Subscribe` has no ack in the v1 protocol) with a deterministic
// round-trip: the server's per-connection read loop is FIFO, so once the
// reply to a probe sent AFTER a `Subscribe` arrives, the subscription is
// guaranteed registered.

import 'package:crux_cxp/crux_cxp.dart';

int _probeCounter = 0;

class _BarrierProbe extends CxpMessage {
  const _BarrierProbe(this._kind);

  final String _kind;

  @override
  String get kind => _kind;

  @override
  Map<String, Object?> toJson() => const <String, Object?>{};
}

/// Round-trip barrier: returns once the server has processed every
/// message [client] sent before this call.
///
/// Sends a unique unknown-kind probe and awaits the matching
/// `ErrorResponse(unknown_kind)` (the server names the offending kind in
/// the error message, so concurrent barriers can't cross-match). The v1
/// protocol has no `SubscribeAck`; this is the deterministic equivalent.
Future<void> cxpRoundTripBarrier(
  LocalCxpClient client, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final probeKind = 'wavecrux_test_barrier_${_probeCounter++}';
  final reply = client.inbound.firstWhere((inbound) {
    final message = inbound.message;
    return message is ErrorResponse &&
        message.code == CxpErrorCode.unknownKind &&
        message.message.contains(probeKind);
  });
  client.send(_BarrierProbe(probeKind));
  await reply.timeout(timeout);
}
