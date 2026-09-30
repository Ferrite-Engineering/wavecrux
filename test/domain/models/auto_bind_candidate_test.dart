// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';

void main() {
  group('AutoBindCandidate', () {
    const candidate = AutoBindCandidate(
      signalRef: 'tb.dut.m_axi_aclk',
      confidence: AutoBindConfidence.exactSuffix,
      matchReason: 'shared prefix m_axi_',
      alternatives: ['tb.dut.s_axi_aclk'],
    );

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const other = AutoBindCandidate(
        signalRef: 'tb.dut.m_axi_aclk',
        confidence: AutoBindConfidence.exactSuffix,
        matchReason: 'shared prefix m_axi_',
        alternatives: ['tb.dut.s_axi_aclk'],
      );
      expect(candidate, equals(other));
      expect(candidate.hashCode, equals(other.hashCode));
    });

    test('identical instances are equal', () {
      expect(candidate, equals(candidate));
    });

    test('not equal when signalRef differs', () {
      const other = AutoBindCandidate(
        signalRef: 'tb.dut.other',
        confidence: AutoBindConfidence.exactSuffix,
        matchReason: 'shared prefix m_axi_',
      );
      expect(candidate, isNot(equals(other)));
    });

    test('not equal when confidence differs', () {
      const other = AutoBindCandidate(
        signalRef: 'tb.dut.m_axi_aclk',
        confidence: AutoBindConfidence.fuzzyMatch,
        matchReason: 'shared prefix m_axi_',
      );
      expect(candidate, isNot(equals(other)));
    });

    test('not equal when matchReason differs', () {
      const other = AutoBindCandidate(
        signalRef: 'tb.dut.m_axi_aclk',
        confidence: AutoBindConfidence.exactSuffix,
        matchReason: 'different reason',
      );
      expect(candidate, isNot(equals(other)));
    });

    test('not equal when alternatives differ', () {
      const other = AutoBindCandidate(
        signalRef: 'tb.dut.m_axi_aclk',
        confidence: AutoBindConfidence.exactSuffix,
        matchReason: 'shared prefix m_axi_',
        alternatives: ['tb.dut.different'],
      );
      expect(candidate, isNot(equals(other)));
    });

    test('not equal when alternatives length differs', () {
      const other = AutoBindCandidate(
        signalRef: 'tb.dut.m_axi_aclk',
        confidence: AutoBindConfidence.exactSuffix,
        matchReason: 'shared prefix m_axi_',
      );
      expect(candidate, isNot(equals(other)));
    });

    test('null signalRef equals null signalRef', () {
      const a = AutoBindCandidate(
        signalRef: null,
        confidence: AutoBindConfidence.noMatch,
        matchReason: 'no plausible signal',
      );
      const b = AutoBindCandidate(
        signalRef: null,
        confidence: AutoBindConfidence.noMatch,
        matchReason: 'no plausible signal',
      );
      expect(a, equals(b));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith returns equal when no args', () {
      expect(candidate.copyWith(), equals(candidate));
    });

    test('copyWith updates signalRef', () {
      final updated = candidate.copyWith(signalRef: 'tb.dut.other');
      expect(updated.signalRef, 'tb.dut.other');
      expect(updated.confidence, candidate.confidence);
    });

    test('copyWith updates confidence', () {
      final updated = candidate.copyWith(
        confidence: AutoBindConfidence.knownAlias,
      );
      expect(updated.confidence, AutoBindConfidence.knownAlias);
    });

    test('copyWith updates matchReason', () {
      final updated = candidate.copyWith(matchReason: 'new reason');
      expect(updated.matchReason, 'new reason');
    });

    test('copyWith updates alternatives', () {
      final updated = candidate.copyWith(alternatives: ['x', 'y']);
      expect(updated.alternatives, ['x', 'y']);
    });

    test('clearSignalRef sets signalRef to null', () {
      expect(candidate.copyWith(clearSignalRef: true).signalRef, isNull);
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains signalRef and confidence', () {
      final s = candidate.toString();
      expect(s, contains('m_axi_aclk'));
      expect(s, contains('exactSuffix'));
    });
  });
}
