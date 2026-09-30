// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/auto_bind/auto_bind_text.dart';

void main() {
  group('AutoBindText.levenshtein', () {
    test('returns 0 for identical strings', () {
      expect(AutoBindText.levenshtein('foo', 'foo'), 0);
    });

    test('returns string length when one side is empty', () {
      expect(AutoBindText.levenshtein('', 'foo'), 3);
      expect(AutoBindText.levenshtein('foo', ''), 3);
    });

    test('counts single-char substitution', () {
      expect(AutoBindText.levenshtein('led', 'lex'), 1);
    });

    test('counts insertion and deletion', () {
      expect(AutoBindText.levenshtein('aclk', 'a_clk'), 1);
      expect(AutoBindText.levenshtein('a_clk', 'aclk'), 1);
    });

    test('returns 2 for plausible board-aliased mismatches', () {
      expect(AutoBindText.levenshtein('led', 'leds'), 1);
      expect(AutoBindText.levenshtein('sw', 'swc'), 1);
    });

    test('rejects clearly different names with distance > 2', () {
      expect(
        AutoBindText.levenshtein('completely_different', 'led'),
        greaterThan(2),
      );
    });
  });
}
