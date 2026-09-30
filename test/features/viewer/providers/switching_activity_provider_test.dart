// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/activity_report.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';

void main() {
  // ── SwitchingActivityState unit tests ─────────────────────────────────────────

  group('SwitchingActivityState', () {
    test('default state has no report, empty heatmap, not analyzing', () {
      const s = SwitchingActivityState();
      expect(s.report, isNull);
      expect(s.heatmapValues, isEmpty);
      expect(s.isAnalyzing, isFalse);
      expect(s.isActive, isFalse);
    });

    test('isActive when report is non-null', () {
      const s = SwitchingActivityState(
        report: ActivityReport(
          signals: [],
          timeRange: TimeRange(start: 0, end: 100),
          totalTransitions: 0,
          topSwitchers: [],
        ),
      );
      expect(s.isActive, isTrue);
    });

    test('isActive when isAnalyzing is true even with no report', () {
      const s = SwitchingActivityState(isAnalyzing: true);
      expect(s.isActive, isTrue);
    });

    test('copyWith preserves unset fields', () {
      const report = ActivityReport(
        signals: [],
        timeRange: TimeRange(start: 0, end: 100),
        totalTransitions: 0,
        topSwitchers: [],
      );
      const s = SwitchingActivityState(
        report: report,
        heatmapValues: {'top.clk': 1.0},
      );
      final copy = s.copyWith(isAnalyzing: true);
      expect(copy.report, report);
      expect(copy.heatmapValues, const {'top.clk': 1.0});
      expect(copy.isAnalyzing, isTrue);
    });

    test('copyWith clearReport removes report and heatmap', () {
      const report = ActivityReport(
        signals: [],
        timeRange: TimeRange(start: 0, end: 100),
        totalTransitions: 0,
        topSwitchers: [],
      );
      const s = SwitchingActivityState(
        report: report,
        heatmapValues: {'top.clk': 1.0},
      );
      final cleared = s.copyWith(clearReport: true);
      expect(cleared.report, isNull);
      expect(cleared.heatmapValues, isEmpty);
    });

    test('equality holds for same fields', () {
      const a = SwitchingActivityState(isAnalyzing: true);
      const b = SwitchingActivityState(isAnalyzing: true);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when isAnalyzing differs', () {
      const a = SwitchingActivityState(isAnalyzing: true);
      const b = SwitchingActivityState();
      expect(a, isNot(equals(b)));
    });

    test('inequality when heatmapValues differ', () {
      const a = SwitchingActivityState(heatmapValues: {'top.clk': 1.0});
      const b = SwitchingActivityState();
      expect(a, isNot(equals(b)));
    });

    test('toString contains active and analyzing fields', () {
      const s = SwitchingActivityState(isAnalyzing: true);
      expect(s.toString(), contains('analyzing: true'));
      expect(s.toString(), contains('active: true'));
    });
  });

  // ── SwitchingActivityNotifier provider tests ──────────────────────────────────

  group('SwitchingActivityNotifier', () {
    ProviderContainer makeContainer() => ProviderContainer();

    test('initial state is empty/idle', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final state = container.read(switchingActivityProvider);
      expect(state.isActive, isFalse);
      expect(state.report, isNull);
      expect(state.heatmapValues, isEmpty);
      expect(state.isAnalyzing, isFalse);
    });

    test('clear resets state to idle', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(switchingActivityProvider.notifier).clear();
      final state = container.read(switchingActivityProvider);
      expect(state, equals(const SwitchingActivityState()));
    });

    test('analyze with no waveform source is a no-op', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container
          .read(switchingActivityProvider.notifier)
          .analyze({'!': 'top.clk'}, 0, 1000);

      final state = container.read(switchingActivityProvider);
      expect(state.isActive, isFalse);
      expect(state.report, isNull);
    });

    test('analyze with empty map is a no-op', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container
          .read(switchingActivityProvider.notifier)
          .analyze({}, 0, 1000);

      final state = container.read(switchingActivityProvider);
      expect(state.isActive, isFalse);
    });

    test('clear after idle is idempotent', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(switchingActivityProvider.notifier)
        ..clear()
        ..clear();

      expect(
        container.read(switchingActivityProvider),
        const SwitchingActivityState(),
      );
    });

    test('provider is keepAlive — returns same notifier on multiple reads', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final n1 = container.read(switchingActivityProvider.notifier);
      final n2 = container.read(switchingActivityProvider.notifier);
      expect(identical(n1, n2), isTrue);
    });
  });
}
