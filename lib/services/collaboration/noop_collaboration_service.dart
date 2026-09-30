// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';

/// Open-core default [CollaborationService]: every query returns a neutral
/// value, no network calls are made, and no allocations occur in hot paths.
///
/// The closed-source Pro overlay replaces this binding via
/// [collaborationServiceProvider] with `CollaborationServiceImpl`, which runs
/// real WebSocket sessions (LAN direct or WAN relay).
class NoopCollaborationService implements CollaborationService {
  const NoopCollaborationService();

  @override
  bool get hasRecordedEvents => false;
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

  // Collaborative annotations. Inert here by design: open core
  // renders and persists annotations perfectly well on its own, and this
  // service is what makes that path behave identically when the Pro overlay is
  // absent — no session, nothing to publish to.
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
  // Setter-only by design — the no-op implementation ignores the callback;
  // the Pro implementation stores it and fires it to break follow mode.
  set onUserInteraction(void Function()? callback) {}
}
