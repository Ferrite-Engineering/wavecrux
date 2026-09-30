// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/time_range.dart';

void main() {
  const range = TimeRange(start: 0, end: 100);

  const base = SignalActivity(
    signalPath: 'top.clk',
    transitionCount: 10,
    toggleRate: 0.1,
    isClockCandidate: false,
    timeRange: range,
    dutyCycle: 0.5,
  );

  group('equality', () {
    test('identical instances are equal', () {
      expect(base, equals(base));
    });

    test('equal values produce equal instances', () {
      const other = SignalActivity(
        signalPath: 'top.clk',
        transitionCount: 10,
        toggleRate: 0.1,
        isClockCandidate: false,
        timeRange: range,
        dutyCycle: 0.5,
      );
      expect(base, equals(other));
    });

    test('different signalPath → not equal', () {
      final other = base.copyWith(signalPath: 'top.data');
      expect(base, isNot(equals(other)));
    });

    test('different transitionCount → not equal', () {
      final other = base.copyWith(transitionCount: 5);
      expect(base, isNot(equals(other)));
    });

    test('different toggleRate → not equal', () {
      final other = base.copyWith(toggleRate: 0.2);
      expect(base, isNot(equals(other)));
    });

    test('different isClockCandidate → not equal', () {
      final other = base.copyWith(isClockCandidate: true);
      expect(base, isNot(equals(other)));
    });

    test('different estimatedFrequency → not equal', () {
      final other = base.copyWith(estimatedFrequency: 1e8);
      expect(base, isNot(equals(other)));
    });

    test('different dutyCycle → not equal', () {
      final other = base.copyWith(dutyCycle: 0.3);
      expect(base, isNot(equals(other)));
    });

    test('different timeRange → not equal', () {
      final other = base.copyWith(
        timeRange: const TimeRange(start: 10, end: 200),
      );
      expect(base, isNot(equals(other)));
    });
  });

  group('hashCode', () {
    test('equal instances have equal hashCodes', () {
      const other = SignalActivity(
        signalPath: 'top.clk',
        transitionCount: 10,
        toggleRate: 0.1,
        isClockCandidate: false,
        timeRange: range,
        dutyCycle: 0.5,
      );
      expect(base.hashCode, equals(other.hashCode));
    });
  });

  group('copyWith', () {
    test('no args returns equivalent instance', () {
      expect(base.copyWith(), equals(base));
    });

    test('updates signalPath', () {
      final result = base.copyWith(signalPath: 'top.data');
      expect(result.signalPath, 'top.data');
      expect(result.transitionCount, base.transitionCount);
    });

    test('updates transitionCount', () {
      expect(base.copyWith(transitionCount: 20).transitionCount, 20);
    });

    test('updates toggleRate', () {
      expect(base.copyWith(toggleRate: 0.5).toggleRate, 0.5);
    });

    test('updates isClockCandidate', () {
      expect(base.copyWith(isClockCandidate: true).isClockCandidate, isTrue);
    });

    test('updates timeRange', () {
      const newRange = TimeRange(start: 50, end: 150);
      expect(base.copyWith(timeRange: newRange).timeRange, newRange);
    });

    test('sets estimatedFrequency to value', () {
      final result = base.copyWith(estimatedFrequency: 1e8);
      expect(result.estimatedFrequency, 1e8);
    });

    test('clears estimatedFrequency to null', () {
      final withFreq = base.copyWith(estimatedFrequency: 1e8);
      final cleared = withFreq.copyWith(estimatedFrequency: null);
      expect(cleared.estimatedFrequency, isNull);
    });

    test('sets dutyCycle to value', () {
      expect(base.copyWith(dutyCycle: 0.7).dutyCycle, 0.7);
    });

    test('clears dutyCycle to null', () {
      final cleared = base.copyWith(dutyCycle: null);
      expect(cleared.dutyCycle, isNull);
    });

    test('omitting nullable field preserves existing value', () {
      final withFreq = base.copyWith(estimatedFrequency: 1e9);
      expect(withFreq.copyWith(signalPath: 'x').estimatedFrequency, 1e9);
    });
  });

  group('toString', () {
    test('contains key fields', () {
      final s = base.toString();
      expect(s, contains('top.clk'));
      expect(s, contains('10'));
      expect(s, contains('false'));
    });
  });

  group('null nullable fields', () {
    test('estimatedFrequency and dutyCycle can be null', () {
      const a = SignalActivity(
        signalPath: 'x',
        transitionCount: 0,
        toggleRate: 0,
        isClockCandidate: false,
        timeRange: range,
      );
      expect(a.estimatedFrequency, isNull);
      expect(a.dutyCycle, isNull);
    });
  });
}
