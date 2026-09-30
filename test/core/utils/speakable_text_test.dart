// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/utils/speakable_text.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _en = SpeakableGlyphWords(
  to: 'to',
  from: 'from',
  both: 'to and from',
  up: 'up',
  down: 'down',
);

/// The exact character class of `crux_a11y`'s `unspeakableGlyph` rule and of
/// `speakable_strings_test.dart`, written out independently so a drift in
/// [kUnspeakableGlyph] cannot silently shrink what is tested.
const _unspeakableRanges = <(int, int)>[
  (0x2190, 0x21FF),
  (0x2500, 0x25FF),
  (0x27F0, 0x27FF),
  (0x2900, 0x297F),
  (0xE000, 0xF8FF),
];

void main() {
  group('speakableText', () {
    test('decoder labels read with words instead of arrows', () {
      expect(
        speakableText('R 0x00000008 → 0x12345678', _en),
        'R 0x00000008 to 0x12345678',
      );
      expect(speakableText('Eth src→dst IPv4', _en), 'Eth src to dst IPv4');
      expect(speakableText('[0x10] ← 0xFF', _en), '[0x10] from 0xFF');
      expect(speakableText('A ↔ B', _en), 'A to and from B');
      expect(speakableText('edges: ↑3/↓2', _en), 'edges: up 3/ down 2');
      expect(speakableText('▼ A', _en), 'down A');
    });

    test('shapes, box drawing and private-use glyphs are dropped', () {
      expect(speakableText('● busy ─ ok', _en), 'busy ok');
      expect(speakableText('icon name', _en), 'icon name');
    });

    test('text with nothing to convert is returned unchanged', () {
      const label = 'W 0x00000004 = 0xDEADBEEF  [OKAY]';
      expect(identical(speakableText(label, _en), label), isTrue);
    });

    test('every glyph in the unspeakable set comes out speakable', () {
      var checked = 0;
      for (final (first, last) in _unspeakableRanges) {
        for (var rune = first; rune <= last; rune++) {
          final glyph = String.fromCharCode(rune);
          expect(kUnspeakableGlyph.hasMatch(glyph), isTrue, reason: glyph);
          final spoken = speakableText('a${glyph}b', _en);
          expect(
            kUnspeakableGlyph.hasMatch(spoken),
            isFalse,
            reason: 'U+${rune.toRadixString(16).toUpperCase()} -> "$spoken"',
          );
          expect(spoken, anyOf('a b', startsWith('a '), contains(' b')));
          checked++;
        }
      }
      expect(checked, 0x70 + 0x100 + 0x10 + 0x80 + 0x1900);
    });

    test('characters just outside the set are left alone', () {
      for (final rune in const [0x218F, 0x2200, 0x24FF, 0x2600, 0xDFFF]) {
        final text = 'a${String.fromCharCode(rune)}b';
        expect(speakableText(text, _en), text);
      }
    });

    testWidgets('the words come from the locale', (tester) async {
      for (final locale in L10N.supportedLocales) {
        final l10n = await L10N.delegate.load(locale);
        final words = SpeakableGlyphWords.of(l10n);
        final spoken = speakableText('R 0x08 → 0xFF', words);
        expect(spoken, 'R 0x08 ${words.to} 0xFF', reason: '$locale');
        expect(kUnspeakableGlyph.hasMatch(spoken), isFalse);
        for (final word in [
          words.to,
          words.from,
          words.both,
          words.up,
          words.down,
        ]) {
          expect(word.trim(), isNotEmpty, reason: '$locale');
        }
      }
    });
  });
}
