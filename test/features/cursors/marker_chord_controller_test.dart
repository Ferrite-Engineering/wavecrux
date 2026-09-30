// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/cursors/marker_chord_controller.dart';

void main() {
  group('MarkerChordController.letterFor', () {
    test('maps every letter key a–z to its lowercase letter', () {
      const cases = <(LogicalKeyboardKey, String)>[
        (LogicalKeyboardKey.keyA, 'a'),
        (LogicalKeyboardKey.keyC, 'c'),
        (LogicalKeyboardKey.keyM, 'm'),
        (LogicalKeyboardKey.keyZ, 'z'),
      ];
      for (final (key, expected) in cases) {
        expect(MarkerChordController.letterFor(key), expected);
      }
    });

    test('returns null for digits, modifiers, and function keys', () {
      for (final key in const [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
      ]) {
        expect(
          MarkerChordController.letterFor(key),
          isNull,
          reason: '${key.keyLabel} is not a letter',
        );
      }
    });
  });

  group('MarkerChordController — arm/complete', () {
    test('starts unarmed', () {
      final c = MarkerChordController();
      expect(c.isArmed, isFalse);
      expect(c.pending, isNull);
    });

    test('arm(set) then a letter completes with that letter', () {
      final c = MarkerChordController()..arm(MarkerChordMode.set);
      expect(c.isArmed, isTrue);
      expect(c.pending, MarkerChordMode.set);

      final completion = c.handleKey(LogicalKeyboardKey.keyC);
      expect(completion, const MarkerChordCompletion(MarkerChordMode.set, 'c'));
      // Completing disarms the chord.
      expect(c.isArmed, isFalse);
    });

    test('arm(jump) then a letter completes in jump mode', () {
      final c = MarkerChordController()..arm(MarkerChordMode.jump);
      final completion = c.handleKey(LogicalKeyboardKey.keyK);
      expect(
        completion,
        const MarkerChordCompletion(MarkerChordMode.jump, 'k'),
      );
      expect(c.isArmed, isFalse);
    });

    test('a non-letter key cancels an armed chord and returns null', () {
      final c = MarkerChordController()..arm(MarkerChordMode.set);
      final completion = c.handleKey(LogicalKeyboardKey.escape);
      expect(completion, isNull);
      expect(c.isArmed, isFalse);
    });

    test('handleKey returns null and stays unarmed when nothing is armed', () {
      final c = MarkerChordController();
      expect(c.handleKey(LogicalKeyboardKey.keyC), isNull);
      expect(c.isArmed, isFalse);
    });

    test('cancel() disarms a pending chord', () {
      final c = MarkerChordController()
        ..arm(MarkerChordMode.set)
        ..cancel();
      expect(c.isArmed, isFalse);
    });
  });

  group('MarkerChordController — notifications', () {
    test('arm, complete, and cancel each notify listeners', () {
      final c = MarkerChordController();
      var notifications = 0;
      c
        ..addListener(() => notifications++)
        ..arm(MarkerChordMode.set) // 1
        ..handleKey(LogicalKeyboardKey.keyC) // 2 (complete)
        ..arm(MarkerChordMode.jump) // 3
        ..cancel(); // 4
      expect(notifications, 4);
    });

    test('re-arming the same mode does not notify', () {
      final c = MarkerChordController()..arm(MarkerChordMode.set);
      var notifications = 0;
      c
        ..addListener(() => notifications++)
        ..arm(MarkerChordMode.set);
      expect(notifications, 0);
    });

    test('cancel with nothing armed does not notify', () {
      final c = MarkerChordController();
      var notifications = 0;
      c
        ..addListener(() => notifications++)
        ..cancel();
      expect(notifications, 0);
    });
  });
}
