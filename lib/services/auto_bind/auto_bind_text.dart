// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Text-distance helpers shared by both
/// [DecoderAutoBindService] and [BoardAutoBindService].
///
/// Pure Dart, no Flutter or Riverpod dependencies.
class AutoBindText {
  const AutoBindText._();

  /// Computes the Levenshtein edit distance between [a] and [b].
  ///
  /// Used by the fuzzy-match tier of every auto-bind algorithm: a name
  /// is considered a candidate when its distance to the target is at
  /// most 2 (single character insert / delete / substitute / transpose).
  ///
  /// O(|a| × |b|) time, O(|b|) space — small enough that running it
  /// against every signal in a typical waveform is essentially free.
  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    var prev = List<int>.generate(n + 1, (i) => i);
    var curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        var min = del < ins ? del : ins;
        if (sub < min) min = sub;
        curr[j] = min;
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }
}
