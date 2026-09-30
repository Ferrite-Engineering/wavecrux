// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/activity_report.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/time_range.dart';

void main() {
  const range = TimeRange(start: 0, end: 100);

  SignalActivity makeActivity(String path, int transitions, double rate) =>
      SignalActivity(
        signalPath: path,
        transitionCount: transitions,
        toggleRate: rate,
        isClockCandidate: false,
        timeRange: range,
      );

  final a1 = makeActivity('top.clk', 10, 0.1);
  final a2 = makeActivity('top.data', 4, 0.04);

  final report = ActivityReport(
    signals: [a1, a2],
    timeRange: range,
    totalTransitions: 14,
    topSwitchers: [a1, a2],
  );

  group('equality', () {
    test('identical instance is equal', () {
      expect(report, equals(report));
    });

    test('equal values produce equal instances', () {
      final other = ActivityReport(
        signals: [a1, a2],
        timeRange: range,
        totalTransitions: 14,
        topSwitchers: [a1, a2],
      );
      expect(report, equals(other));
    });

    test('different signals list → not equal', () {
      final other = ActivityReport(
        signals: [a1],
        timeRange: range,
        totalTransitions: 10,
        topSwitchers: [a1],
      );
      expect(report, isNot(equals(other)));
    });

    test('different timeRange → not equal', () {
      final other = ActivityReport(
        signals: [a1, a2],
        timeRange: const TimeRange(start: 0, end: 200),
        totalTransitions: 14,
        topSwitchers: [a1, a2],
      );
      expect(report, isNot(equals(other)));
    });

    test('different totalTransitions → not equal', () {
      final other = ActivityReport(
        signals: [a1, a2],
        timeRange: range,
        totalTransitions: 99,
        topSwitchers: [a1, a2],
      );
      expect(report, isNot(equals(other)));
    });

    test('different topSwitchers order → not equal', () {
      final other = ActivityReport(
        signals: [a1, a2],
        timeRange: range,
        totalTransitions: 14,
        topSwitchers: [a2, a1],
      );
      expect(report, isNot(equals(other)));
    });
  });

  group('hashCode', () {
    test('equal instances have equal hashCodes', () {
      final other = ActivityReport(
        signals: [a1, a2],
        timeRange: range,
        totalTransitions: 14,
        topSwitchers: [a1, a2],
      );
      expect(report.hashCode, equals(other.hashCode));
    });
  });

  group('empty report', () {
    test('can be constructed with empty lists', () {
      const empty = ActivityReport(
        signals: [],
        timeRange: range,
        totalTransitions: 0,
        topSwitchers: [],
      );
      expect(empty.signals, isEmpty);
      expect(empty.topSwitchers, isEmpty);
      expect(empty.totalTransitions, 0);
    });
  });

  group('toString', () {
    test('contains signal count and range', () {
      final s = report.toString();
      expect(s, contains('2'));
      expect(s, contains('14'));
    });
  });
}
