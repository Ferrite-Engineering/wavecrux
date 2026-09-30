// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';

const _base = MemoryStats(
  wellenEstimateBytes: 356515840,
  loadedSignalCount: 85,
  totalSignalCount: 3200,
  dartProcessRssBytes: 536870912,
);

void main() {
  group('MemoryStats', () {
    test('stores all fields', () {
      expect(_base.wellenEstimateBytes, 356515840);
      expect(_base.loadedSignalCount, 85);
      expect(_base.totalSignalCount, 3200);
      expect(_base.dartProcessRssBytes, 536870912);
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      expect(_base.copyWith(), equals(_base));
    });

    test('copyWith changes only loadedSignalCount', () {
      final updated = _base.copyWith(loadedSignalCount: 100);
      expect(updated.loadedSignalCount, 100);
      expect(updated.wellenEstimateBytes, _base.wellenEstimateBytes);
      expect(updated.totalSignalCount, _base.totalSignalCount);
      expect(updated.dartProcessRssBytes, _base.dartProcessRssBytes);
    });

    test('copyWith changes only dartProcessRssBytes', () {
      final updated = _base.copyWith(dartProcessRssBytes: 1073741824);
      expect(updated.dartProcessRssBytes, 1073741824);
      expect(updated.loadedSignalCount, _base.loadedSignalCount);
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal objects compare as equal', () {
      final a = _base.copyWith();
      final b = _base.copyWith();
      expect(a, equals(b));
    });

    test('differing wellenEstimateBytes makes objects unequal', () {
      final a = _base.copyWith(wellenEstimateBytes: 100);
      final b = _base.copyWith(wellenEstimateBytes: 200);
      expect(a, isNot(equals(b)));
    });

    test('differing loadedSignalCount makes objects unequal', () {
      final a = _base.copyWith(loadedSignalCount: 1);
      final b = _base.copyWith(loadedSignalCount: 2);
      expect(a, isNot(equals(b)));
    });

    test('differing totalSignalCount makes objects unequal', () {
      final a = _base.copyWith(totalSignalCount: 100);
      final b = _base.copyWith(totalSignalCount: 200);
      expect(a, isNot(equals(b)));
    });

    // ── hashCode ──────────────────────────────────────────────────────────────

    test('equal objects have equal hashCodes', () {
      final a = _base.copyWith();
      final b = _base.copyWith();
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains loaded/total signal counts', () {
      final s = _base.toString();
      expect(s, contains('85'));
      expect(s, contains('3200'));
    });

    test('toString contains wellen estimate', () {
      expect(_base.toString(), contains('356515840'));
    });
  });
}
