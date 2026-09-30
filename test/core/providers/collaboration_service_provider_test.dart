// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/services/collaboration/noop_collaboration_service.dart';

void main() {
  group('collaborationServiceProvider', () {
    test('default returns NoopCollaborationService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(collaborationServiceProvider),
        isA<NoopCollaborationService>(),
      );
    });

    test('default implementation reports isInSession=false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(collaborationServiceProvider).isInSession,
        isFalse,
      );
    });

    test('can be overridden with a fake implementation', () {
      final fake = _FakeCollaborationService();
      final container = ProviderContainer(
        overrides: [
          collaborationServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(collaborationServiceProvider),
        same(fake),
      );
    });

    test('overridden implementation is used by dependents', () async {
      final fake = _FakeCollaborationService();
      final container = ProviderContainer(
        overrides: [
          collaborationServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(collaborationServiceProvider)
          .createSession(displayName: 'Alice', mode: CollabMode.wan);

      expect(fake.createSessionCalled, isTrue);
    });
  });
}

class _FakeCollaborationService implements CollaborationService {
  bool createSessionCalled = false;

  @override
  bool get hasRecordedEvents => false;
  @override
  Future<String> createSession({
    required String displayName,
    required CollabMode mode,
  }) async {
    createSessionCalled = true;
    return 'FAKE01';
  }

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
  Stream<CollabSessionState?> get sessionState => const Stream.empty();

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
