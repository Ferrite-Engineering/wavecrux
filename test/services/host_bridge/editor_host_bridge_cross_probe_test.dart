// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/host_bridge/editor_host_bridge.dart';
import 'package:wavecrux/services/host_bridge/editor_host_cross_probe_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';

import '../../support/fake_host_bridge_transport.dart';

/// The cross-probe branch of the editor-host bridge, both directions.
///
/// One `_dispatch` branch down (the host's snapshot, recorded and never acted
/// on — what the panel does with it is `cross_probe_panel.dart`'s decision)
/// and one `postCxp`-shaped call up (the panel's directed send). Frames are
/// untrusted `window.postMessage` input, so the refusal behaviour is pinned
/// alongside the happy path.
void main() {
  Map<String, Object?> frameOf(
    String kind,
    Map<String, Object?> payload, {
    String messageId = 'm1',
  }) => <String, Object?>{
    'type': kHostBridgeCxpFrameType,
    'envelope': <String, Object?>{
      'cxp_version': cxpProtocolVersion,
      'message_id': messageId,
      'from': 'vscode.host',
      'kind': kind,
      'payload': payload,
    },
  };

  ({
    ProviderContainer container,
    FakeHostBridgeTransport transport,
    EditorHostBridge bridge,
  })
  makeBridge() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final transport = FakeHostBridgeTransport();
    final bridge = EditorHostBridge(
      ref: container.read(_refProvider),
      channel: transport,
    )..start();
    addTearDown(bridge.dispose);
    return (container: container, transport: transport, bridge: bridge);
  }

  group('inbound crux.cross_probe_state', () {
    test('records the host snapshot into the provider', () async {
      final it = makeBridge();
      await it.bridge.handleFrame(
        frameOf(kHostBridgeCrossProbeStateKind, <String, Object?>{
          'online': true,
          'peers': <Object?>[
            <String, Object?>{
              'peer_id': 'wavecrux-1-2',
              'product_name': 'WaveCrux',
              'product_version': '0.9.0',
              'capabilities': <Object?>['request_highlight'],
            },
          ],
          'events': <Object?>[
            <String, Object?>{
              'message_kind': 'peer_connected',
              'direction': 'inbound',
              'peer_label': 'WaveCrux',
              'timestamp_ms': 1700000000000,
            },
          ],
        }),
      );

      final state = it.container.read(editorHostCrossProbeProvider);
      expect(state.online, isTrue);
      expect(state.peers.single.productName, 'WaveCrux');
      expect(state.events.single.messageKind, 'peer_connected');
    });

    test('is deliberately unacknowledged — it is a push, not a request', () {
      // Same reasoning as the theme and host-session frames: the host has
      // nothing to correlate a reply to, and it re-pushes on every change.
      final it = makeBridge();
      return it.bridge
          .handleFrame(
            frameOf(kHostBridgeCrossProbeStateKind, <String, Object?>{
              'online': false,
            }),
          )
          .then((_) {
            expect(it.transport.posted, isEmpty);
          });
    });

    test('leaves the provider alone when the frame does not decode', () async {
      final it = makeBridge();
      await it.bridge.handleFrame(
        frameOf(kHostBridgeCrossProbeStateKind, <String, Object?>{
          'online': 'yes',
        }),
      );
      expect(
        it.container.read(editorHostCrossProbeProvider),
        EditorHostCrossProbeState.unknown,
      );
      // Silent and total, like every other malformed frame on this bridge:
      // a payload that does not decode is ignored, never partially applied,
      // and never thrown out of. Half a snapshot is not a smaller snapshot —
      // it is a peer list the user would act on and a state that is not
      // true.
      expect(it.transport.posted, isEmpty);
    });
  });

  group('outbound crux.cross_probe_send', () {
    test(
      'posts the target peer beside a notify_selection, and returns its id',
      () {
        final it = makeBridge();
        final messageId = it.bridge.postCrossProbeSend(
          'wavecrux-1-2',
          const NotifySelection(
            elements: <ElementId>[
              ElementId(kind: ElementKind.signal, path: 'top.clk'),
            ],
            displayName: 'top.clk',
          ),
        );

        expect(messageId, isNotNull);
        final envelope = CxpEnvelope.fromJson(
          it.transport.posted.single['envelope']! as Map<String, Object?>,
        );
        expect(envelope.kind, kHostBridgeCrossProbeSendKind);
        // The id the host correlates a refusal on.
        expect(envelope.messageId, messageId);
        expect(envelope.from, kHostBridgePeerId);
        expect(envelope.payload['peer_id'], 'wavecrux-1-2');
        expect(
          (envelope.payload['selection']! as Map<String, Object?>)['elements'],
          <Object?>[
            <String, Object?>{'kind': 'signal', 'path': 'top.clk'},
          ],
        );
      },
    );

    test('posts nothing and returns null once disposed', () {
      final it = makeBridge();
      it.bridge.dispose();
      expect(
        it.bridge.postCrossProbeSend(
          'wavecrux-1-2',
          const NotifySelection(elements: <ElementId>[]),
        ),
        isNull,
      );
      expect(it.transport.posted, isEmpty);
    });
  });
}

final _refProvider = Provider<Ref>((ref) => ref);
