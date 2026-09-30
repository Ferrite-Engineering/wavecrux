// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_filter_state.dart';

void main() {
  group('CocotbFilterState', () {
    test('default values', () {
      const f = CocotbFilterState();
      expect(f.testNameFilter, isNull);
      expect(f.severityFilter, isEmpty);
      expect(f.keywordFilter, '');
    });

    test('equality', () {
      const a = CocotbFilterState(
        testNameFilter: 'test_x',
        severityFilter: {CocotbLogSeverity.info},
        keywordFilter: 'reset',
      );
      const b = CocotbFilterState(
        testNameFilter: 'test_x',
        severityFilter: {CocotbLogSeverity.info},
        keywordFilter: 'reset',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equality with severity set order independence', () {
      const a = CocotbFilterState(
        severityFilter: {CocotbLogSeverity.info, CocotbLogSeverity.error},
      );
      const b = CocotbFilterState(
        severityFilter: {CocotbLogSeverity.error, CocotbLogSeverity.info},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on testName', () {
      expect(
        const CocotbFilterState(testNameFilter: 'a'),
        isNot(const CocotbFilterState(testNameFilter: 'b')),
      );
    });

    test('inequality on severity set', () {
      expect(
        const CocotbFilterState(
          severityFilter: {CocotbLogSeverity.info},
        ),
        isNot(
          const CocotbFilterState(
            severityFilter: {CocotbLogSeverity.error},
          ),
        ),
      );
    });

    test('inequality on keyword', () {
      expect(
        const CocotbFilterState(keywordFilter: 'a'),
        isNot(const CocotbFilterState(keywordFilter: 'b')),
      );
    });

    test('inequality on severity set length', () {
      expect(
        const CocotbFilterState(
          severityFilter: {CocotbLogSeverity.info},
        ),
        isNot(
          const CocotbFilterState(
            severityFilter: {
              CocotbLogSeverity.info,
              CocotbLogSeverity.error,
            },
          ),
        ),
      );
    });

    test('copyWith preserves unspecified fields', () {
      const f = CocotbFilterState(
        testNameFilter: 'test_x',
        severityFilter: {CocotbLogSeverity.info},
        keywordFilter: 'reset',
      );
      final copy = f.copyWith(keywordFilter: 'clk');
      expect(copy.testNameFilter, 'test_x');
      expect(copy.severityFilter, {CocotbLogSeverity.info});
      expect(copy.keywordFilter, 'clk');
    });

    test('copyWith can clear testNameFilter', () {
      const f = CocotbFilterState(testNameFilter: 'test_x');
      final cleared = f.copyWith(testNameFilter: null);
      expect(cleared.testNameFilter, isNull);
    });

    test('toString includes core fields', () {
      const f = CocotbFilterState(
        testNameFilter: 'test_x',
        severityFilter: {CocotbLogSeverity.warning},
        keywordFilter: 'irq',
      );
      final s = f.toString();
      expect(s, contains('test_x'));
      expect(s, contains('WARNING'));
      expect(s, contains('irq'));
    });

    test('identical comparison short-circuit', () {
      const f = CocotbFilterState(testNameFilter: 'a');
      expect(f == f, isTrue);
    });

    test('not equal to other types', () {
      const f = CocotbFilterState();
      // Cast to Object so the static checker permits the comparison.
      expect((f as Object) == 'string', isFalse);
    });
  });
}
