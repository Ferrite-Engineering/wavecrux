// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Natural (alphanumeric) string comparison: runs of digits compare by
/// numeric value, everything else case-insensitively, so `x[2]` sorts before
/// `x[11]` and `data9` before `data10` — the order an engineer expects from
/// a hierarchy browser, and the opposite of what plain lexicographic order
/// gives gate-level names like `[0] [1] [10] [11] … [2]`.
///
/// Total order: case-insensitive natural comparison first; on a full tie
/// (`Data1` vs `data1`, `x01` vs `x1`) falls back to plain lexicographic
/// comparison so equal-ranked names still order deterministically.
int naturalCompare(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final da = _isDigit(ca);
    final db = _isDigit(cb);
    if (da && db) {
      // Compare the two digit runs numerically without parsing to int
      // (names can carry arbitrarily long runs): skip leading zeros, then
      // longer run wins, then first differing digit decides.
      final sa = _skipZeros(a, i);
      final sb = _skipZeros(b, j);
      final ea = _endOfDigits(a, sa);
      final eb = _endOfDigits(b, sb);
      final la = ea - sa;
      final lb = eb - sb;
      if (la != lb) return la - lb;
      for (var k = 0; k < la; k++) {
        final d = a.codeUnitAt(sa + k) - b.codeUnitAt(sb + k);
        if (d != 0) return d;
      }
      i = ea;
      j = eb;
    } else {
      final fa = _fold(ca);
      final fb = _fold(cb);
      if (fa != fb) return fa - fb;
      i++;
      j++;
    }
  }
  final remaining = (a.length - i) - (b.length - j);
  if (remaining != 0) return remaining;
  // Case-insensitively equal (possibly with different zero-padding) —
  // deterministic tiebreak on the raw strings.
  return a.compareTo(b);
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// ASCII-lowercases [c]; non-ASCII code units compare by code point.
int _fold(int c) => (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c;

int _skipZeros(String s, int i) {
  var k = i;
  while (k + 1 < s.length &&
      s.codeUnitAt(k) == 0x30 &&
      _isDigit(s.codeUnitAt(k + 1))) {
    k++;
  }
  // A run that is all zeros keeps its last zero as the value digit.
  return k;
}

int _endOfDigits(String s, int i) {
  var k = i;
  while (k < s.length && _isDigit(s.codeUnitAt(k))) {
    k++;
  }
  return k;
}
