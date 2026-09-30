// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/collaborator_cursor_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/collaboration/noop_collaboration_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

// ── fake TimeMapper notifier ──────────────────────────────────────────────────

class _FakeTimeMapperNotifier extends TimeMapperNotifier {
  _FakeTimeMapperNotifier(this._mapper);
  final TimeMapper _mapper;

  @override
  TimeMapper build() => _mapper;
}

// ── fake CollaborationService ─────────────────────────────────────────────────

/// A fake that exposes a caller-supplied stream as [sessionState].
class _FakeCollaborationService implements CollaborationService {
  _FakeCollaborationService(this._stream);

  final Stream<CollabSessionState?> _stream;

  @override
  bool get hasRecordedEvents => false;
  @override
  Stream<CollabSessionState?> get sessionState => _stream;

  @override
  Future<String> createSession({
    required String displayName,
    required CollabMode mode,
  }) async => '';

  @override
  Future<void> joinSession({
    required String roomCode,
    required String displayName,
    String? lanHost,
  }) async {}

  @override
  Future<void> leaveSession() async {}

  @override
  CollabJoinOutcome get lastJoinOutcome => CollabJoinOutcome.none;

  @override
  void respondToJoinRequest(String participantId, bool approve) {}

  @override
  void dismissUnreadableFramesNotice() {}

  @override
  String? get sessionInvite => null;

  @override
  void pushCursorUpdate(int? primaryTime, int? secondaryTime) {}

  @override
  void pushViewportUpdate(int startTime, int endTime) {}

  @override
  void updateWaveformIdentity(String? contentHash) {}

  @override
  Future<void> addSharedMarker(String name, int time) async {}

  @override
  Future<void> removeSharedMarker(String name) async {}

  @override
  void setFollowTarget(String? participantId) {}

  @override
  void handoffPresenter(String participantId) {}

  @override
  void requestPresenter() {}

  @override
  void respondToPresenterRequest(String participantId, bool grant) {}

  @override
  void pushPlaybackTransport(CollabPlaybackTransport transport) {}

  @override
  void addPointer(CollabPointer pointer) {}

  @override
  void removePointer(String pointerId) {}

  @override
  void addAnnotation(CollabAnnotation annotation) {}

  @override
  void updateAnnotation(CollabAnnotation annotation) {}

  @override
  void removeAnnotation(String annotationId) {}

  @override
  void setWritingAnnotation({
    required bool writing,
    int? time,
    String? rowId,
  }) {}

  @override
  void dismissRemovedAnnotationNotice() {}

  @override
  void requestPresenterScroll(int time, String rowId) {}

  @override
  void dismissScrollRequest() {}
  @override
  void updateViewComposition(CollabViewComposition composition) {}

  @override
  Future<SessionRecording> exportRecording() async => SessionRecording(
    sessionId: '',
    startedAt: DateTime.fromMillisecondsSinceEpoch(0),
    events: const [],
  );

  @override
  bool get isInSession => true;

  @override
  bool get isHost => false;

  @override
  CollabMode get activeMode => CollabMode.none;

  @override
  // Setter-only matches the CollaborationService interface contract; no getter exists.
  set onUserInteraction(void Function()? callback) {}
}

// ── fixtures ──────────────────────────────────────────────────────────────────

/// Viewport: ticks 0–10000 visible (fitAll, 800 px wide).
final _kMapper = TimeMapper.fitAll(
  startTime: 0,
  endTime: 10000,
  viewportWidth: 800,
);

/// Narrow viewport: shows ticks 0–4000 (5 ticks/px × 800 px).
/// Tick 9000 maps to pixel 1800 — outside the 800 px viewport.
final _kNarrowMapper = TimeMapper.fitAll(
  startTime: 0,
  endTime: 4000,
  viewportWidth: 800,
);

/// Degenerate mapper with `ticksPerPixel == 0`, only reachable via the direct
/// const constructor (every factory floors it to ≥ 1e-6). Its visible range
/// collapses to a single tick (`visibleStartTime == visibleEndTime == 0`), so a
/// cursor at tick 0 *passes* the viewport-visibility gate, yet `timeToPixel(0)`
/// is `0 / 0 == NaN`. This reproduces the precondition for the silent Windows
/// (ANGLE/Direct3D) renderer crash the `!x.isFinite` paint guard defends against.
const _kDegenerateMapper = TimeMapper(
  startTime: 0,
  endTime: 0,
  viewportWidth: 800,
  ticksPerPixel: 0,
  panOffsetTicks: 0,
);

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _wrap({
  CollaborationService? service,
  TimeMapper? mapper,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    // Override the service; collaborationSessionStateProvider derives from it.
    collaborationServiceProvider.overrideWithValue(
      service ?? const NoopCollaborationService(),
    ),
    timeMapperProvider.overrideWith(
      () => _FakeTimeMapperNotifier(mapper ?? _kMapper),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: const Scaffold(
      body: SizedBox(
        width: 800,
        height: 400,
        child: CollaboratorCursorOverlay(),
      ),
    ),
  ),
);

CollabSessionState _session({
  String myId = 'p1',
  List<ParticipantInfo> participants = const [],
}) => CollabSessionState(
  sessionId: 's1',
  myParticipantId: myId,
  hostId: myId,
  participants: participants,
  sharedMarkers: const {},
);

ParticipantInfo _participant({
  required String id,
  int? primaryCursorTime,
}) => ParticipantInfo(
  id: id,
  displayName: id,
  colorIndex: 0,
  viewportStart: 0,
  viewportEnd: 10000,
  isHost: false,
  primaryCursorTime: primaryCursorTime,
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── locale sweep ──────────────────────────────────────────────────────────────

  group('CollaboratorCursorOverlay — locale sweep', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders without exception — $locale', (tester) async {
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── no session ────────────────────────────────────────────────────────────────

  group('CollaboratorCursorOverlay — no active session', () {
    testWidgets('renders nothing when noop service emits empty stream', (
      tester,
    ) async {
      // NoopCollaborationService.sessionState == Stream.empty() →
      // collaborationSessionStateProvider stays AsyncLoading → overlay is SizedBox.shrink().
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CollaboratorCursorOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('renders nothing when stream emits an error', (tester) async {
      final svc = _FakeCollaborationService(
        Stream.error(Exception('relay unreachable')),
      );
      await tester.pumpWidget(_wrap(service: svc));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CollaboratorCursorOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });

  // ── no remote participants ────────────────────────────────────────────────────

  group('CollaboratorCursorOverlay — session with no remote participants', () {
    testWidgets('renders nothing when participant list is empty', (
      tester,
    ) async {
      final svc = _FakeCollaborationService(Stream.value(_session()));
      await tester.pumpWidget(_wrap(service: svc));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CollaboratorCursorOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'renders nothing when all remote participants have null cursor',
      (tester) async {
        final svc = _FakeCollaborationService(
          Stream.value(
            _session(participants: [_participant(id: 'p2')]),
          ),
        );
        await tester.pumpWidget(_wrap(service: svc));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(CollaboratorCursorOverlay),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('renders nothing when only participant is the local user', (
      tester,
    ) async {
      final svc = _FakeCollaborationService(
        Stream.value(
          _session(
            participants: [_participant(id: 'p1', primaryCursorTime: 1000)],
          ),
        ),
      );
      await tester.pumpWidget(_wrap(service: svc));
      await tester.pump();

      // Local participant is filtered out — no remote cursors remain.
      expect(
        find.descendant(
          of: find.byType(CollaboratorCursorOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });

  // ── remote cursor visible ─────────────────────────────────────────────────────

  group('CollaboratorCursorOverlay — remote cursor in viewport', () {
    testWidgets(
      'renders CustomPaint when remote participant has cursor in view',
      (tester) async {
        final svc = _FakeCollaborationService(
          Stream.value(
            _session(
              participants: [_participant(id: 'p2', primaryCursorTime: 4000)],
            ),
          ),
        );
        await tester.pumpWidget(_wrap(service: svc));
        await tester.pump();

        // RepaintBoundary + IgnorePointer + CustomPaint should be in the tree.
        expect(
          find.descendant(
            of: find.byType(CollaboratorCursorOverlay),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders CustomPaint for multiple remote participants', (
      tester,
    ) async {
      final svc = _FakeCollaborationService(
        Stream.value(
          _session(
            participants: [
              _participant(id: 'p2', primaryCursorTime: 2000),
              _participant(id: 'p3', primaryCursorTime: 6000),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrap(service: svc));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CollaboratorCursorOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });
  });

  // ── out-of-viewport clipping ──────────────────────────────────────────────────

  group('CollaboratorCursorOverlay — out-of-viewport cursor', () {
    testWidgets('renders nothing when all remote cursors are outside viewport', (
      tester,
    ) async {
      // _kNarrowMapper shows ticks 0–4000; cursor at 9000 → outside visible range.
      final svc = _FakeCollaborationService(
        Stream.value(
          _session(
            participants: [_participant(id: 'p2', primaryCursorTime: 9000)],
          ),
        ),
      );
      await tester.pumpWidget(_wrap(service: svc, mapper: _kNarrowMapper));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CollaboratorCursorOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });

  // ── non-finite coordinate guard (Windows silent-crash regression) ─────────────

  group('CollaboratorCursorOverlay — non-finite cursor coordinate', () {
    testWidgets(
      'paints without throwing when a degenerate mapper yields a NaN x',
      (tester) async {
        // A directly-constructed zero-ticksPerPixel mapper makes timeToPixel(0)
        // == NaN for a cursor that still passes the visibility gate. Without the
        // `!x.isFinite` skip the painter would draw a line/label at a non-finite
        // coordinate — tolerated by macOS Metal, fatal to the Windows renderer.
        final svc = _FakeCollaborationService(
          Stream.value(
            _session(
              participants: [_participant(id: 'p2', primaryCursorTime: 0)],
            ),
          ),
        );
        await tester.pumpWidget(
          _wrap(service: svc, mapper: _kDegenerateMapper),
        );
        await tester.pump();

        // The build-level gate lets the cursor through (it sits on the collapsed
        // visible range), so the CustomPaint is mounted …
        expect(
          find.descendant(
            of: find.byType(CollaboratorCursorOverlay),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        // … but the paint pass must skip the non-finite coordinate cleanly.
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── presenter cursor distinction ─────────────────────────────────────

  group('CollaboratorCursorOverlay — presenter distinction', () {
    CollabSessionState presenterSession() => const CollabSessionState(
      sessionId: 's1',
      myParticipantId: 'p1',
      // host (and therefore default presenter) is the remote participant p2.
      hostId: 'p2',
      participants: [
        ParticipantInfo(
          id: 'p2',
          displayName: 'Bob',
          colorIndex: 0,
          viewportStart: 0,
          viewportEnd: 10000,
          isHost: true,
          primaryCursorTime: 4000,
        ),
      ],
      sharedMarkers: {},
    );

    testWidgets('overlay forwards the presenterId to its painter', (
      tester,
    ) async {
      final svc = _FakeCollaborationService(Stream.value(presenterSession()));
      await tester.pumpWidget(_wrap(service: svc));
      await tester.pump();

      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(CollaboratorCursorOverlay),
          matching: find.byType(CustomPaint),
        ),
      );
      final painter = paint.painter! as CollaboratorCursorPainter;
      expect(painter.presenterId, 'p2');
    });

    test(
      'presenter cursor paints more coverage (halo) than a follower cursor',
      () async {
        // The presenter gets a wide low-alpha halo + a bolder line + a ▶ badge,
        // so its painted footprint is strictly larger than the same participant's
        // when it is not presenting.
        const participant = ParticipantInfo(
          id: 'p2',
          displayName: 'Bob',
          colorIndex: 0,
          viewportStart: 0,
          viewportEnd: 10000,
          isHost: true,
          primaryCursorTime: 4000,
        );
        const style = TextStyle(fontSize: 10);

        final asPresenter = await _paintedPixels(
          CollaboratorCursorPainter(
            participants: const [participant],
            presenterId: 'p2',
            timeMapper: _kMapper,
            labelStyle: style,
          ),
        );
        final asFollower = await _paintedPixels(
          CollaboratorCursorPainter(
            participants: const [participant],
            presenterId: 'someone-else',
            timeMapper: _kMapper,
            labelStyle: style,
          ),
        );

        expect(asPresenter, greaterThan(asFollower));
      },
    );

    test('shouldRepaint reacts to a presenter change', () {
      const style = TextStyle(fontSize: 10);
      final base = CollaboratorCursorPainter(
        participants: const [],
        presenterId: 'p2',
        timeMapper: _kMapper,
        labelStyle: style,
      );
      final samePresenter = CollaboratorCursorPainter(
        participants: const [],
        presenterId: 'p2',
        timeMapper: _kMapper,
        labelStyle: style,
      );
      final newPresenter = CollaboratorCursorPainter(
        participants: const [],
        presenterId: 'p3',
        timeMapper: _kMapper,
        labelStyle: style,
      );

      expect(base.shouldRepaint(samePresenter), isFalse);
      expect(base.shouldRepaint(newPresenter), isTrue);
    });
  });

  // ── pointer event isolation ───────────────────────────────────────────────────

  group('CollaboratorCursorOverlay — pointer event isolation', () {
    testWidgets('IgnorePointer wraps the CustomPaint', (tester) async {
      final svc = _FakeCollaborationService(
        Stream.value(
          _session(
            participants: [_participant(id: 'p2', primaryCursorTime: 4000)],
          ),
        ),
      );
      await tester.pumpWidget(_wrap(service: svc));
      await tester.pump();

      // There should be exactly one IgnorePointer inside the overlay.
      final ignorePointerInOverlay = find.descendant(
        of: find.byType(CollaboratorCursorOverlay),
        matching: find.byType(IgnorePointer),
      );
      expect(ignorePointerInOverlay, findsOneWidget);

      // That IgnorePointer must contain the CustomPaint.
      expect(
        find.descendant(
          of: ignorePointerInOverlay,
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });
  });
}

/// Paints [painter] into an offscreen 800×400 image and returns the number of
/// pixels with any opacity — a deterministic measure of painted footprint.
Future<int> _paintedPixels(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(800, 400);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = (await image.toByteData())!;
  var count = 0;
  for (var i = 3; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint8(i) > 0) count++;
  }
  image.dispose();
  picture.dispose();
  return count;
}
