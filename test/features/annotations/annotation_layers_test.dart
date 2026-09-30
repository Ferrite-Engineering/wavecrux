// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Annotation session layers and the adoption flow.
//
// The load-bearing assertion in this file is the colour freeze. A session
// annotation's colour comes from its author's `colorIndex`, a per-session 0–7
// palette slot; carrying that index into the document would make last week's
// notes silently recolour and misattribute themselves the moment a new session
// handed the slot to somebody else. Everything else here is grouping and
// disposal, which is what makes "Keep all" a safe answer a week later.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/collaborator_palette.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_adoption_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';

Annotation _note({
  String id = 'n1',
  String author = 'Bob',
  int time = 100,
  String? layerId,
}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: 'top.bus'),
  authorName: author,
  createdAt: DateTime.utc(2026, 8, 13),
  text: 'note $id',
  layerId: layerId,
);

PendingAdoption _pending({
  required List<AdoptableAnnotation> candidates,
  int participants = 3,
}) => PendingAdoption(
  candidates: candidates,
  participantCount: participants,
  endedAt: DateTime.utc(2026, 8, 13, 14, 30),
  sessionId: 'S1',
);

void main() {
  late ProviderContainer container;

  setUp(() {
    // Held so a read closing its last subscription does not schedule a dispose
    // between steps.
    container = ProviderContainer()
      ..listen(annotationsProvider, (_, _) {})
      ..listen(annotationLayersProvider, (_, _) {})
      ..listen(annotationAdoptionProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  AnnotationAdoption adoption() =>
      container.read(annotationAdoptionProvider.notifier);
  AnnotationLayers layers() =>
      container.read(annotationLayersProvider.notifier);

  group('the colour freeze', () {
    test('adoption stores the RESOLVED colour, never the slot', () {
      adoption()
        ..offer(
          _pending(
            candidates: [
              AdoptableAnnotation(
                annotation: _note(),
                isMine: false,
                colorIndex: 3,
              ),
            ],
          ),
        )
        ..keep(onlyMine: false, label: 'Design review');

      final adopted = container.read(annotationsProvider).single;
      expect(adopted.colorRgb, collaboratorColor(3).toARGB32());
    });

    test('a second session reassigning slot 3 does not move it', () {
      // The failure this exists to catch is silent and arrives a week later:
      // the note still says "Bob", and it is now wearing Priya's colour.
      adoption()
        ..offer(
          _pending(
            candidates: [
              AdoptableAnnotation(
                annotation: _note(),
                isMine: false,
                colorIndex: 3,
              ),
            ],
          ),
        )
        ..keep(onlyMine: false, label: 'Design review');
      final before = container.read(annotationsProvider).single.colorRgb;

      // Next week: a different person holds slot 3, and slot 3 itself is a
      // different colour as far as the *previous* meeting is concerned.
      adoption()
        ..offer(
          _pending(
            candidates: [
              AdoptableAnnotation(
                annotation: _note(id: 'n2', author: 'Priya'),
                isMine: false,
                colorIndex: 5,
              ),
            ],
          ),
        )
        ..keep(onlyMine: false, label: 'Second review');

      final first = container
          .read(annotationsProvider)
          .firstWhere((a) => a.id == 'n1');
      expect(first.colorRgb, before);
      expect(first.colorRgb, isNot(collaboratorColor(5).toARGB32()));
    });

    test('an author the roster no longer knows adopts unattributed', () {
      adoption()
        ..offer(
          _pending(
            candidates: [
              AdoptableAnnotation(annotation: _note(), isMine: false),
            ],
          ),
        )
        ..keep(onlyMine: false, label: 'Design review');

      // The theme colour, not somebody else's slot: a note in a colour picked
      // at random would attribute it to whoever happens to hold that slot.
      expect(container.read(annotationsProvider).single.colorRgb, isNull);
    });
  });

  group('the prompt branches', () {
    List<AdoptableAnnotation> mixed() => [
      AdoptableAnnotation(annotation: _note(), isMine: false, colorIndex: 1),
      AdoptableAnnotation(
        annotation: _note(id: 'n2', author: 'Me'),
        isMine: true,
        colorIndex: 0,
      ),
    ];

    test('Keep all adopts everything as one named layer', () {
      adoption()
        ..offer(_pending(candidates: mixed()))
        ..keep(onlyMine: false, label: 'Design review · 3 participants');

      expect(container.read(annotationsProvider), hasLength(2));
      final layer = container.read(annotationLayersProvider).single;
      expect(layer.label, 'Design review · 3 participants');
      expect(layer.sourceSessionId, 'S1');
      expect(
        container.read(annotationsProvider).map((a) => a.layerId),
        everyElement(layer.id),
      );
    });

    test('Keep only mine drops the others but still makes a layer', () {
      // Still a layer rather than loose notes: they were written in that
      // meeting whoever wrote them, and "which of these came out of the
      // review?" is the same question a week later.
      adoption()
        ..offer(_pending(candidates: mixed()))
        ..keep(onlyMine: true, label: 'Design review');

      expect(container.read(annotationsProvider).map((a) => a.id), ['n2']);
      expect(container.read(annotationLayersProvider), hasLength(1));
    });

    test('Discard keeps nothing and registers no layer', () {
      adoption()
        ..offer(_pending(candidates: mixed()))
        ..discard();

      expect(container.read(annotationsProvider), isEmpty);
      expect(container.read(annotationLayersProvider), isEmpty);
      expect(container.read(annotationAdoptionProvider), isNull);
    });

    test('**dismissing keeps everything**', () {
      // The branch a closed prompt takes, and the one worth a test of its own:
      // silently discarding destroys the meeting's output, silently keeping
      // merely surprises somebody, and a closed prompt must take the branch
      // that does not lose work irreversibly.
      adoption()
        ..offer(_pending(candidates: mixed()))
        ..dismiss(label: 'Design review');

      expect(container.read(annotationsProvider), hasLength(2));
    });

    test('an empty session is never offered', () {
      adoption().offer(_pending(candidates: const []));
      expect(container.read(annotationAdoptionProvider), isNull);
    });

    test('adoption is one undo step, not one per note', () {
      adoption()
        ..offer(_pending(candidates: mixed()))
        ..keep(onlyMine: false, label: 'Design review');

      container.read(annotationsProvider.notifier).undo();
      expect(container.read(annotationsProvider), isEmpty);
    });

    test('the local copy of your own note is not duplicated', () {
      // A participant's session notes are already on their canvas. Adoption
      // must move them into the layer, not add a second copy of each.
      container.read(annotationsProvider.notifier).add(_note(id: 'n2'));
      adoption()
        ..offer(_pending(candidates: mixed()))
        ..keep(onlyMine: false, label: 'Design review');

      expect(
        container.read(annotationsProvider).where((a) => a.id == 'n2'),
        hasLength(1),
      );
    });
  });

  group('layers as a unit', () {
    test('hiding a layer takes its notes off the canvas, not the panel', () {
      layers().upsert(
        const AnnotationLayer(id: 'L1', label: 'Design review'),
      );
      container.read(annotationsProvider.notifier)
        ..add(_note(layerId: 'L1'))
        ..add(_note(id: 'n2'));

      expect(container.read(hiddenAnnotationLayerIdsProvider), isEmpty);
      layers().setVisible('L1', visible: false);

      expect(container.read(hiddenAnnotationLayerIdsProvider), {'L1'});
      // The panel's source is unfiltered: a layer you cannot see and cannot
      // find again is a layer you have lost.
      expect(container.read(annotationsProvider), hasLength(2));
    });

    test('deleting a layer removes its notes in one undo step', () {
      layers().upsert(
        const AnnotationLayer(id: 'L1', label: 'Design review'),
      );
      final notifier = container.read(annotationsProvider.notifier)
        ..add(_note(layerId: 'L1'))
        ..add(_note(id: 'n2', layerId: 'L1'))
        ..add(_note(id: 'mine'))
        ..removeLayer('L1');
      layers().remove('L1');

      expect(container.read(annotationsProvider).map((a) => a.id), ['mine']);
      expect(container.read(annotationLayersProvider), isEmpty);

      notifier.undo();
      expect(container.read(annotationsProvider), hasLength(3));
    });

    test('toggling visibility to its current value changes nothing', () {
      layers().upsert(
        const AnnotationLayer(id: 'L1', label: 'Design review'),
      );
      final before = container.read(annotationLayersProvider);
      layers().setVisible('L1', visible: true);
      expect(identical(container.read(annotationLayersProvider), before), true);
    });
  });

  group('read-only attribution', () {
    test('an adopted note is read-only; your own are not', () {
      container.read(annotationsProvider.notifier)
        ..add(_note(layerId: 'L1'))
        ..add(_note(id: 'mine'));

      expect(container.read(readOnlyAnnotationIdsProvider), {'n1'});
    });
  });

  group('the layer model', () {
    test('round-trips through JSON', () {
      const layer = AnnotationLayer(
        id: 'L1',
        label: 'Design review · 3 participants',
        sourceSessionId: 'S1',
        visible: false,
      );
      expect(AnnotationLayer.fromJson(layer.toJson()), layer);
    });

    test('a missing visible flag means visible', () {
      // A layer that defaulted to hidden would make a document quietly lose
      // notes the first time an older build saved it.
      final decoded = AnnotationLayer.fromJson({'id': 'L1', 'label': 'x'});
      expect(decoded!.visible, isTrue);
    });

    test('a malformed entry decodes to null rather than throwing', () {
      expect(AnnotationLayer.fromJson({'label': 'no id'}), isNull);
      expect(AnnotationLayer.fromJson({'id': 'L1'}), isNull);
      expect(AnnotationLayer.fromJson('not a map'), isNull);
    });
  });
}
