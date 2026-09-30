// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/auto_bind_result.dart';

void main() {
  group('AutoBindResult', () {
    const exactCandidate = AutoBindCandidate(
      signalRef: 'tb.dut.m_axi_aclk',
      confidence: AutoBindConfidence.exactSuffix,
      matchReason: 'shared prefix m_axi_',
    );
    const fuzzyCandidate = AutoBindCandidate(
      signalRef: 'tb.dut.awvld',
      confidence: AutoBindConfidence.fuzzyMatch,
      matchReason: 'fuzzy',
    );
    const noMatchCandidate = AutoBindCandidate(
      signalRef: null,
      confidence: AutoBindConfidence.noMatch,
      matchReason: 'no plausible signal',
    );

    const result = AutoBindResult(
      candidates: {
        'aclk': exactCandidate,
        'awvalid': fuzzyCandidate,
        'wstrb': noMatchCandidate,
      },
      detectedPrefix: 'm_axi_',
      detectedScopePath: 'tb.dut',
    );

    // ── computed ──────────────────────────────────────────────────────────────

    test('exactMatchCount counts only exactSuffix entries', () {
      expect(result.exactMatchCount, 1);
    });

    test('exactMatchCount is 0 when no exact matches', () {
      const fuzzyOnly = AutoBindResult(
        candidates: {
          'a': AutoBindCandidate(
            signalRef: 'x',
            confidence: AutoBindConfidence.fuzzyMatch,
            matchReason: 'fuzzy',
          ),
        },
      );
      expect(fuzzyOnly.exactMatchCount, 0);
    });

    test('hasAmbiguity is false when ambiguousPrefixes empty', () {
      expect(result.hasAmbiguity, isFalse);
    });

    test('hasAmbiguity is true when ambiguousPrefixes non-empty', () {
      const ambiguous = AutoBindResult(
        candidates: {},
        ambiguousPrefixes: ['m_axi_', 's_axi_'],
      );
      expect(ambiguous.hasAmbiguity, isTrue);
    });

    test('isEmpty is true for empty candidates map', () {
      const empty = AutoBindResult(candidates: {});
      expect(empty.isEmpty, isTrue);
    });

    test('isEmpty is false when candidates present', () {
      expect(result.isEmpty, isFalse);
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const other = AutoBindResult(
        candidates: {
          'aclk': exactCandidate,
          'awvalid': fuzzyCandidate,
          'wstrb': noMatchCandidate,
        },
        detectedPrefix: 'm_axi_',
        detectedScopePath: 'tb.dut',
      );
      expect(result, equals(other));
      expect(result.hashCode, equals(other.hashCode));
    });

    test('not equal when detectedPrefix differs', () {
      const other = AutoBindResult(
        candidates: {'aclk': exactCandidate},
        detectedPrefix: 'other_',
        detectedScopePath: 'tb.dut',
      );
      const me = AutoBindResult(
        candidates: {'aclk': exactCandidate},
        detectedPrefix: 'm_axi_',
        detectedScopePath: 'tb.dut',
      );
      expect(me, isNot(equals(other)));
    });

    test('not equal when detectedScopePath differs', () {
      const me = AutoBindResult(
        candidates: {'aclk': exactCandidate},
        detectedScopePath: 'tb.dut',
      );
      const other = AutoBindResult(
        candidates: {'aclk': exactCandidate},
        detectedScopePath: 'tb.other',
      );
      expect(me, isNot(equals(other)));
    });

    test('not equal when candidates differ', () {
      const other = AutoBindResult(
        candidates: {'aclk': fuzzyCandidate},
      );
      const me = AutoBindResult(
        candidates: {'aclk': exactCandidate},
      );
      expect(me, isNot(equals(other)));
    });

    test('not equal when ambiguousPrefixes differ', () {
      const a = AutoBindResult(
        candidates: {},
        ambiguousPrefixes: ['m_axi_'],
      );
      const b = AutoBindResult(
        candidates: {},
        ambiguousPrefixes: ['s_axi_'],
      );
      expect(a, isNot(equals(b)));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith returns equal when no args', () {
      expect(result.copyWith(), equals(result));
    });

    test('copyWith updates detectedPrefix', () {
      final updated = result.copyWith(detectedPrefix: 'new_');
      expect(updated.detectedPrefix, 'new_');
      expect(updated.detectedScopePath, result.detectedScopePath);
    });

    test('clearDetectedPrefix nulls the prefix', () {
      final updated = result.copyWith(clearDetectedPrefix: true);
      expect(updated.detectedPrefix, isNull);
    });

    test('clearDetectedScopePath nulls the scope', () {
      final updated = result.copyWith(clearDetectedScopePath: true);
      expect(updated.detectedScopePath, isNull);
    });

    test('copyWith updates ambiguousPrefixes', () {
      final updated = result.copyWith(ambiguousPrefixes: ['x', 'y']);
      expect(updated.ambiguousPrefixes, ['x', 'y']);
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString includes candidate count and prefix', () {
      final s = result.toString();
      expect(s, contains('candidates: 3'));
      expect(s, contains('m_axi_'));
    });
  });
}
