// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';

Annotation _ann({
  String id = 'a1',
  int time = 100,
  String row = 'top.bus',
  String? layerId,
  DateTime? createdAt,
}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: row),
  authorName: 'Martin',
  createdAt: createdAt ?? DateTime.utc(2026, 8, 12),
  text: 'note $id',
  layerId: layerId,
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationsNotifier notifier() =>
      container.read(annotationsProvider.notifier);
  List<Annotation> current() => container.read(annotationsProvider);

  group('mutations', () {
    test('starts empty and appends', () {
      expect(current(), isEmpty);
      notifier().add(_ann());
      expect(current().single.id, 'a1');
    });

    test('a duplicate id is ignored, not appended twice', () {
      notifier()
        ..add(_ann())
        ..add(_ann());
      expect(current().length, 1);
    });

    test('removes by id, and ignores an unknown id', () {
      notifier()
        ..add(_ann())
        ..add(_ann(id: 'a2'))
        ..remove('a1')
        ..remove('nope');
      expect(current().map((a) => a.id), ['a2']);
    });

    test('setText caps at the model limit', () {
      notifier()
        ..add(_ann())
        ..setText('a1', 'x' * (kAnnotationTextMaxLength + 100));
      expect(current().single.text.length, kAnnotationTextMaxLength);
    });

    test('removeLayer drops the whole group in one step', () {
      notifier()
        ..add(_ann(layerId: 'review-1'))
        ..add(_ann(id: 'a2', layerId: 'review-1'))
        ..add(_ann(id: 'a3'))
        ..removeLayer('review-1');
      expect(current().map((a) => a.id), ['a3']);

      notifier().undo();
      expect(current().length, 3, reason: 'one undo step for the whole layer');
    });
  });

  group('the anchor/label distinction', () {
    test('setLabelOffset moves the label and leaves the anchor alone', () {
      notifier()
        ..add(_ann())
        ..setLabelOffset('a1', 55, -80);
      final a = current().single;
      expect(a.labelDx, 55);
      expect(a.labelDy, -80);
      expect(a.anchor, const PointAnchor(time: 100, rowId: 'top.bus'));
    });

    test('reanchor moves the anchor and leaves the label alone', () {
      notifier()
        ..add(_ann())
        ..setLabelOffset('a1', 55, -80)
        ..reanchor('a1', const PointAnchor(time: 900, rowId: 'top.clk'));
      final a = current().single;
      expect(a.anchor, const PointAnchor(time: 900, rowId: 'top.clk'));
      expect(a.labelDx, 55);
      expect(a.labelDy, -80);
    });
  });

  group('undo / redo', () {
    test('nothing to undo or redo on a fresh notifier', () {
      expect(notifier().canUndo, isFalse);
      expect(notifier().canRedo, isFalse);
      notifier()
        ..undo()
        ..redo();
      expect(current(), isEmpty);
    });

    test('undo reverses an add; redo reinstates it', () {
      notifier().add(_ann());
      expect(notifier().canUndo, isTrue);

      notifier().undo();
      expect(current(), isEmpty);
      expect(notifier().canRedo, isTrue);

      notifier().redo();
      expect(current().single.id, 'a1');
    });

    test('a fresh edit clears the redo stack', () {
      notifier()
        ..add(_ann())
        ..undo();
      expect(notifier().canRedo, isTrue);

      notifier().add(_ann(id: 'a2'));
      expect(notifier().canRedo, isFalse);
    });

    test('a no-op mutation records no undo step', () {
      notifier()
        ..add(_ann())
        ..remove('does-not-exist');
      expect(notifier().canUndo, isTrue);
      notifier().undo();
      expect(current(), isEmpty, reason: 'the add was the only step');
      expect(notifier().canUndo, isFalse);
    });

    test('history is bounded', () {
      for (var i = 0; i < kAnnotationUndoHistoryLimit + 25; i++) {
        notifier().add(_ann(id: 'a$i'));
      }
      var undos = 0;
      while (notifier().canUndo) {
        notifier().undo();
        undos++;
        if (undos > kAnnotationUndoHistoryLimit + 50) break;
      }
      expect(undos, kAnnotationUndoHistoryLimit);
    });
  });

  group('transactions — a drag is one undo step', () {
    test('sixty drag frames collapse into a single undo', () {
      notifier().add(_ann());
      final afterAdd = current().single;

      notifier().beginTransaction();
      for (var i = 1; i <= 60; i++) {
        notifier().setLabelOffset('a1', i.toDouble(), -i.toDouble());
      }
      notifier().endTransaction();

      expect(current().single.labelDx, 60);

      notifier().undo();
      expect(
        current().single.labelDx,
        afterAdd.labelDx,
        reason: 'one undo returns to before the drag, not one frame back',
      );
      expect(
        current().single.id,
        'a1',
        reason: 'the annotation itself survives — only the drag is undone',
      );
    });

    test('a transaction that changes nothing records no step', () {
      notifier().add(_ann());
      notifier()
        ..beginTransaction()
        ..endTransaction()
        ..undo();
      expect(current(), isEmpty, reason: 'undo hit the add, not an empty step');
    });

    test('cancelTransaction discards without recording', () {
      notifier().add(_ann());
      notifier()
        ..beginTransaction()
        ..setLabelOffset('a1', 99, 99)
        ..cancelTransaction()
        ..undo();
      // The drag stays applied (cancel only drops the *history* entry) and
      // undo falls through to the add.
      expect(current(), isEmpty);
    });

    test('beginTransaction is idempotent', () {
      notifier().add(_ann());
      notifier()
        ..beginTransaction()
        ..beginTransaction()
        ..setLabelOffset('a1', 10, 10)
        ..endTransaction()
        ..undo();
      expect(current().single.labelDx, 0);
    });
  });

  group('session integration', () {
    test('restoreFromSession replaces state and clears history', () {
      notifier()
        ..add(_ann())
        ..add(_ann(id: 'a2'));
      expect(notifier().canUndo, isTrue);

      notifier().restoreFromSession([_ann(id: 'loaded')]);
      expect(current().map((a) => a.id), ['loaded']);
      expect(
        notifier().canUndo,
        isFalse,
        reason:
            'undoing across a file load would resurrect another '
            "waveform's annotations",
      );
      expect(notifier().canRedo, isFalse);
    });

    test('snapshot returns the current list', () {
      notifier().add(_ann());
      expect(notifier().snapshot().single.id, 'a1');
    });
  });

  group('time ordering', () {
    test('sorts by anchor tick, not insertion order', () {
      notifier()
        ..add(_ann(id: 'late', time: 900))
        ..add(_ann(id: 'early', time: 150))
        ..add(_ann(id: 'middle', time: 500));
      expect(
        container.read(annotationsInTimeOrderProvider).map((a) => a.id),
        ['early', 'middle', 'late'],
      );
    });

    test('ties break by creation time so ordering is stable', () {
      notifier()
        ..add(
          _ann(
            id: 'second',
            time: 250,
            createdAt: DateTime.utc(2026, 8, 12, 10),
          ),
        )
        ..add(
          _ann(
            id: 'first',
            time: 250,
            createdAt: DateTime.utc(2026, 8, 12, 9),
          ),
        );
      expect(
        container.read(annotationsInTimeOrderProvider).map((a) => a.id),
        ['first', 'second'],
      );
    });

    test('a band sorts by its earlier end', () {
      notifier().add(_ann(id: 'point', time: 500));
      container
          .read(annotationsProvider.notifier)
          .add(
            Annotation(
              id: 'band',
              shape: AnnotationShape.band,
              anchor: const RangeAnchor(startTime: 800, endTime: 200),
              authorName: 'M',
              createdAt: DateTime.utc(2026),
            ),
          );
      expect(
        container.read(annotationsInTimeOrderProvider).map((a) => a.id),
        ['band', 'point'],
      );
    });
  });
}
