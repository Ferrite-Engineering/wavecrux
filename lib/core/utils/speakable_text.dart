// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Arrows, box drawing, block elements, geometric shapes and the private use
/// area: the glyphs desktop speech engines read as a question mark or skip.
///
/// The same character class as the focus walk's `unspeakableGlyph` rule
/// (`crux_a11y`) and `test/static/speakable_strings_test.dart`.
final RegExp kUnspeakableGlyph = RegExp(
  '[←-⇿─-◿⟰-⟿⤀-⥿-]',
);

/// The words an unspeakable glyph is read as, in the current locale.
@immutable
class SpeakableGlyphWords {
  /// Creates the word set.
  const SpeakableGlyphWords({
    required this.to,
    required this.from,
    required this.both,
    required this.up,
    required this.down,
  });

  /// The word set for [l10n]'s locale.
  factory SpeakableGlyphWords.of(L10N l10n) => SpeakableGlyphWords(
    to: l10n.speakableGlyphTo,
    from: l10n.speakableGlyphFrom,
    both: l10n.speakableGlyphBoth,
    up: l10n.speakableGlyphUp,
    down: l10n.speakableGlyphDown,
  );

  /// A rightward arrow, as in `R 0x08 → 0xFF` or `src→dst`.
  final String to;

  /// A leftward arrow, as in `[addr] ← data`.
  final String from;

  /// A two-headed horizontal arrow.
  final String both;

  /// An upward arrow or triangle.
  final String up;

  /// A downward arrow or triangle.
  final String down;
}

/// [text] with every unspeakable glyph replaced by a word a screen reader can
/// say, for semantics only — the visible text keeps its glyphs.
///
/// Decoders write compact labels such as `R 0x00000008 → 0x12345678`, and
/// those labels are data: fixture snapshots pin them byte for byte. A screen
/// reader reads the arrow as "?", so the spoken form is converted where a
/// label reaches semantics instead of where it is produced. Directional
/// arrows become the connecting words in [words]; any other arrow becomes
/// [SpeakableGlyphWords.to]; box drawing, block, shape and private-use
/// glyphs, which carry no word, are dropped. Whitespace is collapsed, so
/// `src→dst` reads "src to dst".
String speakableText(String text, SpeakableGlyphWords words) {
  if (!kUnspeakableGlyph.hasMatch(text)) return text;
  final out = StringBuffer();
  for (final rune in text.runes) {
    final word = _wordFor(rune, words);
    if (word == null) {
      out.writeCharCode(rune);
    } else {
      out.write(word.isEmpty ? ' ' : ' $word ');
    }
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The word for [rune], an empty string for a glyph that is dropped, or null
/// when [rune] is not an unspeakable glyph.
String? _wordFor(int rune, SpeakableGlyphWords words) {
  if (_toRunes.contains(rune)) return words.to;
  if (_fromRunes.contains(rune)) return words.from;
  if (_bothRunes.contains(rune)) return words.both;
  if (_upRunes.contains(rune)) return words.up;
  if (_downRunes.contains(rune)) return words.down;
  final isArrow =
      (rune >= 0x2190 && rune <= 0x21FF) ||
      (rune >= 0x27F0 && rune <= 0x27FF) ||
      (rune >= 0x2900 && rune <= 0x297F);
  if (isArrow) return words.to;
  final isShapeOrPrivate =
      (rune >= 0x2500 && rune <= 0x25FF) || (rune >= 0xE000 && rune <= 0xF8FF);
  return isShapeOrPrivate ? '' : null;
}

const Set<int> _toRunes = {
  0x2192, // →
  0x219B, // ↛
  0x219D, // ↝
  0x21A0, // ↠
  0x21A3, // ↣
  0x21A6, // ↦
  0x21AA, // ↪
  0x21C0, // ⇀
  0x21C1, // ⇁
  0x21D2, // ⇒
  0x21E2, // ⇢
  0x21E8, // ⇨
  0x21FE, // ⇾
  0x27F6, // ⟶
  0x27F9, // ⟹
  0x27FC, // ⟼
  0x2933, // ⤳
};

const Set<int> _fromRunes = {
  0x2190, // ←
  0x219A, // ↚
  0x219C, // ↜
  0x219E, // ↞
  0x21A2, // ↢
  0x21A4, // ↤
  0x21A9, // ↩
  0x21BC, // ↼
  0x21BD, // ↽
  0x21D0, // ⇐
  0x21E0, // ⇠
  0x21E6, // ⇦
  0x21FD, // ⇽
  0x27F5, // ⟵
  0x27F8, // ⟸
  0x27FB, // ⟻
};

const Set<int> _bothRunes = {
  0x2194, // ↔
  0x21AD, // ↭
  0x21AE, // ↮
  0x21C4, // ⇄
  0x21C6, // ⇆
  0x21CB, // ⇋
  0x21CC, // ⇌
  0x21D4, // ⇔
  0x27F7, // ⟷
  0x27FA, // ⟺
};

const Set<int> _upRunes = {
  0x2191, // ↑
  0x219F, // ↟
  0x21A5, // ↥
  0x21D1, // ⇑
  0x21E1, // ⇡
  0x21E7, // ⇧
  0x27F0, // ⟰
  0x25B2, // ▲
  0x25B3, // △
  0x25B4, // ▴
  0x25B5, // ▵
};

const Set<int> _downRunes = {
  0x2193, // ↓
  0x21A1, // ↡
  0x21A7, // ↧
  0x21D3, // ⇓
  0x21E3, // ⇣
  0x21E9, // ⇩
  0x27F1, // ⟱
  0x25BC, // ▼
  0x25BD, // ▽
  0x25BE, // ▾
  0x25BF, // ▿
};
