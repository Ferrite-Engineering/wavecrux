// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';

void main() {
  group('collaborationSessionStateProvider', () {
    test('stays in AsyncLoading when noop service emits no events', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final value = container.read(collaborationSessionStateProvider);
      expect(value, isA<AsyncLoading<CollabSessionState?>>());
    });

    test('emits state from overridden service stream', () async {
      const state = CollabSessionState(
        sessionId: 's1',
        myParticipantId: 'p1',
        hostId: 'p1',
        participants: [],
        sharedMarkers: {},
      );
      final fake = _StreamingCollaborationService(Stream.value(state));
      final container = ProviderContainer(
        overrides: [
          collaborationServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      // Subscribe so Riverpod 3 keeps the auto-dispose StreamProvider alive
      // long enough for `.future` to resolve. Plain `container.read` does not
      // create a listener, so the element disposes mid-load.
      final sub = container.listen(
        collaborationSessionStateProvider,
        (_, _) {},
      );
      addTearDown(sub.close);

      final result = await container.read(
        collaborationSessionStateProvider.future,
      );
      expect(result, state);
    });

    test('valueOrNull is null while in AsyncLoading (noop)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(collaborationSessionStateProvider).value,
        isNull,
      );
    });

    test('valueOrNull returns emitted state after data arrives', () async {
      const state = CollabSessionState(
        sessionId: 's2',
        myParticipantId: 'p2',
        hostId: 'p2',
        participants: [],
        sharedMarkers: {},
      );
      final fake = _StreamingCollaborationService(Stream.value(state));
      final container = ProviderContainer(
        overrides: [
          collaborationServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      // Keep the auto-dispose stream provider alive across the awaits below.
      final sub = container.listen(
        collaborationSessionStateProvider,
        (_, _) {},
      );
      addTearDown(sub.close);

      // Drive the stream.
      await container.read(collaborationSessionStateProvider.future);

      expect(
        container.read(collaborationSessionStateProvider).value,
        state,
      );
    });

    test('transitions to AsyncError on stream error', () async {
      final fake = _StreamingCollaborationService(
        Stream.error(Exception('relay unreachable')),
      );
      final container = ProviderContainer(
        overrides: [
          collaborationServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      // Capture the first AsyncError emitted to a subscriber. Riverpod 3
      // enables retries on StreamProviders by default, so awaiting `.future`
      // would loop forever — instead, listen and wait for the error state
      // to land synchronously after stream subscription.
      final completer = Completer<AsyncValue<CollabSessionState?>>();
      final sub = container.listen<AsyncValue<CollabSessionState?>>(
        collaborationSessionStateProvider,
        (_, next) {
          if (next is AsyncError<CollabSessionState?> &&
              !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final result = await completer.future.timeout(const Duration(seconds: 2));
      expect(result, isA<AsyncError<CollabSessionState?>>());
      expect(
        (result as AsyncError<CollabSessionState?>).error.toString(),
        contains('relay unreachable'),
      );
    });
  });
}

/// A minimal fake that exposes a caller-supplied stream as [sessionState].
class _StreamingCollaborationService implements CollaborationService {
  _StreamingCollaborationService(this._stream);

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
  bool get isInSession => false;

  @override
  bool get isHost => false;

  @override
  CollabMode get activeMode => CollabMode.none;

  @override
  // Setter-only matches the CollaborationService interface contract; no getter exists.
  set onUserInteraction(void Function()? callback) {}
}
