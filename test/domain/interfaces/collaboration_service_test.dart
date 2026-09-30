// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/domain/models/playback_state.dart';

void main() {
  group('ParticipantInfo', () {
    const base = ParticipantInfo(
      id: 'p1',
      displayName: 'Alice',
      colorIndex: 0,
      viewportStart: 0,
      viewportEnd: 1000,
      isHost: true,
    );

    test('equality matches all fields', () {
      const same = ParticipantInfo(
        id: 'p1',
        displayName: 'Alice',
        colorIndex: 0,
        viewportStart: 0,
        viewportEnd: 1000,
        isHost: true,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
    });

    test('equality is sensitive to each field', () {
      expect(base == base.copyWith(id: 'p2'), isFalse);
      expect(base == base.copyWith(displayName: 'Bob'), isFalse);
      expect(base == base.copyWith(colorIndex: 1), isFalse);
      expect(base == base.copyWith(viewportStart: 100), isFalse);
      expect(base == base.copyWith(viewportEnd: 2000), isFalse);
      expect(base == base.copyWith(isHost: false), isFalse);
      expect(base == base.copyWith(waveformContentHash: 'abc'), isFalse);
      expect(base == base.copyWith(joinSequence: 7), isFalse);
    });

    test('joinSequence defaults to 0 and round-trips via copyWith', () {
      expect(base.joinSequence, 0);
      final stamped = base.copyWith(joinSequence: 42);
      expect(stamped.joinSequence, 42);
      // Unspecified copyWith preserves the existing sequence.
      expect(stamped.copyWith(displayName: 'Bob').joinSequence, 42);
    });

    test('oldest-remaining auto-promotion picks the lowest joinSequence', () {
      // Host-assigned monotonic arrival order — never wall-clock. When the host
      // drops, the participant with the smallest joinSequence is promoted.
      final remaining = <ParticipantInfo>[
        base.copyWith(id: 'carol', joinSequence: 3),
        base.copyWith(id: 'bob', joinSequence: 1),
        base.copyWith(id: 'dave', joinSequence: 2),
      ]..sort((a, b) => a.joinSequence.compareTo(b.joinSequence));
      expect(remaining.first.id, 'bob');
      expect(remaining.map((p) => p.id), ['bob', 'dave', 'carol']);
    });

    test('copyWith waveformContentHash round-trip', () {
      expect(base.waveformContentHash, isNull);
      final withHash = base.copyWith(waveformContentHash: 'abc123');
      expect(withHash.waveformContentHash, 'abc123');
      final cleared = withHash.copyWith(clearWaveformContentHash: true);
      expect(cleared.waveformContentHash, isNull);
    });

    test(
      'clearWaveformContentHash wins over a simultaneously supplied value',
      () {
        final withHash = base.copyWith(waveformContentHash: 'abc');
        final cleared = withHash.copyWith(
          waveformContentHash: 'xyz',
          clearWaveformContentHash: true,
        );
        expect(cleared.waveformContentHash, isNull);
      },
    );

    test('copyWith preserves unmodified fields', () {
      final copy = base.copyWith(displayName: 'Bob');
      expect(copy.id, base.id);
      expect(copy.colorIndex, base.colorIndex);
      expect(copy.isHost, base.isHost);
    });

    test('copyWith primaryCursorTime round-trip', () {
      final withCursor = base.copyWith(primaryCursorTime: 500);
      expect(withCursor.primaryCursorTime, 500);
      final cleared = withCursor.copyWith(clearPrimaryCursor: true);
      expect(cleared.primaryCursorTime, isNull);
    });

    test('copyWith secondaryCursorTime round-trip', () {
      final withCursor = base.copyWith(secondaryCursorTime: 750);
      expect(withCursor.secondaryCursorTime, 750);
      final cleared = withCursor.copyWith(clearSecondaryCursor: true);
      expect(cleared.secondaryCursorTime, isNull);
    });

    test('clearPrimaryCursor wins over a simultaneously supplied value', () {
      final cleared = base.copyWith(
        primaryCursorTime: 999,
        clearPrimaryCursor: true,
      );
      expect(cleared.primaryCursorTime, isNull);
    });

    test('is const-constructible', () {
      const a = ParticipantInfo(
        id: 'x',
        displayName: 'X',
        colorIndex: 2,
        viewportStart: 0,
        viewportEnd: 0,
        isHost: false,
      );
      const b = ParticipantInfo(
        id: 'x',
        displayName: 'X',
        colorIndex: 2,
        viewportStart: 0,
        viewportEnd: 0,
        isHost: false,
      );
      expect(a, b);
    });
  });

  group('CollabSessionState', () {
    const base = CollabSessionState(
      sessionId: 's1',
      myParticipantId: 'p1',
      hostId: 'p1',
      participants: [],
      sharedMarkers: {},
    );

    test('equality matches all fields', () {
      const same = CollabSessionState(
        sessionId: 's1',
        myParticipantId: 'p1',
        hostId: 'p1',
        participants: [],
        sharedMarkers: {},
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
    });

    test('equality is sensitive to each field', () {
      expect(base == base.copyWith(sessionId: 's2'), isFalse);
      expect(base == base.copyWith(myParticipantId: 'p2'), isFalse);
      expect(
        base ==
            base.copyWith(
              participants: [
                const ParticipantInfo(
                  id: 'p2',
                  displayName: 'Bob',
                  colorIndex: 1,
                  viewportStart: 0,
                  viewportEnd: 0,
                  isHost: false,
                ),
              ],
            ),
        isFalse,
      );
      expect(base == base.copyWith(sharedMarkers: {'A': 100}), isFalse);
      expect(base == base.copyWith(isRecording: true), isFalse);
      expect(base == base.copyWith(hostId: 'p2'), isFalse);
      expect(base == base.copyWith(presenterId: 'p2'), isFalse);
      expect(
        base == base.copyWith(pendingControlRequests: const ['p2']),
        isFalse,
      );
      expect(
        base ==
            base.copyWith(
              pointers: [
                const CollabPointer(
                  id: 'x',
                  authorId: 'p2',
                  kind: CollabPointerKind.pin,
                  time: 5,
                  rowId: 'top.clk',
                ),
              ],
            ),
        isFalse,
      );
      expect(
        base ==
            base.copyWith(
              presenterTransport: const CollabPlaybackTransport(
                isPlaying: true,
                speed: PlaybackSpeed.duration(10),
                loopMode: PlaybackLoopMode.none,
                anchorTime: 0,
              ),
            ),
        isFalse,
      );
      expect(
        base ==
            base.copyWith(
              incomingScrollRequest: const CollabScrollRequest(
                requesterId: 'p2',
                time: 5,
                rowId: 'top.clk',
              ),
            ),
        isFalse,
      );
    });

    test('pointers default empty and round-trip via copyWith', () {
      expect(base.pointers, isEmpty);
      final withPointer = base.copyWith(
        pointers: [
          const CollabPointer(
            id: 'x',
            authorId: 'p2',
            kind: CollabPointerKind.ping,
            time: 5,
            rowId: 'top.clk',
            ttl: Duration(seconds: 3),
          ),
        ],
      );
      expect(withPointer.pointers, hasLength(1));
      // Unspecified copyWith preserves the existing pointer list.
      expect(withPointer.copyWith(isRecording: true).pointers, hasLength(1));
    });

    test('presenterTransport defaults null and round-trips/clears', () {
      expect(base.presenterTransport, isNull);
      const transport = CollabPlaybackTransport(
        isPlaying: true,
        speed: PlaybackSpeed.duration(5),
        loopMode: PlaybackLoopMode.wholeRange,
        anchorTime: 42,
      );
      final playing = base.copyWith(presenterTransport: transport);
      expect(playing.presenterTransport, transport);
      // Unspecified copyWith preserves it; the explicit clear flag drops it.
      expect(
        playing.copyWith(isRecording: true).presenterTransport,
        transport,
      );
      expect(
        playing.copyWith(clearPresenterTransport: true).presenterTransport,
        isNull,
      );
    });

    test('incomingScrollRequest defaults null and round-trips/clears', () {
      expect(base.incomingScrollRequest, isNull);
      const req = CollabScrollRequest(
        requesterId: 'p2',
        time: 1234,
        rowId: 'top.clk',
      );
      final asked = base.copyWith(incomingScrollRequest: req);
      expect(asked.incomingScrollRequest, req);
      // Unspecified copyWith preserves it; the explicit clear flag drops it.
      expect(asked.copyWith(isRecording: true).incomingScrollRequest, req);
      expect(
        asked.copyWith(clearIncomingScrollRequest: true).incomingScrollRequest,
        isNull,
      );
    });

    test('followTargetId round-trip via copyWith', () {
      final following = base.copyWith(followTargetId: 'p2');
      expect(following.followTargetId, 'p2');
      final stopped = following.copyWith(clearFollowTarget: true);
      expect(stopped.followTargetId, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      final copy = base.copyWith(isRecording: true);
      expect(copy.sessionId, base.sessionId);
      expect(copy.myParticipantId, base.myParticipantId);
    });
  });

  group('CollabSessionState presenter / host roles', () {
    ParticipantInfo p(String id, {int seq = 0}) => ParticipantInfo(
      id: id,
      displayName: id,
      colorIndex: 0,
      viewportStart: 0,
      viewportEnd: 0,
      isHost: id == 'host',
      joinSequence: seq,
    );

    CollabSessionState session({
      String myParticipantId = 'host',
      String hostId = 'host',
      String? presenterId,
      List<String> pending = const [],
    }) => CollabSessionState(
      sessionId: 's',
      myParticipantId: myParticipantId,
      hostId: hostId,
      presenterId: presenterId,
      pendingControlRequests: pending,
      participants: [p('host'), p('bob', seq: 1)],
      sharedMarkers: const {},
    );

    test('presenter defaults to host at session start', () {
      // No explicit presenterId → presenter is the host (the two roles
      // are the same participant until the first handoff).
      final s = session();
      expect(s.presenterId, 'host');
      expect(s.presenter?.id, 'host');
    });

    test('presenterId tracks an explicit assignment (after handoff)', () {
      final s = session(presenterId: 'bob');
      expect(s.presenterId, 'bob');
      expect(s.presenter?.id, 'bob');
      // Host is unchanged — host ≠ presenter once handed off.
      expect(s.hostId, 'host');
      expect(s.isLocalHost, isTrue); // local is 'host'
    });

    test('isLocalPresenter reflects whether the local participant drives', () {
      // Local is the host, presenter defaults to host → local presents.
      expect(session().isLocalPresenter, isTrue);
      // After handoff to bob, the local host no longer presents.
      expect(session(presenterId: 'bob').isLocalPresenter, isFalse);
      // From bob's machine, bob is the presenter.
      expect(
        session(myParticipantId: 'bob', presenterId: 'bob').isLocalPresenter,
        isTrue,
      );
    });

    test('isLocalHost is independent of who presents', () {
      expect(session(presenterId: 'bob').isLocalHost, isTrue);
      expect(
        session(myParticipantId: 'bob', presenterId: 'bob').isLocalHost,
        isFalse,
      );
    });

    test('presenter getter is null when the presenter has left', () {
      final s = session(presenterId: 'ghost');
      expect(s.presenterId, 'ghost');
      expect(s.presenter, isNull);
    });

    test('pending control-requests surface through the state', () {
      expect(session().hasPendingControlRequests, isFalse);
      expect(session().pendingControlRequests, isEmpty);
      final s = session(pending: const ['bob']);
      expect(s.hasPendingControlRequests, isTrue);
      expect(s.pendingControlRequests, ['bob']);
    });

    test('handoff via copyWith updates presenter; equality follows', () {
      final before = session();
      final after = before.copyWith(presenterId: 'bob');
      expect(before.isLocalPresenter, isTrue);
      expect(after.isLocalPresenter, isFalse);
      expect(after.presenterId, 'bob');
      expect(before == after, isFalse);
    });

    test('viewComposition defaults to null and round-trips via copyWith', () {
      final before = session();
      expect(before.viewComposition, isNull);

      const composition = CollabViewComposition(
        fsmTargetPath: 'top.fsm.state',
        panelVisibility: CollabPanelVisibility(stageViewVisible: true),
      );
      final after = before.copyWith(viewComposition: composition);
      expect(after.viewComposition, composition);
      expect(before == after, isFalse);

      // clearViewComposition wins over the positional value.
      final cleared = after.copyWith(
        viewComposition: composition,
        clearViewComposition: true,
      );
      expect(cleared.viewComposition, isNull);
    });
  });

  group('CollabSessionState waveform-identity mismatch', () {
    ParticipantInfo participant(String id, {String? hash}) => ParticipantInfo(
      id: id,
      displayName: id,
      colorIndex: 0,
      viewportStart: 0,
      viewportEnd: 0,
      isHost: false,
      waveformContentHash: hash,
    );

    CollabSessionState withParticipants(List<ParticipantInfo> ps) =>
        CollabSessionState(
          sessionId: 's',
          myParticipantId: 'me',
          hostId: 'me',
          participants: ps,
          sharedMarkers: const {},
        );

    test('no mismatch when all reported hashes agree', () {
      final state = withParticipants([
        participant('me', hash: 'aaa'),
        participant('bob', hash: 'aaa'),
      ]);
      expect(state.reportedWaveformHashes, {'aaa'});
      expect(state.hasWaveformMismatch, isFalse);
    });

    test('mismatch when two distinct hashes are reported', () {
      final state = withParticipants([
        participant('me', hash: 'aaa'),
        participant('bob', hash: 'bbb'),
      ]);
      expect(state.reportedWaveformHashes, {'aaa', 'bbb'});
      expect(state.hasWaveformMismatch, isTrue);
    });

    test('participants with no reported hash never count as a difference', () {
      final state = withParticipants([
        participant('me', hash: 'aaa'),
        participant('bob'), // still loading / streaming — no hash yet
      ]);
      expect(state.reportedWaveformHashes, {'aaa'});
      expect(state.hasWaveformMismatch, isFalse);
    });

    test('no mismatch when nobody has reported a hash', () {
      final state = withParticipants([participant('me'), participant('bob')]);
      expect(state.reportedWaveformHashes, isEmpty);
      expect(state.hasWaveformMismatch, isFalse);
    });
  });

  group('RecordingEvent.toJson', () {
    test('serializes all fields', () {
      final event = RecordingEvent(
        timestamp: DateTime.utc(2026, 1, 1, 12),
        participantId: 'p1',
        displayName: 'Alice',
        type: RecordingEventType.cursorMove,
        data: const {'time': 500},
      );
      final json = event.toJson();
      expect(json['participantId'], 'p1');
      expect(json['displayName'], 'Alice');
      expect(json['type'], 'cursorMove');
      expect((json['data']! as Map)['time'], 500);
      expect(json['timestamp'], contains('2026'));
    });
  });

  group('SessionRecording', () {
    final recording = SessionRecording(
      sessionId: 's1',
      startedAt: DateTime.utc(2026),
      events: [
        RecordingEvent(
          timestamp: DateTime.utc(2026, 1, 1, 0, 1),
          participantId: 'p1',
          displayName: 'Alice',
          type: RecordingEventType.join,
        ),
        RecordingEvent(
          timestamp: DateTime.utc(2026, 1, 1, 0, 2),
          participantId: 'p1',
          displayName: 'Alice',
          type: RecordingEventType.leave,
        ),
      ],
    );

    test('toJson contains sessionId and events array', () {
      final json = recording.toJson();
      expect(json['sessionId'], 's1');
      expect((json['events']! as List).length, 2);
    });

    test('toCsv has header row and one row per event', () {
      final csv = recording.toCsv();
      final lines = csv.trim().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.first, contains('timestamp'));
      expect(lines.length, 3); // header + 2 events
    });

    test('toCsv escapes double-quotes in data', () {
      final r = SessionRecording(
        sessionId: 's2',
        startedAt: DateTime.utc(2026),
        events: [
          RecordingEvent(
            timestamp: DateTime.utc(2026),
            participantId: 'p1',
            displayName: 'Alice',
            type: RecordingEventType.markerAdd,
            data: const {'label': 'it\'s a "test"'},
          ),
        ],
      );
      final csv = r.toCsv();
      expect(csv, contains('""'));
    });
  });

  group('CollabMode', () {
    test('has three values', () {
      expect(CollabMode.values.length, 3);
      expect(
        CollabMode.values,
        containsAll([
          CollabMode.none,
          CollabMode.lan,
          CollabMode.wan,
        ]),
      );
    });
  });

  group('RecordingEventType', () {
    test('has eleven values covering the full lifecycle', () {
      // The three annotation events joined the original eight. The
      // audit trail must not have a hole exactly where the substantive content
      // is — an annotation is the only thing in a session carrying an argument
      // in words.
      expect(RecordingEventType.values.length, 11);
      expect(
        RecordingEventType.values,
        containsAll([
          RecordingEventType.annotationAdd,
          RecordingEventType.annotationEdit,
          RecordingEventType.annotationRemove,
        ]),
      );
    });
  });

  group('CollabPointer (data-anchored pointers)', () {
    const ping = CollabPointer(
      id: 'ptr1',
      authorId: 'bob',
      kind: CollabPointerKind.ping,
      time: 4200,
      rowId: 'top.dut.clk',
      ttl: Duration(seconds: 4),
    );
    const pin = CollabPointer(
      id: 'ptr2',
      authorId: 'carol',
      kind: CollabPointerKind.pin,
      time: 9000,
      rowId: 'top.dut.state',
    );

    test('anchors to data coordinates (time, rowId), never pixels', () {
      expect(ping.time, 4200);
      expect(ping.rowId, 'top.dut.clk');
    });

    test('ping is ephemeral with a TTL; pin is persistent without one', () {
      expect(ping.isEphemeral, isTrue);
      expect(ping.ttl, const Duration(seconds: 4));
      expect(pin.isEphemeral, isFalse);
      expect(pin.ttl, isNull);
    });

    test('equality matches all fields', () {
      const same = CollabPointer(
        id: 'ptr1',
        authorId: 'bob',
        kind: CollabPointerKind.ping,
        time: 4200,
        rowId: 'top.dut.clk',
        ttl: Duration(seconds: 4),
      );
      expect(ping, same);
      expect(ping.hashCode, same.hashCode);
    });

    test('equality is sensitive to each field', () {
      expect(ping == ping.copyWith(id: 'x'), isFalse);
      expect(ping == ping.copyWith(authorId: 'x'), isFalse);
      expect(ping == ping.copyWith(kind: CollabPointerKind.pin), isFalse);
      expect(ping == ping.copyWith(time: 1), isFalse);
      expect(ping == ping.copyWith(rowId: 'x'), isFalse);
      expect(ping == ping.copyWith(ttl: const Duration(seconds: 1)), isFalse);
    });

    test('copyWith clearTtl converts a ping into a persistent pointer', () {
      final cleared = ping.copyWith(clearTtl: true);
      expect(cleared.ttl, isNull);
    });

    test('kind has exactly ping and pin', () {
      expect(CollabPointerKind.values, [
        CollabPointerKind.ping,
        CollabPointerKind.pin,
      ]);
    });
  });

  group('CollabPlaybackTransport (shared playhead)', () {
    const transport = CollabPlaybackTransport(
      isPlaying: true,
      speed: PlaybackSpeed.duration(10),
      loopMode: PlaybackLoopMode.aToB,
      anchorTime: 500,
      loopStart: 100,
      loopEnd: 900,
    );

    test('carries transport state, not frames', () {
      expect(transport.isPlaying, isTrue);
      expect(transport.anchorTime, 500);
      expect(transport.loopMode, PlaybackLoopMode.aToB);
      expect(transport.loopStart, 100);
      expect(transport.loopEnd, 900);
    });

    test('equality matches all fields', () {
      const same = CollabPlaybackTransport(
        isPlaying: true,
        speed: PlaybackSpeed.duration(10),
        loopMode: PlaybackLoopMode.aToB,
        anchorTime: 500,
        loopStart: 100,
        loopEnd: 900,
      );
      expect(transport, same);
      expect(transport.hashCode, same.hashCode);
    });

    test('equality is sensitive to transport fields', () {
      const paused = CollabPlaybackTransport(
        isPlaying: false,
        speed: PlaybackSpeed.duration(10),
        loopMode: PlaybackLoopMode.aToB,
        anchorTime: 500,
        loopStart: 100,
        loopEnd: 900,
      );
      const movedAnchor = CollabPlaybackTransport(
        isPlaying: true,
        speed: PlaybackSpeed.duration(10),
        loopMode: PlaybackLoopMode.aToB,
        anchorTime: 600,
        loopStart: 100,
        loopEnd: 900,
      );
      expect(transport == paused, isFalse);
      expect(transport == movedAnchor, isFalse);
    });

    test('non-loop transport leaves A–B bounds null', () {
      const t = CollabPlaybackTransport(
        isPlaying: false,
        speed: PlaybackSpeed.duration(10),
        loopMode: PlaybackLoopMode.none,
        anchorTime: 0,
      );
      expect(t.loopStart, isNull);
      expect(t.loopEnd, isNull);
    });
  });

  group('CollabScrollRequest (off-screen ask-to-scroll)', () {
    const req = CollabScrollRequest(
      requesterId: 'bob',
      time: 4200,
      rowId: 'top.core.clk',
    );

    test('carries the requester and data-anchored target', () {
      expect(req.requesterId, 'bob');
      expect(req.time, 4200);
      expect(req.rowId, 'top.core.clk');
    });

    test('equality matches all fields', () {
      const same = CollabScrollRequest(
        requesterId: 'bob',
        time: 4200,
        rowId: 'top.core.clk',
      );
      expect(req, same);
      expect(req.hashCode, same.hashCode);
    });

    test('equality is sensitive to each field', () {
      expect(
        req ==
            const CollabScrollRequest(
              requesterId: 'al',
              time: 4200,
              rowId: 'top.core.clk',
            ),
        isFalse,
      );
      expect(
        req ==
            const CollabScrollRequest(
              requesterId: 'bob',
              time: 9,
              rowId: 'top.core.clk',
            ),
        isFalse,
      );
      expect(
        req ==
            const CollabScrollRequest(
              requesterId: 'bob',
              time: 4200,
              rowId: 'top.other',
            ),
        isFalse,
      );
    });
  });

  group('CollabJoinRequest', () {
    test('is a value type — the door queue de-dups and compares by value', () {
      const a = CollabJoinRequest(participantId: 'bob', displayName: 'Bob');
      const b = CollabJoinRequest(participantId: 'bob', displayName: 'Bob');
      const differentName = CollabJoinRequest(
        participantId: 'bob',
        displayName: 'Bobby',
      );
      const differentId = CollabJoinRequest(
        participantId: 'carol',
        displayName: 'Bob',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == differentName, isFalse);
      expect(a == differentId, isFalse);
    });
  });

  group('CollabSessionState admission', () {
    const base = CollabSessionState(
      sessionId: 's',
      myParticipantId: 'me',
      hostId: 'me',
      participants: [],
      sharedMarkers: {},
    );

    test('defaults to approved with an empty door queue', () {
      // The default is what the host and every already-admitted client are, so
      // a state built without mentioning admission is a state in the room.
      expect(base.admission, CollabAdmission.approved);
      expect(base.pendingJoinRequests, isEmpty);
      expect(base.hasPendingJoinRequests, isFalse);
      expect(base.isAwaitingAdmission, isFalse);
    });

    test('reports waiting at the door', () {
      final waiting = base.copyWith(
        admission: CollabAdmission.awaitingApproval,
      );
      expect(waiting.isAwaitingAdmission, isTrue);
    });

    test('copyWith carries both admission fields independently', () {
      final withQueue = base.copyWith(
        pendingJoinRequests: const [
          CollabJoinRequest(participantId: 'bob', displayName: 'Bob'),
        ],
      );
      expect(withQueue.hasPendingJoinRequests, isTrue);
      expect(withQueue.admission, CollabAdmission.approved);

      final waiting = base.copyWith(
        admission: CollabAdmission.awaitingApproval,
      );
      expect(waiting.pendingJoinRequests, isEmpty);
    });

    test('equality and hashCode take both fields into account', () {
      final queued = base.copyWith(
        pendingJoinRequests: const [
          CollabJoinRequest(participantId: 'bob', displayName: 'Bob'),
        ],
      );
      final waiting = base.copyWith(
        admission: CollabAdmission.awaitingApproval,
      );

      expect(queued == base, isFalse);
      expect(waiting == base, isFalse);
      expect(queued.hashCode == base.hashCode, isFalse);
      expect(waiting.hashCode == base.hashCode, isFalse);
    });
  });
}
