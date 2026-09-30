// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';

/// The cross-probe half of the host-bridge wire contract.
///
/// The claim under test is that a snapshot posted by the extension host
/// arrives as the *same* value types the desktop cross-probe panel already
/// renders — `PeerIdentity`, `CxpDialFailure`, `CxpEventLogEntry` — so the
/// panel's existing mapping runs unchanged, and that nothing malformed can
/// take the panel down with it. A webview's inbound frames are untrusted
/// input in exactly the way a socket peer's are.
void main() {
  Map<String, Object?> peerJson({
    String peerId = 'wavecrux-4242-1700000000000',
    String productName = 'WaveCrux',
  }) => <String, Object?>{
    'peer_id': peerId,
    'product_name': productName,
    'product_version': '0.9.0',
    'capabilities': <Object?>['request_highlight'],
  };

  Map<String, Object?> statePayload({
    Object? online = true,
    List<Object?>? peers,
    List<Object?>? unreachable,
    List<Object?>? events,
    Map<String, Object?>? sendFailure,
  }) => <String, Object?>{
    'online': online,
    'peers': peers ?? <Object?>[peerJson()],
    'unreachable': unreachable ?? <Object?>[],
    'events': events ?? <Object?>[],
    'send_failure': ?sendFailure,
  };

  group('the wire literals', () {
    test('are exactly what the extension host posts', () {
      // Mirrors `CROSS_PROBE_STATE_KIND` / `CROSS_PROBE_SEND_KIND` in
      // crux-vscode's `packages/wavecrux/src/webview/cross-probe.ts`. A
      // rename on one side only fails silently — this build answers
      // `unknown_kind` and the panel stays blind, which is the very bug the
      // frame exists to fix — so both sides pin the literal.
      expect(kHostBridgeCrossProbeStateKind, 'crux.cross_probe_state');
      expect(kHostBridgeCrossProbeSendKind, 'crux.cross_probe_send');
    });
  });

  group('HostBridgeCrossProbeState decoding', () {
    test(
      'is reached through decodeHostBridgePayload, like every other kind',
      () {
        final message = decodeHostBridgePayload(
          kHostBridgeCrossProbeStateKind,
          statePayload(),
        );
        expect(message, isA<HostBridgeCrossProbeState>());
      },
    );

    test('decodes peers with the shared PeerIdentity decoder', () {
      final state = HostBridgeCrossProbeState.tryFromJson(statePayload())!;
      expect(state.online, isTrue);
      expect(
        state.peers.single,
        const PeerIdentity(
          peerId: 'wavecrux-4242-1700000000000',
          productName: 'WaveCrux',
          productVersion: '0.9.0',
          capabilities: <String>{'request_highlight'},
        ),
      );
    });

    test('decodes dial failures into the type the panel already renders', () {
      final state = HostBridgeCrossProbeState.tryFromJson(
        statePayload(
          unreachable: <Object?>[
            <String, Object?>{
              'peer_id': 'netcrux-99-1',
              'host': '127.0.0.1',
              'port': 54400,
              'error': 'connect ECONNREFUSED 127.0.0.1:54400',
              'consecutive_failures': 3,
              'next_retry_after_ticks': 3,
            },
          ],
        ),
      )!;
      final failure = state.unreachable.single;
      expect(failure.peerId, 'netcrux-99-1');
      expect(failure.port, 54400);
      expect(failure.consecutiveFailures, 3);
      expect('${failure.error}', 'connect ECONNREFUSED 127.0.0.1:54400');
    });

    test('decodes events into CxpEventLogEntry, lifecycle kinds included', () {
      final state = HostBridgeCrossProbeState.tryFromJson(
        statePayload(
          events: <Object?>[
            <String, Object?>{
              'message_kind': 'peer_connected',
              'direction': 'inbound',
              'peer_label': 'WaveCrux',
              'timestamp_ms': 1700000000000,
            },
            <String, Object?>{
              'message_kind': CxpMessageKind.notifySelection,
              'direction': 'outbound',
              'peer_label': 'WaveCrux',
              'timestamp_ms': 1700000000100,
              'summary': 'top.clk',
            },
          ],
        ),
      )!;
      expect(state.events, hasLength(2));
      expect(state.events.first.messageKind, 'peer_connected');
      expect(state.events.first.direction, CxpEventDirection.inbound);
      expect(state.events.last.direction, CxpEventDirection.outbound);
      expect(state.events.last.summary, 'top.clk');
      expect(
        state.events.last.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1700000000100),
      );
    });

    test('refuses a frame with no boolean `online`', () {
      // Strict on purpose: `online` is the one field a coercion could invent
      // an answer for, and it is the flag the whole frame exists to report
      // honestly.
      expect(
        HostBridgeCrossProbeState.tryFromJson(statePayload(online: 'yes')),
        isNull,
      );
      expect(
        HostBridgeCrossProbeState.tryFromJson(statePayload(online: null)),
        isNull,
      );
    });

    test('drops an unusable entry rather than failing the whole frame', () {
      // One peer with a malformed identity must not cost the user their
      // whole peer list.
      final state = HostBridgeCrossProbeState.tryFromJson(
        statePayload(
          peers: <Object?>[
            <String, Object?>{'peer_id': 'no-product-name'},
            peerJson(peerId: 'good-1-2'),
            'not a map',
          ],
          events: <Object?>[
            <String, Object?>{'direction': 'inbound'},
            <String, Object?>{
              'message_kind': 'peer_connected',
              'direction': 'inbound',
              'peer_label': 'WaveCrux',
              'timestamp_ms': 1,
            },
          ],
        ),
      )!;
      expect(state.peers.single.peerId, 'good-1-2');
      expect(state.events.single.messageKind, 'peer_connected');
    });

    test('truncates a list above its cap instead of rejecting the frame', () {
      final state = HostBridgeCrossProbeState.tryFromJson(
        statePayload(
          peers: <Object?>[
            for (var i = 0; i < kHostBridgeMaxCrossProbePeers + 20; i++)
              peerJson(peerId: 'peer-$i'),
          ],
          events: <Object?>[
            for (var i = 0; i < kHostBridgeMaxCrossProbeEvents + 20; i++)
              <String, Object?>{
                'message_kind': 'peer_connected',
                'direction': 'inbound',
                'peer_label': 'p$i',
                'timestamp_ms': i,
              },
          ],
        ),
      )!;
      expect(state.peers, hasLength(kHostBridgeMaxCrossProbePeers));
      expect(state.events, hasLength(kHostBridgeMaxCrossProbeEvents));
    });

    test('decodes a send failure and its correlation id', () {
      final state = HostBridgeCrossProbeState.tryFromJson(
        statePayload(
          sendFailure: <String, Object?>{
            'in_reply_to': 'wc-12',
            'peer_label': 'WaveCrux',
            'reason': 'not connected',
          },
        ),
      )!;
      expect(
        state.sendFailure,
        const HostBridgeCrossProbeSendFailure(
          inReplyTo: 'wc-12',
          peerLabel: 'WaveCrux',
          reason: 'not connected',
        ),
      );
    });

    test('ignores a send failure with nothing to correlate on', () {
      // Without an `in_reply_to` the panel could not tell one refusal from
      // the same refusal re-pushed, and would re-fire the toast on every
      // snapshot.
      final state = HostBridgeCrossProbeState.tryFromJson(
        statePayload(
          sendFailure: <String, Object?>{'peer_label': 'WaveCrux'},
        ),
      )!;
      expect(state.sendFailure, isNull);
    });

    test('round-trips through toJson', () {
      final original = HostBridgeCrossProbeState(
        online: true,
        peers: const <PeerIdentity>[
          PeerIdentity(
            peerId: 'wavecrux-1-2',
            productName: 'WaveCrux',
            productVersion: '0.9.0',
          ),
        ],
        unreachable: const <CxpDialFailure>[
          CxpDialFailure(
            peerId: 'netcrux-1-2',
            host: '127.0.0.1',
            port: 1,
            error: 'refused',
            consecutiveFailures: 2,
            nextRetryAfterTicks: 1,
          ),
        ],
        events: <CxpEventLogEntry>[
          CxpEventLogEntry(
            timestamp: DateTime.fromMillisecondsSinceEpoch(5),
            direction: CxpEventDirection.outbound,
            messageKind: CxpMessageKind.notifySelection,
            peerLabel: 'WaveCrux',
            summary: 'top.clk',
          ),
        ],
        sendFailure: const HostBridgeCrossProbeSendFailure(
          inReplyTo: 'wc-1',
          peerLabel: 'WaveCrux',
        ),
      );
      final decoded = HostBridgeCrossProbeState.tryFromJson(original.toJson())!;
      expect(decoded.peers, original.peers);
      expect(decoded.events, original.events);
      expect(decoded.unreachable.single.peerId, 'netcrux-1-2');
      expect(decoded.sendFailure, original.sendFailure);
    });
  });

  group('HostBridgeCrossProbeSend', () {
    test('encodes the target peer beside a notify_selection payload', () {
      const message = HostBridgeCrossProbeSend(
        peerId: 'wavecrux-1-2',
        selection: NotifySelection(
          elements: <ElementId>[
            ElementId(kind: ElementKind.signal, path: 'top.clk'),
          ],
          displayName: 'top.clk',
          metadata: <String, Object?>{'crux.design_id': 'abcdef0123456789'},
        ),
      );
      expect(message.kind, kHostBridgeCrossProbeSendKind);
      final json = message.toJson();
      expect(json['peer_id'], 'wavecrux-1-2');
      // The selection is `crux_cxp`'s own encoding, not a shape invented for
      // the bridge — the host decodes it with the shared CXP decoder.
      expect(
        json['selection'],
        const NotifySelection(
          elements: <ElementId>[
            ElementId(kind: ElementKind.signal, path: 'top.clk'),
          ],
          displayName: 'top.clk',
          metadata: <String, Object?>{'crux.design_id': 'abcdef0123456789'},
        ).toJson(),
      );
    });

    test('is outbound only — a host that posts one down gets unknown_kind', () {
      // No decoder is registered for it, deliberately: a host asking the
      // webview to reach a socket it does not have is not a request this
      // build can honour.
      expect(
        decodeHostBridgePayload(
          kHostBridgeCrossProbeSendKind,
          <String, Object?>{
            'peer_id': 'x',
            'selection': <String, Object?>{'elements': <Object?>[]},
          },
        ),
        isNull,
      );
    });
  });
}
