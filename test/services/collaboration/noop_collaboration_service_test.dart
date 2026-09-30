// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/domain/models/playback_state.dart';
import 'package:wavecrux/services/collaboration/noop_collaboration_service.dart';

void main() {
  group('NoopCollaborationService', () {
    const service = NoopCollaborationService();

    test('is const-constructible (singleton-friendly)', () {
      const a = NoopCollaborationService();
      const b = NoopCollaborationService();
      expect(identical(a, b), isTrue);
    });

    test('isInSession is false', () {
      expect(service.isInSession, isFalse);
    });

    test('isHost is false', () {
      expect(service.isHost, isFalse);
    });

    test('activeMode is none', () {
      expect(service.activeMode, CollabMode.none);
    });

    test('createSession returns empty string without throwing', () async {
      final code = await service.createSession(
        displayName: 'Alice',
        mode: CollabMode.wan,
      );
      expect(code, '');
    });

    test(
      'joinSession completes without throwing (WAN / LAN-mDNS / LAN-manual)',
      () async {
        await expectLater(
          service.joinSession(roomCode: 'ABC123', displayName: 'Bob'),
          completes,
        );
        // LAN auto-discovery (no room code, no host) and LAN manual host both
        // no-op cleanly on the open-core default.
        await expectLater(
          service.joinSession(roomCode: '', displayName: 'Bob'),
          completes,
        );
        await expectLater(
          service.joinSession(
            roomCode: '',
            displayName: 'Bob',
            lanHost: '192.168.1.42',
          ),
          completes,
        );
      },
    );

    test('leaveSession completes without throwing', () async {
      await expectLater(service.leaveSession(), completes);
    });

    test('sessionState is an empty stream that closes immediately', () async {
      final events = await service.sessionState.toList();
      expect(events, isEmpty);
    });

    test('pushCursorUpdate does not throw', () {
      service
        ..pushCursorUpdate(100, 200)
        ..pushCursorUpdate(null, null);
    });

    test('pushViewportUpdate does not throw', () {
      service.pushViewportUpdate(0, 1000);
    });

    test('updateWaveformIdentity does not throw', () {
      service
        ..updateWaveformIdentity('deadbeef')
        ..updateWaveformIdentity(null);
    });

    test('addSharedMarker completes without throwing', () async {
      await expectLater(service.addSharedMarker('A', 500), completes);
    });

    test('removeSharedMarker completes without throwing', () async {
      await expectLater(service.removeSharedMarker('A'), completes);
    });

    test('setFollowTarget does not throw', () {
      service
        ..setFollowTarget('p2')
        ..setFollowTarget(null);
    });

    test('handoffPresenter does not throw', () {
      service.handoffPresenter('p2');
    });

    test('requestPresenter does not throw', () {
      service.requestPresenter();
    });

    test('respondToPresenterRequest (grant and deny) does not throw', () {
      service
        ..respondToPresenterRequest('p2', true)
        ..respondToPresenterRequest('p2', false);
    });

    test('pushPlaybackTransport does not throw', () {
      service.pushPlaybackTransport(
        const CollabPlaybackTransport(
          isPlaying: true,
          speed: PlaybackSpeed.duration(10),
          loopMode: PlaybackLoopMode.none,
          anchorTime: 0,
        ),
      );
    });

    test('addPointer / removePointer do not throw', () {
      service
        ..addPointer(
          const CollabPointer(
            id: 'ptr1',
            authorId: 'me',
            kind: CollabPointerKind.ping,
            time: 100,
            rowId: 'top.clk',
            ttl: Duration(seconds: 3),
          ),
        )
        ..removePointer('ptr1');
    });

    test('requestPresenterScroll / dismissScrollRequest do not throw', () {
      service
        ..requestPresenterScroll(100, 'top.clk')
        ..dismissScrollRequest();
    });

    test('updateViewComposition does not throw', () {
      service.updateViewComposition(const CollabViewComposition());
    });

    test('exportRecording returns empty SessionRecording', () async {
      final recording = await service.exportRecording();
      expect(recording.events, isEmpty);
      expect(recording.sessionId, '');
    });

    test('onUserInteraction setter accepts and ignores callback', () {
      // Setter-only — no observable effect on the noop; just must not throw.
      (service as dynamic)
        ..onUserInteraction = () {}
        ..onUserInteraction = null;
    });
  });
}
