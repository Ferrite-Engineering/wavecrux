// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/natural_compare.dart';

void main() {
  group('naturalCompare', () {
    test('digit runs compare numerically, not lexicographically', () {
      // Kevin's gate-level report: [0] [1] … [11] [12] must order by value.
      final names = ['[10]', '[2]', '[0]', '[12]', '[1]', '[11]']
        ..sort(naturalCompare);
      expect(names, ['[0]', '[1]', '[2]', '[10]', '[11]', '[12]']);
    });

    test('mixed text and numbers order naturally', () {
      final names = ['data10', 'data9', 'data1', 'addr2', 'addr10']
        ..sort(naturalCompare);
      expect(names, ['addr2', 'addr10', 'data1', 'data9', 'data10']);
    });

    test('multiple digit runs are each compared numerically', () {
      final names = ['x2_y10', 'x2_y9', 'x10_y1']..sort(naturalCompare);
      expect(names, ['x2_y9', 'x2_y10', 'x10_y1']);
    });

    test('case-insensitive primary order with deterministic tiebreak', () {
      expect(naturalCompare('Clk', 'data'), lessThan(0));
      expect(naturalCompare('DATA', 'data'), isNot(0));
      expect(
        naturalCompare('DATA', 'data'),
        -naturalCompare('data', 'DATA'),
        reason: 'tiebreak must be antisymmetric',
      );
    });

    test('leading zeros: numerically equal values still order '
        'deterministically', () {
      expect(naturalCompare('x01', 'x1'), isNot(0));
      expect(naturalCompare('x01', 'x1'), -naturalCompare('x1', 'x01'));
      // Numeric value dominates padding: x002 < x10 despite '0' < '1'.
      expect(naturalCompare('x002', 'x10'), lessThan(0));
    });

    test('prefix relationships: shorter string first', () {
      expect(naturalCompare('clk', 'clk_en'), lessThan(0));
      expect(naturalCompare('bus[1]', 'bus[1]a'), lessThan(0));
    });

    test('equal strings compare zero', () {
      expect(naturalCompare('wb_clk_i', 'wb_clk_i'), 0);
      expect(naturalCompare('', ''), 0);
    });

    test('long digit runs beyond int range still compare by value', () {
      expect(
        naturalCompare('n99999999999999999998', 'n99999999999999999999'),
        lessThan(0),
      );
    });

    test('escaped gate-level identifiers with embedded dots sort stably', () {
      final names = [
        r'\core.u_fifo.valid',
        r'\core.u_fifo.data[10]',
        r'\core.u_fifo.data[2]',
      ]..sort(naturalCompare);
      expect(names, [
        r'\core.u_fifo.data[2]',
        r'\core.u_fifo.data[10]',
        r'\core.u_fifo.valid',
      ]);
    });
  });
}
