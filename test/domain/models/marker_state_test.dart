// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/marker_state.dart';

void main() {
  group('MarkerState', () {
    // ── construction ─────────────────────────────────────────────────────────

    test('default state has empty marker map', () {
      const s = MarkerState();
      expect(s.markers, isEmpty);
    });

    test('accepts explicit marker map', () {
      const s = MarkerState(markers: {'a': 100, 'z': 999});
      expect(s.getMarker('a'), 100);
      expect(s.getMarker('z'), 999);
    });

    // ── setMarker ────────────────────────────────────────────────────────────

    test('setMarker adds a new marker', () {
      const s = MarkerState();
      final s2 = s.setMarker('a', 500);
      expect(s2.getMarker('a'), 500);
    });

    test('setMarker overwrites existing marker', () {
      const s = MarkerState();
      final s1 = s.setMarker('b', 100);
      final s2 = s1.setMarker('b', 999);
      expect(s2.getMarker('b'), 999);
    });

    test('setMarker does not mutate original state', () {
      const s = MarkerState();
      final _ = s.setMarker('a', 100);
      expect(s.markers, isEmpty);
    });

    test('setMarker accepts all letters a through z', () {
      var s = const MarkerState();
      for (var code = 0x61; code <= 0x7A; code++) {
        final name = String.fromCharCode(code);
        s = s.setMarker(name, code * 10);
      }
      expect(s.markers.length, 26);
    });

    test('setMarker throws on non-lowercase-letter name', () {
      const s = MarkerState();
      expect(() => s.setMarker('A', 100), throwsAssertionError);
      expect(() => s.setMarker('1', 100), throwsAssertionError);
      expect(() => s.setMarker('ab', 100), throwsAssertionError);
    });

    // ── removeMarker ─────────────────────────────────────────────────────────

    test('removeMarker removes an existing marker', () {
      const s = MarkerState();
      final s2 = s.setMarker('a', 100).removeMarker('a');
      expect(s2.getMarker('a'), isNull);
    });

    test('removeMarker returns same instance when marker does not exist', () {
      const s = MarkerState();
      final s2 = s.removeMarker('x');
      expect(identical(s, s2), isTrue);
    });

    test('removeMarker does not affect other markers', () {
      const s = MarkerState();
      final s2 = s.setMarker('a', 100).setMarker('b', 200).removeMarker('a');
      expect(s2.getMarker('a'), isNull);
      expect(s2.getMarker('b'), 200);
    });

    // ── getMarker ────────────────────────────────────────────────────────────

    test('getMarker returns null for unset marker', () {
      const s = MarkerState();
      expect(s.getMarker('a'), isNull);
    });

    test('getMarker returns the correct time', () {
      final s = const MarkerState().setMarker('m', 12345);
      expect(s.getMarker('m'), 12345);
    });

    // ── getAllMarkers ─────────────────────────────────────────────────────────

    test('getAllMarkers returns empty list when no markers set', () {
      const s = MarkerState();
      expect(s.getAllMarkers(), isEmpty);
    });

    test('getAllMarkers returns markers sorted alphabetically by name', () {
      final s = const MarkerState()
          .setMarker('z', 300)
          .setMarker('a', 100)
          .setMarker('m', 200);
      final all = s.getAllMarkers();
      expect(all.map((e) => e.key).toList(), ['a', 'm', 'z']);
      expect(all.map((e) => e.value).toList(), [100, 200, 300]);
    });

    test('getAllMarkers returns single marker correctly', () {
      final s = const MarkerState().setMarker('c', 42);
      final all = s.getAllMarkers();
      expect(all.length, 1);
      expect(all.first.key, 'c');
      expect(all.first.value, 42);
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      final s = const MarkerState().setMarker('a', 100);
      expect(s.copyWith(), equals(s));
    });

    test('copyWith(markers:) replaces the map', () {
      final s = const MarkerState().setMarker('a', 100);
      final s2 = s.copyWith(markers: const {'b': 200});
      expect(s2.getMarker('a'), isNull);
      expect(s2.getMarker('b'), 200);
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('two default states are equal', () {
      const a = MarkerState();
      const b = MarkerState();
      expect(a, equals(b));
    });

    test('equal when markers map matches', () {
      final a = const MarkerState().setMarker('a', 100).setMarker('b', 200);
      final b = const MarkerState().setMarker('a', 100).setMarker('b', 200);
      expect(a, equals(b));
    });

    test('not equal when marker values differ', () {
      final a = const MarkerState().setMarker('a', 100);
      final b = const MarkerState().setMarker('a', 200);
      expect(a, isNot(equals(b)));
    });

    test('not equal when marker sets differ in size', () {
      final a = const MarkerState().setMarker('a', 100);
      final b = const MarkerState().setMarker('a', 100).setMarker('b', 200);
      expect(a, isNot(equals(b)));
    });

    test('not equal when marker names differ', () {
      final a = const MarkerState().setMarker('a', 100);
      final b = const MarkerState().setMarker('b', 100);
      expect(a, isNot(equals(b)));
    });

    test('hashCode equal for equal states', () {
      final a = const MarkerState().setMarker('a', 100);
      final b = const MarkerState().setMarker('a', 100);
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString contains marker data', () {
      final s = const MarkerState().setMarker('a', 100);
      expect(s.toString(), allOf(contains('a'), contains('100')));
    });
  });
}
