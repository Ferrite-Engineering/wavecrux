// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';

/// A representative annotation with every optional field populated, so
/// round-trip tests exercise the full payload rather than the defaults.
Annotation _full() => Annotation(
  id: 'ann-1',
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 1250, rowId: 'top.cpu.alu_result'),
  text: 'ALU result is stale here — one cycle behind the operand latch.',
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12, 9, 30),
  labelDx: 40,
  labelDy: -60,
  colorRgb: 0xFF4C9AFF,
  witness: const AnnotationWitness(bits: '10100011', edgeOrdinal: 17),
  layerId: 'layer-review-1',
  collapsed: true,
);

void main() {
  group('AnnotationAnchor', () {
    test('point anchor round-trips', () {
      const anchor = PointAnchor(time: 42, rowId: 'top.clk');
      final decoded = AnnotationAnchor.fromJson(anchor.toJson());
      expect(decoded, anchor);
    });

    test('range anchor round-trips with and without a row', () {
      const lane = RangeAnchor(startTime: 10, endTime: 90, rowId: 'top.bus');
      const full = RangeAnchor(startTime: 10, endTime: 90);
      expect(AnnotationAnchor.fromJson(lane.toJson()), lane);
      expect(AnnotationAnchor.fromJson(full.toJson()), full);
    });

    test('range exposes normalised ends regardless of authoring order', () {
      const forward = RangeAnchor(startTime: 10, endTime: 90);
      const backward = RangeAnchor(startTime: 90, endTime: 10);
      expect(forward.earliest, 10);
      expect(forward.latest, 90);
      expect(backward.earliest, 10);
      expect(backward.latest, 90);
      expect(backward.durationTicks, 80);
    });

    test('unusable payloads decode to null rather than throwing', () {
      expect(AnnotationAnchor.fromJson(null), isNull);
      expect(AnnotationAnchor.fromJson('nonsense'), isNull);
      expect(AnnotationAnchor.fromJson(<String, Object?>{}), isNull);
      // Unknown kind.
      expect(
        AnnotationAnchor.fromJson({'kind': 'spiral', 'time': 1}),
        isNull,
      );
      // Point with a non-integer tick — a formatted time would land here.
      expect(
        AnnotationAnchor.fromJson({
          'kind': 'point',
          'time': '1.25us',
          'rowId': 'a',
        }),
        isNull,
      );
      // Point with no row identity.
      expect(
        AnnotationAnchor.fromJson({'kind': 'point', 'time': 1}),
        isNull,
      );
      // Point with an empty row identity.
      expect(
        AnnotationAnchor.fromJson({
          'kind': 'point',
          'time': 1,
          'rowId': '',
        }),
        isNull,
      );
      // Range missing an end.
      expect(
        AnnotationAnchor.fromJson({'kind': 'range', 'start': 1}),
        isNull,
      );
    });
  });

  group('AnnotationWitness', () {
    test('round-trips, with and without an edge ordinal', () {
      const withOrdinal = AnnotationWitness(
        bits: '1101111010101101',
        edgeOrdinal: 3,
      );
      const without = AnnotationWitness(bits: '0');
      expect(AnnotationWitness.fromJson(withOrdinal.toJson()), withOrdinal);
      expect(AnnotationWitness.fromJson(without.toJson()), without);
      expect(without.toJson().containsKey('edgeOrdinal'), isFalse);
    });

    test('unusable payloads decode to null', () {
      expect(AnnotationWitness.fromJson(null), isNull);
      expect(AnnotationWitness.fromJson({'bits': 7}), isNull);
      expect(AnnotationWitness.fromJson('x'), isNull);
    });

    test('a non-integer edge ordinal degrades rather than failing', () {
      final decoded = AnnotationWitness.fromJson({
        'bits': '1',
        'edgeOrdinal': 'third',
      });
      expect(decoded, isNotNull);
      expect(decoded!.bits, '1');
      expect(decoded.edgeOrdinal, isNull);
    });
  });

  group('Annotation JSON', () {
    test('round-trips every field', () {
      final original = _full();
      final decoded = Annotation.fromJson(original.toJson());
      expect(decoded, original);
    });

    test('round-trips each shape and anchor combination', () {
      final cases = <Annotation>[
        Annotation(
          id: 'a',
          shape: AnnotationShape.callout,
          anchor: const PointAnchor(time: 1, rowId: 'r'),
          authorName: 'A',
          createdAt: DateTime.utc(2026),
          text: 'hello',
        ),
        Annotation(
          id: 'b',
          shape: AnnotationShape.arrow,
          anchor: const PointAnchor(time: 2, rowId: 'r'),
          authorName: 'A',
          createdAt: DateTime.utc(2026),
        ),
        Annotation(
          id: 'c',
          shape: AnnotationShape.band,
          anchor: const RangeAnchor(startTime: 3, endTime: 9),
          authorName: 'A',
          createdAt: DateTime.utc(2026),
        ),
        Annotation(
          id: 'd',
          shape: AnnotationShape.band,
          anchor: const RangeAnchor(
            startTime: 3,
            endTime: 9,
            rowId: 'top.bus',
          ),
          authorName: 'A',
          createdAt: DateTime.utc(2026),
        ),
      ];
      for (final c in cases) {
        expect(Annotation.fromJson(c.toJson()), c, reason: 'case ${c.id}');
      }
    });

    test('defaults are omitted from the encoded form', () {
      final minimal = Annotation(
        id: 'm',
        shape: AnnotationShape.arrow,
        anchor: const PointAnchor(time: 5, rowId: 'r'),
        authorName: '',
        createdAt: DateTime.utc(2026),
      );
      final json = minimal.toJson();
      expect(json.containsKey('text'), isFalse);
      expect(json.containsKey('author'), isFalse);
      expect(json.containsKey('labelDx'), isFalse);
      expect(json.containsKey('labelDy'), isFalse);
      expect(json.containsKey('colorRgb'), isFalse);
      expect(json.containsKey('witness'), isFalse);
      expect(json.containsKey('layerId'), isFalse);
      expect(json.containsKey('collapsed'), isFalse);
    });

    test('an over-long body is truncated at the model boundary', () {
      final json = _full().toJson()
        ..['text'] = 'x' * (kAnnotationTextMaxLength + 500);
      final decoded = Annotation.fromJson(json);
      expect(decoded, isNotNull);
      expect(decoded!.text.length, kAnnotationTextMaxLength);
    });

    test('undecodable annotations yield null, never an exception', () {
      expect(Annotation.fromJson(null), isNull);
      expect(Annotation.fromJson('nope'), isNull);
      // Missing id.
      expect(
        Annotation.fromJson({
          'shape': 'callout',
          'anchor': {'kind': 'point', 'time': 1, 'rowId': 'r'},
        }),
        isNull,
      );
      // Unknown shape — e.g. a document written by a newer build.
      expect(
        Annotation.fromJson({
          'id': 'x',
          'shape': 'hexagon',
          'anchor': {'kind': 'point', 'time': 1, 'rowId': 'r'},
        }),
        isNull,
      );
      // Unusable anchor.
      expect(
        Annotation.fromJson({
          'id': 'x',
          'shape': 'callout',
          'anchor': {'kind': 'point'},
        }),
        isNull,
      );
    });

    test('a malformed timestamp degrades to the epoch rather than failing', () {
      final json = _full().toJson()..['createdAt'] = 'not-a-date';
      final decoded = Annotation.fromJson(json);
      expect(decoded, isNotNull);
      expect(decoded!.createdAt.millisecondsSinceEpoch, 0);
    });
  });

  group('Annotation derived accessors', () {
    test('sortTime uses the point tick and the range start', () {
      final point = _full();
      expect(point.sortTime, 1250);

      final band = Annotation(
        id: 'b',
        shape: AnnotationShape.band,
        anchor: const RangeAnchor(startTime: 900, endTime: 400),
        authorName: 'A',
        createdAt: DateTime.utc(2026),
      );
      expect(band.sortTime, 400, reason: 'earlier end, not authored order');
    });

    test('rowId is null only for a full-height band', () {
      expect(_full().rowId, 'top.cpu.alu_result');

      final fullHeight = Annotation(
        id: 'b',
        shape: AnnotationShape.band,
        anchor: const RangeAnchor(startTime: 1, endTime: 2),
        authorName: 'A',
        createdAt: DateTime.utc(2026),
      );
      expect(fullHeight.rowId, isNull);
    });

    test('hasText ignores whitespace-only bodies', () {
      final blank = _full().copyWith(text: '   \n ');
      expect(blank.hasText, isFalse);
      expect(_full().hasText, isTrue);
    });
  });

  group('Annotation copyWith', () {
    test('changes only the named field', () {
      final original = _full();
      final moved = original.copyWith(labelDx: 999);
      expect(moved.labelDx, 999);
      expect(moved.labelDy, original.labelDy);
      expect(moved.anchor, original.anchor);
      expect(moved.text, original.text);
      expect(moved.witness, original.witness);
      expect(moved.id, original.id);
    });

    test('dragging the label never moves the anchor', () {
      final original = _full();
      final dragged = original.copyWith(labelDx: 10, labelDy: 10);
      expect(dragged.anchor, same(original.anchor));
    });

    test('explicit clears null the nullable fields', () {
      final cleared = _full().copyWith(
        clearColor: true,
        clearWitness: true,
        clearLayer: true,
      );
      expect(cleared.colorRgb, isNull);
      expect(cleared.witness, isNull);
      expect(cleared.layerId, isNull);
      // And the non-cleared fields survive.
      expect(cleared.text, _full().text);
    });
  });

  group('Annotation equality', () {
    test('identical content compares equal and hashes equal', () {
      expect(_full(), _full());
      expect(_full().hashCode, _full().hashCode);
    });

    test('a differing anchor breaks equality', () {
      final moved = _full().copyWith(
        anchor: const PointAnchor(time: 1251, rowId: 'top.cpu.alu_result'),
      );
      expect(moved == _full(), isFalse);
    });

    test('a differing witness breaks equality', () {
      final rewitnessed = _full().copyWith(
        witness: const AnnotationWitness(bits: '00000000'),
      );
      expect(rewitnessed == _full(), isFalse);
    });
  });
}
