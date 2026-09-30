// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';

/// Annotations — the SessionNotifier ↔ AnnotationsNotifier wiring.
///
/// **Why this file exists.** The codec round-trip tests in
/// `session_annotations_round_trip_test.dart` all passed while the app showed
/// no annotations at all, because they exercise `SessionService` directly.
/// Nothing captured annotations into `_snapshot()` or pushed them back in
/// `_restore()`, so the serializer was faithfully writing an empty list and
/// faithfully reading one back into nowhere.
///
/// A codec test cannot catch a missing wire. These assert the live provider
/// graph: what the notifier snapshots, and what a restore actually lands in.

Annotation _ann({String id = 'a1', int time = 100}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: 'top.bus'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12),
  text: 'note $id',
);

void main() {
  late ProviderContainer container;

  setUp(() {
    // Hold the providers so a read closing its last subscription does not
    // schedule a dispose between steps.
    container = ProviderContainer()
      ..listen(annotationsProvider, (_, _) {})
      ..listen(annotationLayersProvider, (_, _) {})
      ..listen(sessionProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test('snapshot() carries the annotations the notifier holds', () {
    final notifier = container.read(annotationsProvider.notifier)
      ..add(_ann())
      ..add(_ann(id: 'a2', time: 900));
    expect(notifier.snapshot(), hasLength(2));

    final snapshot = container.read(sessionProvider.notifier).snapshot();

    expect(
      snapshot.annotations.map((a) => a.id),
      ['a1', 'a2'],
      reason:
          'a snapshot that drops annotations saves an empty list over the '
          'work the user actually did',
    );
  });

  test('restoreFromState lands annotations in the provider', () async {
    expect(container.read(annotationsProvider), isEmpty);

    await container
        .read(sessionProvider.notifier)
        .restoreFromState(
          SessionState(
            annotations: [
              _ann(),
              _ann(id: 'a2', time: 900),
            ],
          ),
        );

    expect(
      container.read(annotationsProvider).map((a) => a.id),
      ['a1', 'a2'],
      reason: 'this is the exact gap that made the demo session open blank',
    );
  });

  test('a restore replaces rather than merges', () async {
    container.read(annotationsProvider.notifier).add(_ann(id: 'stale'));

    await container
        .read(sessionProvider.notifier)
        .restoreFromState(
          SessionState(annotations: [_ann(id: 'fresh')]),
        );

    expect(container.read(annotationsProvider).map((a) => a.id), ['fresh']);
  });

  test('a restore clears undo history', () async {
    container.read(annotationsProvider.notifier).add(_ann(id: 'before'));
    expect(container.read(annotationsProvider.notifier).canUndo, isTrue);

    await container
        .read(sessionProvider.notifier)
        .restoreFromState(
          SessionState(annotations: [_ann(id: 'after')]),
        );

    expect(
      container.read(annotationsProvider.notifier).canUndo,
      isFalse,
      reason: "undoing across a load would resurrect another waveform's notes",
    );
  });

  test(
    'restoring a session with no annotations empties the provider',
    () async {
      container.read(annotationsProvider.notifier).add(_ann());

      await container
          .read(sessionProvider.notifier)
          .restoreFromState(const SessionState());

      expect(container.read(annotationsProvider), isEmpty);
    },
  );

  test('snapshot → restore is lossless through the provider graph', () async {
    final original = [
      _ann(),
      Annotation(
        id: 'band',
        shape: AnnotationShape.band,
        anchor: const RangeAnchor(startTime: 10, endTime: 90),
        authorName: 'Martin',
        createdAt: DateTime.utc(2026, 8, 12),
        text: 'window',
        witness: const AnnotationWitness(bits: '0xa3', edgeOrdinal: 2),
      ),
    ];
    final notifier = container.read(annotationsProvider.notifier);
    original.forEach(notifier.add);

    final snapshot = container.read(sessionProvider.notifier).snapshot();
    container.read(annotationsProvider.notifier).restoreFromSession(const []);
    await container.read(sessionProvider.notifier).restoreFromState(snapshot);

    expect(container.read(annotationsProvider), original);
  });

  group('adopted layers', () {
    test('the layer registry is snapshotted and restored with the notes', () {
      // A codec test cannot catch a missing wire: the registry could serialize
      // perfectly while nothing ever put a layer into it or took one out.
      container
          .read(annotationLayersProvider.notifier)
          .upsert(
            const AnnotationLayer(
              id: 'L1',
              label: 'Design review · 3 participants',
              sourceSessionId: 'S1',
            ),
          );
      container
          .read(annotationsProvider.notifier)
          .add(
            _ann().copyWith(layerId: 'L1'),
          );

      final snapshot = container.read(sessionProvider.notifier).snapshot();
      expect(snapshot.annotationLayers, hasLength(1));
      expect(
        snapshot.annotationLayers.single.label,
        'Design review · 3 participants',
      );

      container
          .read(annotationLayersProvider.notifier)
          .restoreFromSession(
            const [],
          );
      expect(container.read(annotationLayersProvider), isEmpty);

      container
          .read(annotationLayersProvider.notifier)
          .restoreFromSession(snapshot.annotationLayers);
      expect(container.read(annotationLayersProvider).single.id, 'L1');
    });
  });
}
