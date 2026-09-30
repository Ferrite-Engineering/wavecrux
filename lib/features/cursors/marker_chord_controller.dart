// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// The two marker chords advertised in the command palette
/// (`Set Marker (M + a–z)` and `Jump to Marker (⇧M + a–z)`).
enum MarkerChordMode {
  /// Drop a named marker (a–z) at the primary cursor.
  set,

  /// Move the primary cursor to a named marker (a–z).
  jump,
}

/// The result of completing a marker chord: which [mode] was armed and the
/// single lowercase letter (`a`–`z`) the user pressed to finish it.
@immutable
class MarkerChordCompletion {
  const MarkerChordCompletion(this.mode, this.letter);

  final MarkerChordMode mode;

  /// A single lowercase letter `a`–`z`.
  final String letter;

  @override
  bool operator ==(Object other) =>
      other is MarkerChordCompletion &&
      other.mode == mode &&
      other.letter == letter;

  @override
  int get hashCode => Object.hash(mode, letter);

  @override
  String toString() => 'MarkerChordCompletion($mode, $letter)';
}

/// State machine for the two-key marker chords.
///
/// The waveform viewer arms a chord ([arm]) when the user presses `M`
/// (set) or `⇧M` (jump), then feeds the next key into [handleKey]. A letter
/// `a`–`z` completes the chord and returns a [MarkerChordCompletion]; any
/// other key cancels it. The chord can also be [cancel]led explicitly (e.g.
/// on a timeout or when focus leaves the viewer).
///
/// Kept free of widget/provider dependencies so the full arm → complete /
/// arm → cancel behaviour is unit-testable without pumping the viewer.
class MarkerChordController extends ChangeNotifier {
  MarkerChordMode? _pending;

  /// The currently-armed chord mode, or null when no chord is pending.
  MarkerChordMode? get pending => _pending;

  /// Whether a chord is waiting for its completing `a`–`z` keystroke.
  bool get isArmed => _pending != null;

  /// Arms [mode], replacing any previously-armed chord.
  void arm(MarkerChordMode mode) {
    if (_pending == mode) return;
    _pending = mode;
    notifyListeners();
  }

  /// Cancels the armed chord, if any. No-op when nothing is armed.
  void cancel() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }

  /// Feeds [key] into an armed chord.
  ///
  /// Callers must check [isArmed] first: a key fed while armed always consumes
  /// the chord, either completing it (letter `a`–`z`, returns the
  /// [MarkerChordCompletion]) or cancelling it (any other key, returns null).
  /// Returns null immediately when nothing is armed.
  MarkerChordCompletion? handleKey(LogicalKeyboardKey key) {
    final mode = _pending;
    if (mode == null) return null;
    _pending = null;
    notifyListeners();
    final letter = letterFor(key);
    return letter == null ? null : MarkerChordCompletion(mode, letter);
  }

  /// Maps a [LogicalKeyboardKey] to its lowercase letter `a`–`z`, or null when
  /// the key is not a letter (digits, modifiers, function keys, etc.).
  static String? letterFor(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.length != 1) return null;
    final lower = label.toLowerCase();
    final code = lower.codeUnitAt(0);
    return (code >= 0x61 && code <= 0x7a) ? lower : null;
  }
}
