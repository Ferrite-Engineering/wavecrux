// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/shared_marker_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/collaboration/noop_collaboration_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

class _FakeTimeMapperNotifier extends TimeMapperNotifier {
  _FakeTimeMapperNotifier(this._mapper);
  final TimeMapper _mapper;
  @override
  TimeMapper build() => _mapper;
}

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
  set onUserInteraction(void Function()? callback) {}
}

final _kMapper = TimeMapper.fitAll(
  startTime: 0,
  endTime: 10000,
  viewportWidth: 800,
);
final _kNarrowMapper = TimeMapper.fitAll(
  startTime: 0,
  endTime: 4000,
  viewportWidth: 800,
);

Widget _wrap({
  CollaborationService? service,
  TimeMapper? mapper,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
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
        child: SharedMarkerOverlay(),
      ),
    ),
  ),
);

CollabSessionState _session(Map<String, int> markers) => CollabSessionState(
  sessionId: 's1',
  myParticipantId: 'p1',
  hostId: 'p1',
  participants: const [],
  sharedMarkers: markers,
);

Finder _paint() => find.descendant(
  of: find.byType(SharedMarkerOverlay),
  matching: find.byType(CustomPaint),
);

void main() {
  group('SharedMarkerOverlay — locale sweep', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders without exception — $locale', (tester) async {
        final svc = _FakeCollaborationService(
          Stream.value(_session({'a': 4000})),
        );
        await tester.pumpWidget(_wrap(service: svc, locale: locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('renders nothing with no active session', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    expect(_paint(), findsNothing);
  });

  testWidgets('renders nothing when the session has no shared markers', (
    tester,
  ) async {
    final svc = _FakeCollaborationService(Stream.value(_session(const {})));
    await tester.pumpWidget(_wrap(service: svc));
    await tester.pump();
    expect(_paint(), findsNothing);
  });

  testWidgets('paints when a shared marker is within the viewport', (
    tester,
  ) async {
    final svc = _FakeCollaborationService(Stream.value(_session({'a': 4000})));
    await tester.pumpWidget(_wrap(service: svc));
    await tester.pump();
    expect(_paint(), findsOneWidget);
  });

  testWidgets('renders nothing when every shared marker is out of viewport', (
    tester,
  ) async {
    // Narrow viewport shows 0–4000; marker at 9000 is off-screen.
    final svc = _FakeCollaborationService(Stream.value(_session({'a': 9000})));
    await tester.pumpWidget(_wrap(service: svc, mapper: _kNarrowMapper));
    await tester.pump();
    expect(_paint(), findsNothing);
  });
}
