// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/activity_report.dart';
import 'package:wavecrux/domain/models/signal_activity.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/widgets/activity_heatmap_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── fake notifier ─────────────────────────────────────────────────────────────

class _FakeActivityNotifier extends SwitchingActivityNotifier {
  _FakeActivityNotifier(this._initial);
  final SwitchingActivityState _initial;

  bool clearCalled = false;

  @override
  SwitchingActivityState build() => _initial;

  @override
  Future<void> analyze(
    Map<String, String> signalRefToPath,
    int startTime,
    int endTime,
  ) async {}

  @override
  void clear() {
    clearCalled = true;
    state = const SwitchingActivityState();
  }
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
  transitionCount: 4,
  toggleRate: 0.004,
  isClockCandidate: false,
  timeRange: TimeRange(start: 0, end: 1000),
);

ActivityReport _makeReport() => const ActivityReport(
  signals: [_clkActivity, _dataActivity],
  timeRange: TimeRange(start: 0, end: 1000),
  totalTransitions: 204,
  topSwitchers: [_clkActivity, _dataActivity],
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
    home: const Scaffold(body: ActivityHeatmapOverlay()),
  ),
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── locale sweep ─────────────────────────────────────────────────────────────

  group('ActivityHeatmapOverlay — locale sweep', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders without exception — $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(const SwitchingActivityState(), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── inactive state ────────────────────────────────────────────────────────────

  group('ActivityHeatmapOverlay — inactive (no analysis)', () {
    testWidgets('no heat banner shown when isActive is false', (tester) async {
      await tester.pumpWidget(_wrap(const SwitchingActivityState()));
      await tester.pumpAndSettle();

      // Banner has a bolt icon; should not be present when inactive.
      expect(find.byIcon(Icons.bolt), findsNothing);
    });

    testWidgets('renders signal tree panel directly when inactive', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SwitchingActivityState()));
      await tester.pumpAndSettle();

      // SignalTreePanel renders its title "Signal Tree" when no file is loaded.
      expect(find.text('Signal Tree'), findsOneWidget);
    });
  });

  // ── active state ──────────────────────────────────────────────────────────────

  group('ActivityHeatmapOverlay — active (analysis present)', () {
    testWidgets('heat banner is shown when isActive is true', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bolt), findsOneWidget);
    });

    testWidgets('banner shows activity panel title', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Switching Activity'), findsOneWidget);
    });

    testWidgets('banner shows close icon button', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('banner gradient contains blue and red', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      // The banner is a Container with a LinearGradient from blue to red.
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasGradient = containers.any((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          final gradient = decoration.gradient;
          if (gradient is LinearGradient && gradient.colors.length >= 2) {
            return gradient.colors.first.b > 0.5 &&
                gradient.colors.last.r > 0.5;
          }
        }
        return false;
      });
      expect(hasGradient, isTrue);
    });

    testWidgets('signal tree panel still renders below banner', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Signal Tree'), findsOneWidget);
    });
  });

  // ── clear interaction ─────────────────────────────────────────────────────────

  group('ActivityHeatmapOverlay — clear interaction', () {
    testWidgets('tapping close button calls clear on notifier', (tester) async {
      late _FakeActivityNotifier fakeNotifier;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            switchingActivityProvider.overrideWith(
              () => fakeNotifier = _FakeActivityNotifier(
                SwitchingActivityState(report: _makeReport()),
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: ActivityHeatmapOverlay()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(fakeNotifier.clearCalled, isTrue);
    });

    testWidgets('banner disappears after clear', (tester) async {
      await tester.pumpWidget(
        _wrap(SwitchingActivityState(report: _makeReport())),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bolt), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // After clear, isActive becomes false — banner gone.
      expect(find.byIcon(Icons.bolt), findsNothing);
    });
  });

  // ── analyzing state ───────────────────────────────────────────────────────────

  group('ActivityHeatmapOverlay — analyzing state', () {
    testWidgets('banner shown when isAnalyzing is true', (tester) async {
      await tester.pumpWidget(
        _wrap(const SwitchingActivityState(isAnalyzing: true)),
      );
      await tester.pump();

      // isActive = true when isAnalyzing, so banner should be visible.
      expect(find.byIcon(Icons.bolt), findsOneWidget);
    });
  });

  // ── heatmap values ─────────────────────────────────────────────────────────────

  group('ActivityHeatmapOverlay — heatmap values in state', () {
    testWidgets('renders without exception with heatmap values set', (
      tester,
    ) async {
      final state = SwitchingActivityState(
        report: _makeReport(),
        heatmapValues: const {
          'top.clk': 1.0,
          'top.data': 0.1,
        },
      );
      await tester.pumpWidget(_wrap(state));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
