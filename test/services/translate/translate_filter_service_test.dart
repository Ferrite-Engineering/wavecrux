// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';

void main() {
  const svc = TranslateFilterService();

  // ── TranslateFilter.translate ──────────────────────────────────────────────

  group('TranslateFilter.translate', () {
    test('exact decimal match returns label', () {
      final filter = svc.parse('0 IDLE\n1 RUNNING\n2 DONE');
      expect(filter.translate('0'), 'IDLE');
      expect(filter.translate('1'), 'RUNNING');
      expect(filter.translate('10'), 'DONE');
    });

    test('no match returns null', () {
      final filter = svc.parse('0 IDLE');
      expect(filter.translate('1'), isNull);
    });

    test('x bit returns null (indeterminate)', () {
      final filter = svc.parse('0 IDLE');
      expect(filter.translate('x'), isNull);
      expect(filter.translate('xxxx'), isNull);
      expect(filter.translate('x0x1'), isNull);
    });

    test('z bit returns null (hi-z)', () {
      final filter = svc.parse('0 IDLE');
      expect(filter.translate('z'), isNull);
      expect(filter.translate('zzzz'), isNull);
    });

    test('mixed x/z returns null', () {
      final filter = svc.parse('0 IDLE');
      expect(filter.translate('x0z1'), isNull);
    });

    test('multi-bit vector matches by numeric value', () {
      // "0001" in binary = 1, which should match the entry keyed "1"
      final filter = svc.parse('1 START');
      expect(filter.translate('0001'), 'START');
    });

    test('4-bit 1111 (=15) matches entry keyed 15', () {
      final filter = svc.parse('15 MAX');
      expect(filter.translate('1111'), 'MAX');
    });

    test('8-bit 11111111 (=255) matches entry keyed 255', () {
      final filter = svc.parse('255 OVERFLOW');
      expect(filter.translate('11111111'), 'OVERFLOW');
    });
  });

  // ── TranslateFilterService.parse — decimal keys ───────────────────────────

  group('parse — decimal keys', () {
    test('single entry', () {
      final filter = svc.parse('0 IDLE');
      expect(filter.translate('0'), 'IDLE');
      expect(filter.length, 1);
    });

    test('multiple entries', () {
      final filter = svc.parse('0 IDLE\n1 RUNNING\n2 DONE\n3 ERROR');
      expect(filter.translate('0'), 'IDLE');
      expect(filter.translate('1'), 'RUNNING');
      expect(filter.translate('10'), 'DONE');
      expect(filter.translate('11'), 'ERROR');
      expect(filter.length, 4);
    });

    test('label with spaces is captured in full', () {
      final filter = svc.parse('0 IDLE STATE');
      expect(filter.translate('0'), 'IDLE STATE');
    });

    test('large decimal key', () {
      final filter = svc.parse('255 FULL');
      expect(filter.translate('11111111'), 'FULL');
    });
  });

  // ── TranslateFilterService.parse — hex keys ───────────────────────────────

  group('parse — hex keys (0x prefix)', () {
    test('0x00 matches binary 0', () {
      final filter = svc.parse('0x00 NULL');
      expect(filter.translate('0'), 'NULL');
    });

    test('0x01 matches binary 1', () {
      final filter = svc.parse('0x01 ONE');
      expect(filter.translate('1'), 'ONE');
    });

    test('0xFF matches binary 11111111', () {
      final filter = svc.parse('0xFF ERROR_OVERFLOW');
      expect(filter.translate('11111111'), 'ERROR_OVERFLOW');
    });

    test('0x0F matches binary 00001111', () {
      final filter = svc.parse('0x0F HALF');
      expect(filter.translate('00001111'), 'HALF');
    });

    test('hex key is case-insensitive: 0xAB == 0xab', () {
      final filterUpper = svc.parse('0xAB UPPER');
      final filterLower = svc.parse('0xab lower');
      // 0xAB = 171 decimal = 10101011 binary
      expect(filterUpper.translate('10101011'), 'UPPER');
      expect(filterLower.translate('10101011'), 'lower');
    });

    test('0X prefix (uppercase X) is accepted', () {
      final filter = svc.parse('0X10 SIXTEEN');
      // 0x10 = 16 = 00010000
      expect(filter.translate('00010000'), 'SIXTEEN');
    });
  });

  // ── TranslateFilterService.parse — binary keys ────────────────────────────

  group('parse — binary keys (0b prefix)', () {
    test('0b0000 matches binary 0000', () {
      final filter = svc.parse('0b0000 ZERO');
      expect(filter.translate('0000'), 'ZERO');
    });

    test('0b1111 matches binary 1111', () {
      final filter = svc.parse('0b1111 FIFTEEN');
      expect(filter.translate('1111'), 'FIFTEEN');
    });

    test('0B prefix (uppercase) is accepted', () {
      final filter = svc.parse('0B1010 TEN');
      expect(filter.translate('1010'), 'TEN');
    });
  });

  // ── TranslateFilterService.parse — comment and blank line handling ────────

  group('parse — comments and blank lines', () {
    test('lines starting with # are ignored', () {
      final filter = svc.parse('# This is a comment\n0 IDLE\n1 RUNNING');
      expect(filter.length, 2);
      expect(filter.translate('0'), 'IDLE');
    });

    test('lines starting with // are ignored', () {
      final filter = svc.parse('// C-style comment\n0 IDLE');
      expect(filter.length, 1);
    });

    test('blank lines are ignored', () {
      final filter = svc.parse('\n\n0 IDLE\n\n1 RUNNING\n\n');
      expect(filter.length, 2);
    });

    test('mixed comments, blanks, and entries', () {
      const content = '''
# FSM state machine
# Generated by synthesis tool

0 IDLE
1 FETCH
2 DECODE
# Execution states
3 EXECUTE
4 WRITEBACK
''';
      final filter = svc.parse(content);
      expect(filter.length, 5);
      expect(filter.translate('0'), 'IDLE');
      expect(filter.translate('100'), 'WRITEBACK');
    });

    test('lines with only a value and no label are ignored', () {
      final filter = svc.parse('0\n1 RUNNING');
      expect(filter.length, 1);
      expect(filter.translate('1'), 'RUNNING');
    });

    test('leading and trailing whitespace on value is handled', () {
      final filter = svc.parse('  0   IDLE  ');
      expect(filter.length, 1);
      expect(filter.translate('0'), 'IDLE');
    });
  });

  // ── TranslateFilterService.parse — edge cases ─────────────────────────────

  group('parse — edge cases', () {
    test('empty content produces empty filter', () {
      final filter = svc.parse('');
      expect(filter.length, 0);
      expect(filter.translate('0'), isNull);
    });

    test('all-comment content produces empty filter', () {
      final filter = svc.parse('# nothing\n# here\n');
      expect(filter.length, 0);
    });

    test('tab-separated key and label', () {
      final filter = svc.parse('0\tIDLE');
      expect(filter.length, 1);
      expect(filter.translate('0'), 'IDLE');
    });

    test('duplicate keys: last one wins', () {
      // Both map decimal 0; second write to the map wins.
      final filter = svc.parse('0 FIRST\n0 SECOND');
      expect(filter.translate('0'), 'SECOND');
    });

    test('non-numeric key line is ignored', () {
      final filter = svc.parse('abc LABEL\n0 IDLE');
      expect(filter.length, 1);
    });

    test('invalid key with trailing non-digits is ignored', () {
      final filter = svc.parse('0z LABEL\n1 RUNNING');
      expect(filter.length, 1);
    });

    test('very large decimal key (BigInt range)', () {
      // 2^32 - 1 = 4294967295
      final filter = svc.parse('4294967295 MAX32');
      // binary of 2^32-1 = 32 ones
      expect(filter.translate('1' * 32), 'MAX32');
    });
  });

  // ── TranslateFilterService.translateOrRaw ─────────────────────────────────

  group('translateOrRaw', () {
    test('returns label when match found', () {
      final filter = svc.parse('0 IDLE\n1 RUNNING');
      expect(svc.translateOrRaw('0', filter), 'IDLE');
      expect(svc.translateOrRaw('1', filter), 'RUNNING');
    });

    test('returns raw value when no match', () {
      final filter = svc.parse('0 IDLE');
      expect(svc.translateOrRaw('1', filter), '1');
    });

    test('returns raw value for x bits (no match possible)', () {
      final filter = svc.parse('0 IDLE');
      expect(svc.translateOrRaw('xxxx', filter), 'xxxx');
    });

    test('returns raw value for z bits', () {
      final filter = svc.parse('0 IDLE');
      expect(svc.translateOrRaw('zzzz', filter), 'zzzz');
    });
  });

  // ── TranslateFilter equality ───────────────────────────────────────────────

  group('TranslateFilter equality', () {
    test('two filters with same entries are equal', () {
      final a = svc.parse('0 IDLE\n1 RUNNING');
      final b = svc.parse('0 IDLE\n1 RUNNING');
      expect(a, equals(b));
    });

    test('filters with different entries are not equal', () {
      final a = svc.parse('0 IDLE\n1 RUNNING');
      final b = svc.parse('0 IDLE\n1 DONE');
      expect(a, isNot(equals(b)));
    });

    test('empty filters are equal', () {
      expect(svc.parse(''), equals(svc.parse('')));
    });

    test('filter with hex key equals filter with equivalent decimal key', () {
      final a = svc.parse('0xFF FULL');
      final b = svc.parse('255 FULL');
      expect(a, equals(b));
    });
  });

  // ── real-world GTKWave-style filter example ───────────────────────────────

  group('real-world GTKWave filter', () {
    const gtkwaveFilter = '''
# AXI response codes
# Source: ARM IHI 0022 Table A3-4
0 OKAY
1 EXOKAY
2 SLVERR
3 DECERR
''';

    test('parses all 4 AXI response codes', () {
      final filter = svc.parse(gtkwaveFilter);
      expect(filter.length, 4);
    });

    test('translates OKAY (0b00 = 0)', () {
      final filter = svc.parse(gtkwaveFilter);
      expect(filter.translate('00'), 'OKAY');
    });

    test('translates EXOKAY (0b01 = 1)', () {
      final filter = svc.parse(gtkwaveFilter);
      expect(filter.translate('01'), 'EXOKAY');
    });

    test('translates SLVERR (0b10 = 2)', () {
      final filter = svc.parse(gtkwaveFilter);
      expect(filter.translate('10'), 'SLVERR');
    });

    test('translates DECERR (0b11 = 3)', () {
      final filter = svc.parse(gtkwaveFilter);
      expect(filter.translate('11'), 'DECERR');
    });

    test('x response (unknown) returns null', () {
      final filter = svc.parse(gtkwaveFilter);
      expect(filter.translate('xx'), isNull);
    });
  });
}
