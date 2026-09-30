// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';

void main() {
  group('FsmAnnotation', () {
    test('preserves signalRef and labels', () {
      const a = FsmAnnotation(
        signalRef: 'r1',
        stateLabels: {'0': 'IDLE', '1': 'RUN'},
      );
      expect(a.signalRef, 'r1');
      expect(a.stateLabels['0'], 'IDLE');
      expect(a.stateLabels['1'], 'RUN');
    });

    test('hasLabels reflects the map', () {
      const empty = FsmAnnotation(
        signalRef: 'r',
        stateLabels: <String, String>{},
      );
      const full = FsmAnnotation(signalRef: 'r', stateLabels: {'0': 'X'});
      expect(empty.hasLabels, isFalse);
      expect(full.hasLabels, isTrue);
    });

    test('labelFor returns label or null', () {
      const a = FsmAnnotation(
        signalRef: 'r',
        stateLabels: {'0': 'IDLE'},
      );
      expect(a.labelFor('0'), 'IDLE');
      expect(a.labelFor('1'), isNull);
    });

    test('equality is structural', () {
      const a = FsmAnnotation(
        signalRef: 'r',
        stateLabels: {'0': 'A', '1': 'B'},
      );
      const b = FsmAnnotation(
        signalRef: 'r',
        stateLabels: {'0': 'A', '1': 'B'},
      );
      const c = FsmAnnotation(
        signalRef: 'r',
        stateLabels: {'0': 'A'},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('copyWith updates fields', () {
      const a = FsmAnnotation(
        signalRef: 'r',
        stateLabels: {'0': 'IDLE'},
      );
      expect(a.copyWith(signalRef: 'r2').signalRef, 'r2');
      expect(
        a.copyWith(stateLabels: {'5': 'NEW'}).stateLabels['5'],
        'NEW',
      );
    });

    group('JSON', () {
      test('round-trips through toJson/fromJson', () {
        const a = FsmAnnotation(
          signalRef: 'top.fsm.state',
          stateLabels: {'0': 'IDLE', '1': 'RUN', '2': 'STOP'},
        );
        final restored = FsmAnnotation.fromJson(a.toJson());
        expect(restored, equals(a));
        expect(restored.signalRef, 'top.fsm.state');
        expect(restored.stateLabels, {'0': 'IDLE', '1': 'RUN', '2': 'STOP'});
      });

      test('toJson uses signalRef and labels keys', () {
        const a = FsmAnnotation(
          signalRef: 'r',
          stateLabels: {'0': 'A'},
        );
        final json = a.toJson();
        expect(json['signalRef'], 'r');
        expect(json['labels'], {'0': 'A'});
      });

      test('fromJson degrades gracefully on missing/malformed fields', () {
        // No fields at all → empty ref, no labels.
        final empty = FsmAnnotation.fromJson(const {});
        expect(empty.signalRef, '');
        expect(empty.stateLabels, isEmpty);

        // Non-string label values are skipped; string ones survive.
        final mixed = FsmAnnotation.fromJson(const {
          'signalRef': 'r',
          'labels': {'0': 'OK', '1': 42, '2': null},
        });
        expect(mixed.signalRef, 'r');
        expect(mixed.stateLabels, {'0': 'OK'});

        // labels of the wrong type → empty map, no throw.
        final badLabels = FsmAnnotation.fromJson(const {
          'signalRef': 'r',
          'labels': 'nope',
        });
        expect(badLabels.stateLabels, isEmpty);
      });
    });
  });
}
