// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/collaboration/providers/follow_detached_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/shared_pointer_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── fakes ──────────────────────────────────────────────────────────────────

/// Exposes a fixed [sessionState] and records [removePointer] calls.
class _FakeCollaborationService implements CollaborationService {
  _FakeCollaborationService(this._stream);

  final Stream<CollabSessionState?> _stream;
  final List<String> removed = [];
  final List<(int, String)> scrollRequests = [];

  @override
  bool get hasRecordedEvents => false;
  @override
  Stream<CollabSessionState?> get sessionState => _stream;

  @override
  void removePointer(String pointerId) => removed.add(pointerId);

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
  void requestPresenterScroll(int time, String rowId) =>
      scrollRequests.add((time, rowId));

  @override
  void dismissScrollRequest() {}
  @override
  void updateViewComposition(CollabViewComposition composition) {}

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
  set onUserInteraction(void Function()? callback) {}
}

/// One signal whose stable path is `top.clk`, so a pointer anchored to that
/// rowId maps to a real lane.
class _SignalsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [
      SignalEntry.signal(
        signalRef: 'clk',
        displayName: 'clk',
        signalPath: 'top.clk',
      ),
    ],
  );
}

// ── fixtures ──────────────────────────────────────────────────────────────────

const _me = 'me';
const _bob = 'bob';

CollabSessionState _session(List<CollabPointer> pointers) => CollabSessionState(
  sessionId: 's',
  myParticipantId: _me,
  hostId: _bob,
  participants: const [
    ParticipantInfo(
      id: _bob,
      displayName: 'Bob',
      colorIndex: 1,
      viewportStart: 0,
      viewportEnd: 10000,
      isHost: true,
    ),
    ParticipantInfo(
      id: _me,
      displayName: 'Me',
      colorIndex: 2,
      viewportStart: 0,
      viewportEnd: 10000,
      isHost: false,
    ),
  ],
  sharedMarkers: const {},
  pointers: pointers,
);

CollabPointer _ping({
  String id = 'ping1',
  String author = _bob,
  int time = 5000,
  Duration ttl = const Duration(seconds: 4),
}) => CollabPointer(
  id: id,
  authorId: author,
  kind: CollabPointerKind.ping,
  time: time,
  rowId: 'top.clk',
  ttl: ttl,
);

CollabPointer _pin({
  String id = 'pin1',
  String author = _bob,
  int time = 4000,
}) => CollabPointer(
  id: id,
  authorId: author,
  kind: CollabPointerKind.pin,
  time: time,
  rowId: 'top.clk',
);

/// Builds the overlay over a real (mutable) time-mapper initialised to
/// `[0, 10000]` at 800 px (fit-all → 12.5 ticks/px), returning the container so
/// tests can pan/zoom and re-pump.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required CollabSessionState session,
  required _FakeCollaborationService service,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: [
      collaborationServiceProvider.overrideWithValue(service),
      signalGroupsProvider.overrideWith(_SignalsNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  // Keep the time-mapper alive so reading `.notifier` to initialise it does not
  // leave Riverpod's auto-dispose scheduler timer pending at test end.
  final keepAlive = container.listen(timeMapperProvider, (_, _) {});
  addTearDown(keepAlive.close);
  container
      .read(timeMapperProvider.notifier)
      .initialize(
        startTime: 0,
        endTime: 10000,
        viewportWidth: 800,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: SharedPointerOverlay(scrollOffset: 0),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  group('SharedPointerOverlay — no session / no pointers', () {
    testWidgets('renders nothing when there are no pointers', (tester) async {
      final service = _FakeCollaborationService(
        Stream.value(_session(const [])),
      );
      await _pump(tester, session: _session(const []), service: service);
      expect(find.byType(Positioned), findsNothing);
    });
  });

  group('SharedPointerOverlay — data anchoring (X tracks pan/zoom)', () {
    testWidgets('a pin re-maps its X from (time) when the viewport zooms', (
      tester,
    ) async {
      final service = _FakeCollaborationService(
        Stream.value(_session([_pin(time: 2000)])),
      );
      final container = await _pump(
        tester,
        session: _session([_pin(time: 2000)]),
        service: service,
      );

      final pin = find.byKey(const ValueKey('pin-pin1'));
      expect(pin, findsOneWidget);
      final dxBefore = tester.getTopLeft(pin).dx;

      // Zoom to [1500, 2500]: tick 2000 moves from pixel 160 to pixel 400.
      container.read(timeMapperProvider.notifier).zoomToRange(1500, 2500);
      await tester.pump();

      final dxAfter = tester.getTopLeft(pin).dx;
      // The anchor tracked the zoom: Δx ≈ 400 − 160 = 240 px.
      expect(dxAfter - dxBefore, closeTo(240, 2));
    });

    testWidgets('a pin anchored to a known signal sits on that lane', (
      tester,
    ) async {
      final service = _FakeCollaborationService(
        Stream.value(_session([_pin(time: 2000)])),
      );
      await _pump(
        tester,
        session: _session([_pin(time: 2000)]),
        service: service,
      );
      // Row 'top.clk' has top 0, height 30 → centre y = 15; the pin icon is
      // drawn just above that anchor (top = y − iconSize), so it lands on the
      // first lane, not the canvas origin.
      final dy = tester.getTopLeft(find.byKey(const ValueKey('pin-pin1'))).dy;
      expect(dy, lessThan(30));
    });
  });

  group('SharedPointerOverlay — ping TTL fade', () {
    testWidgets('a ping fades out and is removed after its TTL', (
      tester,
    ) async {
      final service = _FakeCollaborationService(
        Stream.value(_session([_ping()])),
      );
      await _pump(
        tester,
        session: _session([_ping()]),
        service: service,
      );

      expect(find.byKey(const ValueKey('ping-ping1')), findsOneWidget);

      // Advance past the TTL: the ping fully fades and stops rendering.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('ping-ping1')), findsNothing);
    });

    test('pingOpacity fades linearly and clamps', () {
      const ttl = Duration(seconds: 4);
      expect(pingOpacity(Duration.zero, ttl), 1.0);
      expect(pingOpacity(const Duration(seconds: 2), ttl), closeTo(0.5, 1e-9));
      expect(pingOpacity(const Duration(seconds: 4), ttl), 0.0);
      expect(pingOpacity(const Duration(seconds: 9), ttl), 0.0);
      expect(pingOpacity(const Duration(seconds: 1), Duration.zero), 0.0);
    });
  });

  group('SharedPointerOverlay — author-only pin delete', () {
    testWidgets('the delete affordance shows only for the local author', (
      tester,
    ) async {
      final pointers = [
        _pin(id: 'mine', author: _me),
        _pin(id: 'theirs', time: 6000),
      ];
      final service = _FakeCollaborationService(
        Stream.value(_session(pointers)),
      );
      await _pump(tester, session: _session(pointers), service: service);

      // Exactly one delete affordance (for the locally-authored pin).
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(service.removed, ['mine']);
    });
  });

  group('SharedPointerOverlay — off-screen affordance', () {
    testWidgets('a pointer outside the viewport surfaces an edge affordance', (
      tester,
    ) async {
      // Off-screen means outside the VIEWPORT, not outside the trace. The
      // fixture used to sit at tick 50000 on a `[0, 10000]` trace, which only
      // read as off-screen because the viewport could be scrolled off the end
      // of the data — it no longer can be. So the local view is zoomed into
      // the first fifth and the pointer sits at 9000, inside the trace and
      // outside what this follower is looking at, which is the situation the
      // affordance exists for.
      final pointers = [_pin(id: 'far', time: 9000)];
      final service = _FakeCollaborationService(
        Stream.value(_session(pointers)),
      );
      final container = await _pump(
        tester,
        session: _session(pointers),
        service: service,
      );
      container.read(timeMapperProvider.notifier).zoomToRange(0, 2000);
      await tester.pump();

      expect(find.byKey(const ValueKey('offscreen-far')), findsOneWidget);
      // The author's name surfaces in the directional affordance.
      expect(find.text('Bob is pointing'), findsOneWidget);
      // … and the on-canvas pin marker is NOT drawn (it is off-screen).
      expect(find.byKey(const ValueKey('pin-far')), findsNothing);
    });
  });

  group('SharedPointerOverlay — off-screen affordance interaction', () {
    testWidgets('"Jump to pointer" scrolls to it locally and detaches', (
      tester,
    ) async {
      final pointers = [_pin(id: 'far', time: 9000)];
      final service = _FakeCollaborationService(
        Stream.value(_session(pointers)),
      );
      final container = await _pump(
        tester,
        session: _session(pointers),
        service: service,
      );
      container.read(timeMapperProvider.notifier).zoomToRange(0, 2000);
      await tester.pump();
      expect(find.byKey(const ValueKey('offscreen-far')), findsOneWidget);

      // Open the edge affordance menu and pick "Jump to pointer".
      await tester.tap(find.byKey(const ValueKey('offscreen-far')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jump to pointer'));
      await tester.pump();

      // The viewport jumped so the once-off-screen pin now renders on-canvas,
      // and the local follower detached so the jump is not snapped back.
      expect(find.byKey(const ValueKey('pin-far')), findsOneWidget);
      expect(find.byKey(const ValueKey('offscreen-far')), findsNothing);
      expect(container.read(followDetachedProvider), isTrue);

      // Cancel the detach idle-auto-resume timer so it is not left pending at
      // teardown.
      container.read(followDetachedProvider.notifier).resume();
    });

    testWidgets(
      '"Ask presenter to scroll" requests the presenter scroll there',
      (tester) async {
        final pointers = [_pin(id: 'far', time: 9000)];
        final service = _FakeCollaborationService(
          Stream.value(_session(pointers)),
        );
        final container = await _pump(
          tester,
          session: _session(pointers),
          service: service,
        );
        container.read(timeMapperProvider.notifier).zoomToRange(0, 2000);
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('offscreen-far')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ask presenter to scroll'));
        await tester.pump();

        expect(service.scrollRequests, [(9000, 'top.clk')]);
      },
    );

    testWidgets('the presenter sees no "ask presenter to scroll" item', (
      tester,
    ) async {
      // Local participant IS the presenter (host defaults to presenter).
      final session = CollabSessionState(
        sessionId: 's',
        myParticipantId: _me,
        hostId: _me,
        participants: const [
          ParticipantInfo(
            id: _me,
            displayName: 'Me',
            colorIndex: 2,
            viewportStart: 0,
            viewportEnd: 10000,
            isHost: true,
          ),
          ParticipantInfo(
            id: _bob,
            displayName: 'Bob',
            colorIndex: 1,
            viewportStart: 0,
            viewportEnd: 10000,
            isHost: false,
          ),
        ],
        sharedMarkers: const {},
        pointers: [_pin(id: 'far', time: 9000)],
      );
      final service = _FakeCollaborationService(Stream.value(session));
      final container = await _pump(
        tester,
        session: session,
        service: service,
      );
      container.read(timeMapperProvider.notifier).zoomToRange(0, 2000);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('offscreen-far')));
      await tester.pumpAndSettle();
      expect(find.text('Jump to pointer'), findsOneWidget);
      expect(find.text('Ask presenter to scroll'), findsNothing);
    });
  });

  group('SharedPointerOverlay — locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets(
        'renders ping + pin + off-screen without exception — $locale',
        (tester) async {
          final pointers = [
            _ping(id: 'p'),
            _pin(id: 'q', author: _me),
            _pin(id: 'r', time: 9000),
          ];
          final service = _FakeCollaborationService(
            Stream.value(_session(pointers)),
          );
          final container = await _pump(
            tester,
            session: _session(pointers),
            service: service,
            locale: locale,
          );
          container.read(timeMapperProvider.notifier).zoomToRange(0, 2000);
          await tester.pump();
          expect(find.byKey(const ValueKey('offscreen-r')), findsOneWidget);
          expect(tester.takeException(), isNull);
          // Let the ping fade so its fade ticker stops before the test ends.
          await tester.pump(const Duration(seconds: 5));
        },
      );
    }
  });
}
