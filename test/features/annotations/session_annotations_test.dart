// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The open-core seam for collaborative annotations.
//
// The Pro overlay publishes and receives; this is the part of C4 that lives in
// open core: one composed set the renderer draws, and the colour rule that
// separates "what I wrote" from "what the room said".
//
// THE RULE THIS FILE EXISTS FOR: a participant's pre-existing LOCAL notes keep
// the neutral theme colour. If joining a session recoloured somebody's
// week-old private notes into their participant colour, everybody in the room
// would read them as things said in this meeting.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/collaborator_palette.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';

Annotation _note({
  required String id,
  int time = 100,
  int? colorRgb,
  String author = '',
}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: 'top.bus'),
  authorName: author,
  createdAt: DateTime.utc(2026, 8, 13),
  text: 'note $id',
  colorRgb: colorRgb,
);

ParticipantInfo _participant(
  String id,
  int colorIndex, {
  bool isHost = false,
}) => ParticipantInfo(
  id: id,
  displayName: id == 'me' ? 'Me' : id[0].toUpperCase() + id.substring(1),
  colorIndex: colorIndex,
  joinSequence: colorIndex,
  viewportStart: 0,
  viewportEnd: 1000,
  isHost: isHost,
);

CollabSessionState _session({
  List<CollabAnnotation> annotations = const [],
  List<CollabWritingNote> writing = const [],
}) => CollabSessionState(
  sessionId: 'S',
  myParticipantId: 'me',
  hostId: 'me',
  participants: [
    _participant('me', 0, isHost: true),
    _participant('bob', 3),
    _participant('ravi', 5),
  ],
  sharedMarkers: const {},
  annotations: annotations,
  writingAnnotation: writing,
);

/// Async because [collaborationSessionStateProvider] is a `StreamProvider`: its
/// first value lands on a microtask, so a synchronous read would see
/// `AsyncLoading` and every session assertion would pass vacuously against an
/// empty list.
Future<ProviderContainer> _container({
  List<Annotation> local = const [],
  CollabSessionState? session,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (session != null)
        collaborationSessionStateProvider.overrideWith(
          (ref) => Stream.value(session),
        ),
    ],
  );
  addTearDown(container.dispose);
  container
    ..listen(annotationsProvider, (_, _) {})
    ..listen(collaborationSessionStateProvider, (_, _) {});
  local.forEach(container.read(annotationsProvider.notifier).add);
  if (session != null) {
    await container.read(collaborationSessionStateProvider.future);
  }
  return container;
}

void main() {
  group('composition', () {
    test('with no session, the composed set IS the local list', () async {
      final local = [_note(id: 'a')];
      final container = await _container(local: local);

      expect(container.read(visibleAnnotationsProvider), hasLength(1));
      expect(
        container.read(visibleAnnotationsProvider),
        same(container.read(annotationsProvider)),
        reason:
            'identical, not merely equal — an open-core build must not rebuild '
            'anything downstream because C4 exists',
      );
    });

    test('session notes join the local ones', () async {
      final container = await _container(
        local: [_note(id: 'mine')],
        session: _session(
          annotations: [
            CollabAnnotation(
              authorId: 'bob',
              annotation: _note(id: 'bobs'),
            ),
          ],
        ),
      );

      final ids = container
          .read(visibleAnnotationsProvider)
          .map((a) => a.id)
          .toSet();
      expect(ids, {'mine', 'bobs'});
    });

    test('a note that is both local and on the wire appears once', () async {
      // Your own session notes come back on the host's authoritative snapshot.
      // The local copy wins: it is the one you are editing.
      final container = await _container(
        local: [_note(id: 'x', colorRgb: 0xFF112233)],
        session: _session(
          annotations: [
            CollabAnnotation(
              authorId: 'me',
              annotation: _note(id: 'x'),
            ),
          ],
        ),
      );

      final composed = container.read(visibleAnnotationsProvider);
      expect(composed, hasLength(1));
      expect(composed.single.colorRgb, 0xFF112233);
    });

    test('an empty session list changes nothing', () async {
      final container = await _container(
        local: [_note(id: 'a')],
        session: _session(),
      );
      expect(container.read(visibleAnnotationsProvider), hasLength(1));
    });
  });

  group('the colour rule', () {
    test("a session note takes its author's palette slot", () async {
      final container = await _container(
        session: _session(
          annotations: [
            CollabAnnotation(
              authorId: 'bob',
              annotation: _note(id: 'b'),
            ),
          ],
        ),
      );

      // An INDEX, not a colour: the state layer stays free of `dart:ui` and
      // the overlay does the resolving, because the palette lives in the
      // viewer's widget layer and the import-layering guard refuses a
      // provider reaching across for it.
      expect(container.read(sessionAnnotationColorIndexProvider), {'b': 3});
      expect(
        collaboratorColor(3),
        isNot(collaboratorColor(5)),
        reason: 'the palette must actually distinguish the two slots',
      );
    });

    test('two authors get two slots', () async {
      final container = await _container(
        session: _session(
          annotations: [
            CollabAnnotation(
              authorId: 'bob',
              annotation: _note(id: 'b'),
            ),
            CollabAnnotation(
              authorId: 'ravi',
              annotation: _note(id: 'r'),
            ),
          ],
        ),
      );

      expect(container.read(sessionAnnotationColorIndexProvider), {
        'b': 3,
        'r': 5,
      });
    });

    test('LOCAL notes never appear in the map', () async {
      // The rule this file exists for. Absent from the map means the overlay
      // leaves the note's own colour alone — a participant colour here would
      // make the room read a week-old private note as something said in this
      // meeting.
      final container = await _container(
        local: [_note(id: 'week-old')],
        session: _session(
          annotations: [
            CollabAnnotation(
              authorId: 'bob',
              annotation: _note(id: 'b'),
            ),
          ],
        ),
      );

      final map = container.read(sessionAnnotationColorIndexProvider);
      expect(map.containsKey('week-old'), isFalse);
      expect(map.containsKey('b'), isTrue);
      // …and the composed note itself is untouched.
      expect(
        container
            .read(visibleAnnotationsProvider)
            .firstWhere((a) => a.id == 'week-old')
            .colorRgb,
        isNull,
      );
    });

    test('a note from a participant who has left has no slot', () async {
      // Nothing to resolve, so nothing is invented — the note keeps whatever
      // colour it already carried.
      final container = await _container(
        session: _session(
          annotations: [
            CollabAnnotation(
              authorId: 'departed',
              annotation: _note(id: 'g', colorRgb: 0xFF445566),
            ),
          ],
        ),
      );

      expect(container.read(sessionAnnotationColorIndexProvider), isEmpty);
      expect(
        container.read(visibleAnnotationsProvider).single.colorRgb,
        0xFF445566,
      );
    });

    test('the map is empty with no session', () async {
      final container = await _container(local: [_note(id: 'a')]);
      expect(container.read(sessionAnnotationColorIndexProvider), isEmpty);
    });
  });

  group('ordering', () {
    test('the composed set sorts by tick across both sources', () async {
      final container = await _container(
        local: [_note(id: 'local-late', time: 900)],
        session: _session(
          annotations: [
            CollabAnnotation(
              authorId: 'bob',
              annotation: _note(id: 'session-early'),
            ),
          ],
        ),
      );

      expect(
        container
            .read(visibleAnnotationsInTimeOrderProvider)
            .map((a) => a.id)
            .toList(),
        ['session-early', 'local-late'],
      );
    });
  });

  group('the writing chip', () {
    test('names other participants who are composing', () async {
      final container = await _container(
        session: _session(
          writing: [const CollabWritingNote(participantId: 'bob')],
        ),
      );
      expect(_writerNames(container), ['Bob']);
    });

    test(
      'never names you — being told you are typing is not information',
      () async {
        final container = await _container(
          session: _session(
            writing: const [
              CollabWritingNote(participantId: 'me'),
              CollabWritingNote(participantId: 'ravi'),
            ],
          ),
        );
        expect(_writerNames(container), ['Ravi']);
      },
    );

    test('is empty with no session', () async {
      final container = await _container();
      expect(_writerNames(container), isEmpty);
    });

    test('resolves the anchor and the author’s palette slot', () async {
      // Both halves are what makes a chip drawable: the anchor decides where,
      // the slot decides whose colour. Without them the canvas has a name and
      // nothing to do with it.
      final container = await _container(
        session: _session(
          writing: const [
            CollabWritingNote(
              participantId: 'ravi',
              time: 640,
              rowId: 'top.bus',
            ),
          ],
        ),
      );

      final chips = container.read(writingAnnotationChipsProvider);
      expect(chips, hasLength(1));
      expect(chips.single.name, 'Ravi');
      expect(chips.single.time, 640);
      expect(chips.single.rowId, 'top.bus');
      expect(chips.single.colorIndex, 5);
    });

    test('drops an announcement from outside the roster', () async {
      // The same posture the rest of the session state takes toward
      // unattributable frames: a chip we cannot name is a chip we cannot draw.
      final container = await _container(
        session: _session(
          writing: const [CollabWritingNote(participantId: 'stranger')],
        ),
      );
      expect(container.read(writingAnnotationChipsProvider), isEmpty);
    });
  });

  group('the wire type', () {
    test('carries a participant id alongside the open-core annotation', () {
      // Rights key on the *participant* id, not on the display name the
      // annotation carries: two people called "Martin" must not inherit each
      // other's notes, and a name persists in documents long after a session.
      final wrapped = CollabAnnotation(
        authorId: 'p1',
        annotation: _note(id: 'a', author: 'Martin'),
      );

      expect(wrapped.id, 'a');
      expect(wrapped.authorId, 'p1');
      expect(wrapped.annotation.authorName, 'Martin');
    });

    test('is a value type', () {
      final a = CollabAnnotation(
        authorId: 'p',
        annotation: _note(id: 'x'),
      );
      final b = CollabAnnotation(
        authorId: 'p',
        annotation: _note(id: 'x'),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(authorId: 'q'), isNot(b));
    });
  });

  group('the session state', () {
    test('defaults to no annotations and nobody writing', () {
      const state = CollabSessionState(
        sessionId: 'S',
        myParticipantId: 'me',
        hostId: 'me',
        participants: [],
        sharedMarkers: {},
      );
      expect(state.annotations, isEmpty);
      expect(state.writingAnnotation, isEmpty);
    });

    test('carries both through copyWith and equality', () {
      final base = _session();
      final withNotes = base.copyWith(
        annotations: [
          CollabAnnotation(
            authorId: 'bob',
            annotation: _note(id: 'b'),
          ),
        ],
        writingAnnotation: const [CollabWritingNote(participantId: 'ravi')],
      );

      expect(withNotes.annotations, hasLength(1));
      expect(withNotes.writingAnnotation, [
        const CollabWritingNote(participantId: 'ravi'),
      ]);
      expect(withNotes, isNot(base));
    });
  });
}

/// The names the writing chips print, in order.
List<String> _writerNames(ProviderContainer container) => [
  for (final chip in container.read(writingAnnotationChipsProvider)) chip.name,
];
