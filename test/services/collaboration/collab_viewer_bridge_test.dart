// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/domain/models/playback_state.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_adoption_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/collaboration/providers/collab_composition_degradation_provider.dart';
import 'package:wavecrux/features/collaboration/providers/collab_viewer_bridge_provider.dart';
import 'package:wavecrux/features/collaboration/providers/composition_detached_provider.dart';
import 'package:wavecrux/features/collaboration/providers/follow_detached_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_identity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/collaboration/collab_viewer_bridge.dart';

/// Records every outbound call so the test can assert what the bridge
/// forwarded. [sessionState] is driven manually via [emit] to simulate a
/// session starting and stopping.
class _FakeCollaborationService implements CollaborationService {
  final _controller = StreamController<CollabSessionState?>.broadcast();

  final List<(int?, int?)> cursorPushes = [];
  final List<(int, int)> viewportPushes = [];
  final List<(String, int)> markersAdded = [];
  final List<String> markersRemoved = [];
  final List<String?> identityUpdates = [];
  final List<CollabPlaybackTransport> transportPushes = [];
  final List<CollabViewComposition> compositionPushes = [];
  final List<CollabAnnotation> annotationsAdded = [];
  final List<CollabAnnotation> annotationsUpdated = [];
  final List<String> annotationsRemoved = [];
  final List<(bool, int?, String?)> writingAnnouncements = [];

  void emit(CollabSessionState? state) => _controller.add(state);
  Future<void> close() => _controller.close();

  @override
  bool get hasRecordedEvents => false;
  @override
  Stream<CollabSessionState?> get sessionState => _controller.stream;

  @override
  void pushCursorUpdate(int? primaryTime, int? secondaryTime) =>
      cursorPushes.add((primaryTime, secondaryTime));

  @override
  void pushViewportUpdate(int startTime, int endTime) =>
      viewportPushes.add((startTime, endTime));

  @override
  void updateWaveformIdentity(String? contentHash) =>
      identityUpdates.add(contentHash);

  @override
  Future<void> addSharedMarker(String name, int time) async =>
      markersAdded.add((name, time));

  @override
  Future<void> removeSharedMarker(String name) async =>
      markersRemoved.add(name);

  @override
  void setFollowTarget(String? participantId) {}

  @override
  void handoffPresenter(String participantId) {}

  @override
  void requestPresenter() {}

  @override
  void respondToPresenterRequest(String participantId, bool grant) {}

  @override
  void pushPlaybackTransport(CollabPlaybackTransport transport) =>
      transportPushes.add(transport);

  @override
  void addPointer(CollabPointer pointer) {}

  @override
  void removePointer(String pointerId) {}

  @override
  void addAnnotation(CollabAnnotation annotation) =>
      annotationsAdded.add(annotation);

  @override
  void updateAnnotation(CollabAnnotation annotation) =>
      annotationsUpdated.add(annotation);

  @override
  void removeAnnotation(String annotationId) =>
      annotationsRemoved.add(annotationId);

  @override
  void setWritingAnnotation({
    required bool writing,
    int? time,
    String? rowId,
  }) => writingAnnouncements.add((writing, time, rowId));

  @override
  void dismissRemovedAnnotationNotice() {}

  @override
  void requestPresenterScroll(int time, String rowId) {}

  @override
  void dismissScrollRequest() {}

  @override
  void updateViewComposition(CollabViewComposition composition) =>
      compositionPushes.add(composition);

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
  Future<SessionRecording> exportRecording() async => SessionRecording(
    sessionId: 's',
    startedAt: DateTime(2020),
    events: const [],
  );

  @override
  bool get isInSession => false;

  @override
  bool get isHost => false;

  @override
  CollabMode get activeMode => CollabMode.none;

  @override
  set onUserInteraction(void Function()? callback) {}
}

/// A session where the local user ('me') is host **and** presenter (presenter
/// defaults to host at session start).
CollabSessionState _session() => const CollabSessionState(
  sessionId: 's',
  myParticipantId: 'me',
  hostId: 'me',
  participants: [
    ParticipantInfo(
      id: 'me',
      displayName: 'Me',
      colorIndex: 0,
      viewportStart: 0,
      viewportEnd: 1000,
      isHost: true,
    ),
  ],
  sharedMarkers: {},
);

/// [_session] carrying the room's annotation set — the inbound half of
/// collaborative annotations.
CollabSessionState _sessionWithAnnotations(
  List<CollabAnnotation> annotations,
) => CollabSessionState(
  sessionId: 's',
  myParticipantId: 'me',
  hostId: 'me',
  participants: const [
    ParticipantInfo(
      id: 'me',
      displayName: 'Me',
      colorIndex: 0,
      viewportStart: 0,
      viewportEnd: 1000,
      isHost: true,
    ),
  ],
  sharedMarkers: const {},
  annotations: annotations,
);

/// A session where the local user ('me') is a **follower** of presenter
/// 'alice' (alice is host, so presenter defaults to alice). Alice's viewport is
/// [vpStart, vpEnd]; an optional [transport] rides the snapshot.
CollabSessionState _followerSession({
  int vpStart = 100,
  int vpEnd = 900,
  CollabPlaybackTransport? transport,
}) => CollabSessionState(
  sessionId: 's',
  myParticipantId: 'me',
  hostId: 'alice',
  participants: [
    ParticipantInfo(
      id: 'alice',
      displayName: 'Alice',
      colorIndex: 1,
      viewportStart: vpStart,
      viewportEnd: vpEnd,
      isHost: true,
    ),
    const ParticipantInfo(
      id: 'me',
      displayName: 'Me',
      colorIndex: 2,
      viewportStart: 0,
      viewportEnd: 10000,
      isHost: false,
    ),
  ],
  sharedMarkers: const {},
  presenterTransport: transport,
);

/// Lets pending microtasks, the Riverpod stream emission, and zero-duration
/// debounce timers run.
Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 5));

ProviderContainer _containerWith(_FakeCollaborationService fake) {
  // The trailing `..read` activates the bridge — mirrors the single bootstrap
  // read in app.dart. The real provider is used (only the service is
  // overridden); the bridge owns its own session-stream subscription.
  //
  // Disable the soft-follow idle auto-resume so no stray Timer outlives a test.
  return ProviderContainer(
    overrides: [
      collaborationServiceProvider.overrideWithValue(fake),
      followDetachIdleTimeoutProvider.overrideWithValue(null),
    ],
  )..read(collabViewerBridgeProvider);
}

void main() {
  // The shared-playhead inbound path creates a real [Ticker] in
  // PlaybackNotifier.play(); a binding must exist for it to construct.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollabViewerBridge', () {
    test('does not forward local changes before a session is active', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      container.read(cursorStateProvider.notifier).placePrimary(100);
      container.read(markerStateProvider.notifier).setMarker('a', 5);
      await _tick();

      expect(fake.cursorPushes, isEmpty);
      expect(fake.markersAdded, isEmpty);
    });

    test(
      'pushes a cursor + viewport baseline when a session starts (presenter)',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _containerWith(fake);
        addTearDown(container.dispose);
        await _tick();

        container.read(cursorStateProvider.notifier).placePrimary(123);
        await _tick();

        fake.emit(_session());
        await _tick();

        expect(fake.cursorPushes, isNotEmpty);
        expect(fake.cursorPushes.last.$1, 123);
        // Local is presenter → viewport baseline is pushed.
        expect(fake.viewportPushes, isNotEmpty);
      },
    );

    test('forwards cursor moves while a session is active', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();
      final baseline = fake.cursorPushes.length;

      container.read(cursorStateProvider.notifier).placePrimary(250);
      await _tick();

      expect(fake.cursorPushes.length, greaterThan(baseline));
      expect(fake.cursorPushes.last, (250, null));
    });

    test('forwards marker add and remove while a session is active', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      container.read(markerStateProvider.notifier).setMarker('a', 42);
      await _tick();
      expect(fake.markersAdded, contains(('a', 42)));

      container.read(markerStateProvider.notifier).removeMarker('a');
      await _tick();
      expect(fake.markersRemoved, contains('a'));
    });

    test(
      'stops forwarding cursor moves after the session ends (null state)',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _containerWith(fake);
        addTearDown(container.dispose);
        await _tick();

        fake.emit(_session());
        await _tick();
        container.read(cursorStateProvider.notifier).placePrimary(100);
        await _tick();
        expect(fake.cursorPushes, isNotEmpty);

        // Session ends — the service emits null.
        fake.emit(null);
        await _tick();
        final countAfterEnd = fake.cursorPushes.length;

        // A later local cursor move is no longer forwarded.
        container.read(cursorStateProvider.notifier).placePrimary(200);
        await _tick();
        expect(fake.cursorPushes.length, countAfterEnd);
      },
    );

    test(
      'binds to the ACTIVE TAB container, not the root scope (regression)',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final tabContainer = ProviderContainer();
        addTearDown(tabContainer.dispose);

        final container = ProviderContainer(
          overrides: [
            collaborationServiceProvider.overrideWithValue(fake),
            followDetachIdleTimeoutProvider.overrideWithValue(null),
            collabViewerBridgeProvider.overrideWith((ref) {
              final bridge = CollabViewerBridge(
                ref: ref,
                activeTabContainerResolver: (_) => tabContainer,
              )..start();
              ref.onDispose(bridge.dispose);
              return bridge;
            }),
          ],
        )..read(collabViewerBridgeProvider);
        addTearDown(container.dispose);
        await _tick();

        fake.emit(_session());
        await _tick();
        final baseline = fake.cursorPushes.length;

        // Moving the ROOT cursor must NOT broadcast — the bridge isn't bound to it.
        container.read(cursorStateProvider.notifier).placePrimary(111);
        await _tick();
        expect(fake.cursorPushes.length, baseline);

        // Moving the ACTIVE TAB's cursor DOES broadcast.
        tabContainer.read(cursorStateProvider.notifier).placePrimary(222);
        await _tick();
        expect(fake.cursorPushes.last, (222, null));
      },
    );

    test('forwards the local waveform identity hash to the service', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      expect(fake.identityUpdates, contains(null));

      container.read(waveformIdentityProvider.notifier).set('deadbeef');
      await _tick();

      expect(fake.identityUpdates.last, 'deadbeef');

      container.read(waveformIdentityProvider.notifier).set(null);
      await _tick();
      expect(fake.identityUpdates.last, isNull);
    });

    test('forwards debounced viewport changes while presenting', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 1000,
            viewportWidth: 800,
          );
      await _tick();

      fake.emit(_session());
      await _tick();
      fake.viewportPushes.clear();

      container.read(timeMapperProvider.notifier).zoomToRange(100, 200);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(fake.viewportPushes, isNotEmpty);
    });
  });

  // ── Presenter Mode: inbound follows the presenter ───────────────────────────

  group('CollabViewerBridge — presenter follow (inbound)', () {
    test(
      'drives the local viewport from the presenter, not the local cursor',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _containerWith(fake);
        addTearDown(container.dispose);

        container
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 10000,
              viewportWidth: 800,
            );
        await _tick();

        fake.emit(_followerSession());
        await _tick();

        // Local viewport mirrors the presenter's range.
        final mapper = container.read(timeMapperProvider);
        expect(mapper.visibleStartTime, lessThanOrEqualTo(150));
        expect(mapper.visibleEndTime, greaterThanOrEqualTo(850));

        // The presenter's cursor is shown via the overlay, not by moving the
        // local cursor — so the local cursor is untouched.
        expect(container.read(cursorStateProvider).primaryCursorTime, isNull);
      },
    );

    test('detach suppresses inbound viewport drive', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 800,
          );
      // Detach first: the follower has peeked away locally.
      container.read(followDetachedProvider.notifier).detach();
      await _tick();

      fake.emit(_followerSession());
      await _tick();

      // Viewport stays at fit-all (0..10000) — the presenter does not drive it.
      final mapper = container.read(timeMapperProvider);
      expect(mapper.visibleStartTime, 0);
      expect(mapper.visibleEndTime, 10000);
    });

    test('a follower local pan detaches and is NOT broadcast', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 800,
          );
      await _tick();
      fake.emit(_followerSession());
      await _tick();
      fake.viewportPushes.clear();

      // The follower deliberately zooms somewhere else.
      container.read(timeMapperProvider.notifier).zoomToRange(2000, 3000);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Followers never broadcast their viewport …
      expect(fake.viewportPushes, isEmpty);
      // … and the local navigation detached soft-follow.
      expect(container.read(followDetachedProvider), isTrue);
    });

    test(
      'a follower local cursor move is still mirrored (presence) + detaches',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _containerWith(fake);
        addTearDown(container.dispose);

        container
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 10000,
              viewportWidth: 800,
            );
        await _tick();
        fake.emit(_followerSession());
        await _tick();

        container.read(cursorStateProvider.notifier).placePrimary(250);
        await _tick();

        expect(fake.cursorPushes, contains((250, null)));
        expect(container.read(followDetachedProvider), isTrue);
      },
    );

    test('becoming the presenter clears a prior detach', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_followerSession());
      await _tick();
      container.read(followDetachedProvider.notifier).detach();
      expect(container.read(followDetachedProvider), isTrue);

      // Handoff: the local user becomes host+presenter.
      fake.emit(_session());
      await _tick();

      expect(container.read(followDetachedProvider), isFalse);
    });
  });

  // ── Presenter Mode: shared playhead (transport) ─────────────────────────────

  group('CollabViewerBridge — shared playhead', () {
    test('presenter broadcasts transport on a local playback change', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 1000,
            viewportWidth: 800,
          );
      await _tick();
      fake.emit(_session()); // local is presenter
      await _tick();

      container
          .read(playbackProvider.notifier)
          .setSpeed(const PlaybackSpeed.duration(5));
      await _tick();

      expect(fake.transportPushes, isNotEmpty);
      expect(fake.transportPushes.last.speed, const PlaybackSpeed.duration(5));
    });

    test('a follower does NOT broadcast transport', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 1000,
            viewportWidth: 800,
          );
      await _tick();
      fake.emit(_followerSession());
      await _tick();
      fake.transportPushes.clear();

      container
          .read(playbackProvider.notifier)
          .setSpeed(const PlaybackSpeed.duration(5));
      await _tick();

      expect(fake.transportPushes, isEmpty);
    });

    test('inbound transport drives the local ticker in lockstep', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 800,
          );
      await _tick();

      fake.emit(
        _followerSession(
          transport: const CollabPlaybackTransport(
            isPlaying: true,
            speed: PlaybackSpeed.duration(7),
            loopMode: PlaybackLoopMode.wholeRange,
            anchorTime: 500,
          ),
        ),
      );
      await _tick();

      final playback = container.read(playbackProvider);
      expect(playback.isPlaying, isTrue);
      expect(playback.speed, const PlaybackSpeed.duration(7));
      expect(playback.loopMode, PlaybackLoopMode.wholeRange);
      // The playhead is seeded to the room's shared anchor.
      expect(container.read(cursorStateProvider).primaryCursorTime, 500);
      // Stop the ticker before teardown.
      container.read(playbackProvider.notifier).pause();
    });

    test('detach suppresses inbound transport', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      container
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 800,
          );
      container.read(followDetachedProvider.notifier).detach();
      await _tick();

      fake.emit(
        _followerSession(
          transport: const CollabPlaybackTransport(
            isPlaying: true,
            speed: PlaybackSpeed.duration(7),
            loopMode: PlaybackLoopMode.none,
            anchorTime: 500,
          ),
        ),
      );
      await _tick();

      expect(container.read(playbackProvider).isPlaying, isFalse);
    });
  });

  group('CollabViewerBridge view-composition sync', () {
    test(
      'presenter mirrors the local composition on a structural edit',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _compositionContainer(fake, _FakeWaveSource());
        addTearDown(container.dispose);
        await _tick();

        fake.emit(_session()); // local is presenter
        await _tick();

        container
            .read(signalGroupsProvider.notifier)
            .addSignal(_wv('clk', ref: 'r_clk'));
        await _tick();

        expect(fake.compositionPushes, isNotEmpty);
        final paths = fake.compositionPushes.last.displayedSignals.entries.map(
          (e) => e.signalPath,
        );
        expect(paths, contains('top.clk'));
      },
    );

    test('followers never mirror their composition outbound', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _compositionContainer(fake, _FakeWaveSource());
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_followerSession()); // local is a follower
      await _tick();
      container
          .read(signalGroupsProvider.notifier)
          .addSignal(_wv('clk', ref: 'r_clk'));
      await _tick();

      expect(fake.compositionPushes, isEmpty);
    });

    test('follower applies the presenter composition as an overlay', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _compositionContainer(fake, _FakeWaveSource());
      addTearDown(container.dispose);
      await _tick();

      // Follower has their own signal first.
      container
          .read(signalGroupsProvider.notifier)
          .addSignal(_wv('own', ref: 'r_own'));

      fake.emit(
        _followerSession().copyWith(
          viewComposition: _composition(['top.clk']),
        ),
      );
      await _tick();

      final paths = container
          .read(signalGroupsProvider)
          .entries
          .map((e) => e.signalPath);
      expect(paths, ['top.clk']);
      // Re-resolved to the follower's local ref.
      expect(
        container.read(signalGroupsProvider).entries.first.signalRef,
        'r_clk',
      );
    });

    test(
      'overlay is non-destructive: detach restores the follower workspace',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _compositionContainer(fake, _FakeWaveSource());
        addTearDown(container.dispose);
        await _tick();

        container
            .read(signalGroupsProvider.notifier)
            .addSignal(_wv('own', ref: 'r_own'));

        fake.emit(
          _followerSession().copyWith(
            viewComposition: _composition(['top.clk']),
          ),
        );
        await _tick();
        expect(
          container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
          ['top.clk'],
        );

        // Composition-scoped detach restores the follower's own workspace.
        container.read(compositionDetachedProvider.notifier).detach();
        await _tick();
        expect(
          container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
          ['top.own'],
        );
      },
    );

    test(
      'follow-or-detached: a detached follower ignores composition updates',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _compositionContainer(fake, _FakeWaveSource());
        addTearDown(container.dispose);
        await _tick();

        container
            .read(signalGroupsProvider.notifier)
            .addSignal(_wv('own', ref: 'r_own'));
        // Detach before any composition arrives.
        container.read(compositionDetachedProvider.notifier).detach();

        fake.emit(
          _followerSession().copyWith(
            viewComposition: _composition(['top.clk']),
          ),
        );
        await _tick();

        // The follower's own workspace is untouched — composition not applied.
        expect(
          container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
          ['top.own'],
        );
      },
    );

    test(
      'missing-signal in the presenter composition degrades gracefully',
      () async {
        final fake = _FakeCollaborationService();
        addTearDown(fake.close);
        final container = _compositionContainer(fake, _FakeWaveSource());
        addTearDown(container.dispose);
        await _tick();

        fake.emit(
          _followerSession().copyWith(
            viewComposition: _composition(['top.clk', 'top.ghost']),
          ),
        );
        await _tick();

        // top.ghost is not in the follower's file → reported, not crashed.
        expect(
          container
              .read(collabCompositionDegradationProvider)
              .missingSignalPaths,
          contains('top.ghost'),
        );
        // The resolvable signal still applied.
        expect(
          container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
          ['top.clk'],
        );
      },
    );

    test('becoming presenter keeps the inherited overlay (does NOT wipe signals) '
        'and re-broadcasts it (regression: beta issue #7)', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _compositionContainer(fake, _FakeWaveSource());
      addTearDown(container.dispose);
      await _tick();

      // Engineer2 joins as a follower with an EMPTY workspace and immediately
      // adopts the presenter's composition (this is what makes the saved
      // workspace empty — the trigger for the original bug).
      fake.emit(
        _followerSession().copyWith(
          viewComposition: _composition(['top.clk']),
        ),
      );
      await _tick();
      expect(
        container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
        ['top.clk'],
      );
      fake.compositionPushes.clear();

      // Engineer2 takes control → becomes host+presenter.
      fake.emit(_session());
      await _tick();

      // The inherited overlay must stay on screen — NOT be restored away to the
      // empty pre-overlay workspace.
      expect(
        container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
        ['top.clk'],
        reason: 'becoming presenter must not wipe the inherited signals',
      );
      // And the becoming-presenter mirror must broadcast that non-empty
      // composition, never an empty list that would clear the whole room.
      expect(fake.compositionPushes, isNotEmpty);
      expect(
        fake.compositionPushes.last.displayedSignals.entries.map(
          (e) => e.signalPath,
        ),
        contains('top.clk'),
      );
      // Overlay bookkeeping is cleared — a later composition-detach must not
      // restore the now-stale empty workspace.
      container.read(compositionDetachedProvider.notifier).detach();
      await _tick();
      expect(
        container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
        ['top.clk'],
        reason:
            'no saved overlay remains after promotion, so detach is a no-op',
      );
    });

    test('session end clears the overlay and degradation', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _compositionContainer(fake, _FakeWaveSource());
      addTearDown(container.dispose);
      await _tick();

      container
          .read(signalGroupsProvider.notifier)
          .addSignal(_wv('own', ref: 'r_own'));
      fake.emit(
        _followerSession().copyWith(
          viewComposition: _composition(['top.ghost']),
        ),
      );
      await _tick();
      expect(
        container.read(collabCompositionDegradationProvider).hasMissing,
        isTrue,
      );

      fake.emit(null); // session ended
      await _tick();
      expect(
        container.read(collabCompositionDegradationProvider).hasMissing,
        isFalse,
      );
      // Follower's own workspace restored.
      expect(
        container.read(signalGroupsProvider).entries.map((e) => e.signalPath),
        ['top.own'],
      );
    });
  });

  // ── collaborative annotations ───────────────────────────────
  //
  // This is the half of C4 that makes the transport reachable from the app.
  // The service, the rights model and the wire format were already covered in
  // the Pro repo; what is asserted here is that authoring actually calls them,
  // and — the part that is easy to get wrong and expensive to notice — that it
  // does NOT call them for the notes that were already on the canvas.
  group('CollabViewerBridge — annotations', () {
    Annotation note(String id, {int time = 100, String text = 'why'}) =>
        Annotation(
          id: id,
          shape: AnnotationShape.callout,
          anchor: PointAnchor(time: time, rowId: 'top.clk'),
          authorName: 'Me',
          createdAt: DateTime.utc(2026, 8, 13),
          text: text,
        );

    /// Long enough for [kCollabAnnotationDebounce] to elapse.
    Future<void> settle() => Future<void>.delayed(
      kCollabAnnotationDebounce + const Duration(milliseconds: 50),
    );

    test('publishes nothing before a session starts', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      container.read(annotationsProvider.notifier).add(note('a'));
      await settle();

      expect(fake.annotationsAdded, isEmpty);
    });

    test('a note written after the session starts reaches the room', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      container.read(annotationsProvider.notifier).add(note('fresh'));
      await settle();

      expect(fake.annotationsAdded.map((a) => a.id), ['fresh']);
    });

    test('notes that predate the session are never published', () async {
      // The rule the colour semantics encode, enforced at the seam that could
      // break it: joining a room must not upload somebody's week-old private
      // notes, and editing or deleting one afterwards must not either.
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      final notifier = container.read(annotationsProvider.notifier)
        ..add(note('old'));
      await _tick();

      fake.emit(_session());
      await _tick();

      notifier
        ..setText('old', 'edited during the meeting')
        ..remove('old');
      await settle();

      expect(fake.annotationsAdded, isEmpty);
      expect(fake.annotationsUpdated, isEmpty);
      expect(fake.annotationsRemoved, isEmpty);
    });

    test('an edit publishes an update, a delete a removal', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      final notifier = container.read(annotationsProvider.notifier)
        ..add(note('n'));
      await settle();

      notifier.setText('n', 'second thoughts');
      await settle();
      expect(fake.annotationsUpdated.map((a) => a.id), ['n']);
      expect(fake.annotationsUpdated.last.annotation.text, 'second thoughts');

      notifier.remove('n');
      await settle();
      expect(fake.annotationsRemoved, ['n']);
    });

    test('a drag is one frame, not one per pointer event', () async {
      // Dragging a balloon emits a nudgeLabel per pointer event. Publishing
      // each of them would be "broadcast per keystroke" wearing a different
      // hat, so the debounce coalesces a gesture into a single update.
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      final notifier = container.read(annotationsProvider.notifier)
        ..add(note('n'));
      await settle();

      for (var i = 0; i < 30; i++) {
        notifier.nudgeLabel('n', 1, 1);
      }
      await settle();

      expect(fake.annotationsUpdated, hasLength(1));
    });

    test('a note being typed is withheld until its editor closes', () async {
      // Broadcast on commit. Creation is two-phase — the note is added to the
      // list immediately so it draws and undo has something to reverse — so
      // without this the room would watch an empty balloon appear.
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      container.read(annotationsProvider.notifier).add(note('n', text: ''));
      container.read(annotationBeingEditedProvider.notifier).editing = 'n';
      await settle();

      expect(fake.annotationsAdded, isEmpty);
      expect(fake.writingAnnouncements.last, (true, 100, 'top.clk'));

      container.read(annotationsProvider.notifier).setText('n', 'committed');
      container.read(annotationBeingEditedProvider.notifier).end();
      await _tick();

      expect(fake.writingAnnouncements.last.$1, isFalse);
      expect(fake.annotationsAdded.map((a) => a.id), ['n']);
      expect(fake.annotationsAdded.single.annotation.text, 'committed');
    });

    test('the writing announcement carries no text, ever', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      container
          .read(annotationsProvider.notifier)
          .add(note('n', text: 'a secret'));
      container.read(annotationBeingEditedProvider.notifier).editing = 'n';
      await settle();

      // The whole announcement is three fields wide. There is nowhere for the
      // text to be, which is the design working rather than an assertion about
      // one call site's discipline.
      expect(fake.writingAnnouncements.last, (true, 100, 'top.clk'));
    });

    test('the host removing your note takes it off your canvas too', () async {
      // The one way a participant's own work disappears without them doing
      // anything. Leaving it on the local canvas would make the status-bar
      // notice describe something the author can still see — and the next edit
      // would republish it into a room that had just rejected it.
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      container.read(annotationsProvider.notifier).add(note('n'));
      await settle();
      expect(fake.annotationsAdded, hasLength(1));

      // The room acknowledges it...
      fake.emit(
        _sessionWithAnnotations([
          CollabAnnotation(
            authorId: 'me',
            annotation: fake.annotationsAdded.single.annotation,
          ),
        ]),
      );
      await _tick();
      // ...and then the host takes it away.
      fake.emit(_sessionWithAnnotations(const []));
      await _tick();

      expect(container.read(annotationsProvider), isEmpty);
      expect(
        fake.annotationsRemoved,
        isEmpty,
        reason: 'the room already knows; echoing it back is a second removal',
      );
    });

    test('a session ending offers its notes for adoption', () async {
      // The session-ended signal is a null on the stream, which by
      // construction carries no annotations, no roster and no palette slots —
      // everything the prompt needs is gone by the time it is told to ask. The
      // bridge holds the last live snapshot for exactly this.
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(
        _sessionWithAnnotations([
          CollabAnnotation(authorId: 'me', annotation: note('mine')),
          CollabAnnotation(authorId: 'bob', annotation: note('theirs')),
        ]),
      );
      await _tick();
      expect(container.read(annotationAdoptionProvider), isNull);

      fake.emit(null);
      await _tick();

      final pending = container.read(annotationAdoptionProvider);
      expect(pending, isNotNull);
      expect(pending!.count, 2);
      expect(pending.mineCount, 1, reason: 'by participant id, not by name');
      // The palette slot is resolved here or never — the roster is gone the
      // moment the session is.
      expect(
        pending.candidates
            .firstWhere((c) => c.annotation.id == 'mine')
            .colorIndex,
        0,
      );
    });

    test('a session that produced no notes asks nothing', () async {
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();
      fake.emit(null);
      await _tick();

      expect(container.read(annotationAdoptionProvider), isNull);
    });

    test('an unacknowledged publish never costs the author their note', () async {
      // A publish the service declined — no session yet, a closed tier gate, a
      // frame lost on the way to the host — looks exactly like the host
      // deleting the note unless the inbound path insists on having SEEN it in
      // the room first.
      final fake = _FakeCollaborationService();
      addTearDown(fake.close);
      final container = _containerWith(fake);
      addTearDown(container.dispose);
      await _tick();

      fake.emit(_session());
      await _tick();

      container.read(annotationsProvider.notifier).add(note('n'));
      await settle();

      // Snapshot after snapshot with an empty annotation set: the room never
      // had it, so it cannot have taken it away.
      fake.emit(_sessionWithAnnotations(const []));
      await _tick();
      fake.emit(_sessionWithAnnotations(const []));
      await _tick();

      expect(container.read(annotationsProvider).map((a) => a.id), ['n']);
    });
  });
}

/// A composition referencing [signalPaths] by canonical path (refs normalised).
CollabViewComposition _composition(List<String> signalPaths) =>
    CollabViewComposition(
      displayedSignals: SignalGroup(
        entries: [
          for (final p in signalPaths)
            SignalEntry.signal(
              signalRef: p,
              signalPath: p,
              displayName: p.split('.').last,
            ),
        ],
      ),
    );

/// Container wired for composition tests: a fixed waveform [source] plus a
/// bridge with a zero composition debounce so structural edits mirror promptly.
ProviderContainer _compositionContainer(
  _FakeCollaborationService fake,
  WaveformDataSource source,
) {
  return ProviderContainer(
    overrides: [
      collaborationServiceProvider.overrideWithValue(fake),
      followDetachIdleTimeoutProvider.overrideWithValue(null),
      waveformSourceProvider.overrideWith(() => _CompSourceNotifier(source)),
      collabViewerBridgeProvider.overrideWith((ref) {
        final bridge = CollabViewerBridge(
          ref: ref,
          compositionDebounce: Duration.zero,
        )..start();
        ref.onDispose(bridge.dispose);
        return bridge;
      }),
    ],
  )..read(collabViewerBridgeProvider);
}

Variable _wv(String name, {required String ref}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top',
  bitWidth: 1,
);

class _CompSourceNotifier extends WaveformSourceNotifier {
  _CompSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// Minimal source exposing top.clk / top.data / top.own (but NOT top.ghost).
class _FakeWaveSource implements WaveformDataSource {
  final List<Variable> _vars = [
    _wv('clk', ref: 'r_clk'),
    _wv('data', ref: 'r_data'),
    _wv('own', ref: 'r_own'),
  ];

  @override
  List<Variable> findVariables(SignalFilter filter) =>
      _vars.where(filter.matches).toList();

  @override
  Future<void> openFile(String path) => throw UnimplementedError();
  @override
  void close() {}
  @override
  List<Scope> get rootScopes => const [];
  @override
  Future<void> loadSignal(String signalRef) async {}
  @override
  Future<void> unloadSignal(String signalRef) async {}
  @override
  bool isSignalLoaded(String signalRef) => true;
  @override
  String? valueAt(String signalRef, int time) => null;
  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) =>
      const [];
  @override
  SignalChange? nextTransition(String signalRef, int afterTime) => null;
  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) => null;
  @override
  int get startTime => 0;
  @override
  int get endTime => 1000;
  @override
  Timescale? get timescale => null;
  @override
  String? get date => null;
  @override
  String? get version => null;
}
