// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/activity_report.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/widgets/activity_report_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── fake notifier ─────────────────────────────────────────────────────────────

class _FakeActivityNotifier extends SwitchingActivityNotifier {
  _FakeActivityNotifier(this._initial);
  final SwitchingActivityState _initial;

  @override
  SwitchingActivityState build() => _initial;

  @override
  Future<void> analyze(
    Map<String, String> signalRefToPath,
    int startTime,
    int endTime,
  ) async {}

  @override
  void clear() => state = const SwitchingActivityState();
}

// ── fixtures ──────────────────────────────────────────────────────────────────

const _clkActivity = SignalActivity(
  signalPath: 'top.clk',
  transitionCount: 200,
  toggleRate: 0.2,
  isClockCandidate: true,
  estimatedFrequency: 100000000,
  dutyCycle: 0.5,
  timeRange: TimeRange(start: 0, end: 1000),
);

const _dataActivity = SignalActivity(
  signalPath: 'top.data',
  transitionCount: 10,
  toggleRate: 0.01,
  isClockCandidate: false,
  timeRange: TimeRange(start: 0, end: 1000),
);

ActivityReport _makeReport([
  List<SignalActivity> signals = const [_clkActivity, _dataActivity],
]) => ActivityReport(
  signals: signals,
  timeRange: const TimeRange(start: 0, end: 1000),
  totalTransitions: signals.fold(0, (sum, s) => sum + s.transitionCount),
  topSwitchers: [...signals]
    ..sort((a, b) => b.toggleRate.compareTo(a.toggleRate)),
);

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(
  SwitchingActivityState state, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    switchingActivityProvider.overrideWith(() => _FakeActivityNotifier(state)),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: const Scaffold(body: ActivityReportPanel()),
  ),
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── locale sweep ─────────────────────────────────────────────────────────────

  group('ActivityReportPanel — locale sweep', () {
    testWidgets('renders without exception — en', (tester) async {
      await tester.pumpWidget(_wrap(const SwitchingActivityState()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — zh_CN', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SwitchingActivityState(),
          locale: const Locale('zh', 'CN'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — ja', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SwitchingActivityState(),
          locale: const Locale('ja'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — ko', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SwitchingActivityState(),
          locale: const Locale('ko'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ── empty state ───────────────────────────────────────────────────────────────

  group('ActivityReportPanel — empty state', () {
    testWidgets('shows empty-state text when no report', (tester) async {
      await tester.pumpWidget(_wrap(const SwitchingActivityState()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No analysis', findRichText: true),
        findsOneWidget,
      );
    });
  });

  // ── analyzing state ───────────────────────────────────────────────────────────

  group('ActivityReportPanel — analyzing state', () {
    testWidgets('shows progress indicator while analyzing', (tester) async {
      await tester.pumpWidget(
        _wrap(const SwitchingActivityState(isAnalyzing: true)),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ── report table ─────────────────────────────────────────────────────────────

  group('ActivityReportPanel — report table', () {
    testWidgets('shows panel title in header', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Switching Activity'), findsWidgets);
    });

    testWidgets('shows leaf signal names as rows', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      // Leaf names are displayed; full paths are in tooltips.
      expect(find.text('clk'), findsOneWidget);
      expect(find.text('data'), findsOneWidget);
      expect(find.text('top.clk'), findsNothing);
      expect(find.text('top.data'), findsNothing);
    });

    testWidgets('signal row wraps leaf name in Tooltip with full path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
      final messages = tooltips.map((t) => t.message).toSet();
      expect(messages, contains('top.clk'));
      expect(messages, contains('top.data'));
    });

    testWidgets('shows clock icon for clock candidates', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows column headers', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Signal'), findsOneWidget);
      expect(find.text('Transitions'), findsOneWidget);
      expect(find.text('Toggle Rate'), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Duty Cycle'), findsOneWidget);
    });

    testWidgets('tapping column header changes sort', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      // Tap the Transitions header to sort by it.
      await tester.tap(find.text('Transitions'));
      await tester.pump();

      // Sort arrow should appear (descending first tap).
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('tapping same column header toggles sort direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transitions'));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

      await tester.tap(find.text('Transitions'));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('clear button resets state', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear'));
      await tester.pump();

      // After clear the fake notifier sets state to idle — empty state shown.
      expect(
        find.textContaining('No analysis', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('Export CSV button is present when report loaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Export CSV'), findsOneWidget);
    });
  });

  // ── sorting all columns ───────────────────────────────────────────────────────

  group('ActivityReportPanel — sorting by each column', () {
    testWidgets('sort by signal name column', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Signal'));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('sort by signal name ascending on second tap', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Signal'));
      await tester.pump();
      await tester.tap(find.text('Signal'));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('sort by clock column', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clock'));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('sort by frequency column', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Frequency'));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('sort by duty cycle column', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Duty Cycle'));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('sort by toggle rate column', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      // Toggle Rate is the default sort column; tapping it again flips direction.
      await tester.tap(find.text('Toggle Rate'));
      await tester.pump();

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });
  });

  // ── row value display ─────────────────────────────────────────────────────────

  group('ActivityReportPanel — row value display', () {
    testWidgets('shows em-dash for null frequency and duty cycle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      // _dataActivity has no estimatedFrequency or dutyCycle — both show '—'.
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('shows formatted frequency for clock signal', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      // 100 MHz clock should show MHz-formatted frequency.
      expect(find.text('100.00 MHz'), findsOneWidget);
    });

    testWidgets('shows duty cycle percentage for clock signal', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.text('50.0%'), findsOneWidget);
    });

    testWidgets('shows transition count for each signal', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.text('200'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('shows total transitions in header', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('210 total'), findsOneWidget);
    });
  });

  // ── row tap selection ─────────────────────────────────────────────────────────

  group('ActivityReportPanel — row tap', () {
    testWidgets('tapping a signal row does not throw', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('clk'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  // ── locale sweep with report ──────────────────────────────────────────────────

  group('ActivityReportPanel — locale sweep with report', () {
    testWidgets('renders with active report — no exception', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
