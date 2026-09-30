// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/fsm_transition.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/signal_query/fsm_layout_service.dart';

// ── Fake notifier ────────────────────────────────────────────────────────────

class _FakeFsmNotifier extends FsmNotifier {
  _FakeFsmNotifier(this._initial);
  final FsmViewState _initial;

  @override
  FsmViewState build() => _initial;

  @override
  Future<void> analyzeSignal(String signalRef) async {}

  @override
  void clearFsm() {
    state = const FsmViewState();
  }

  @override
  bool jumpToFirstOccurrence(String stateId) => true;

  @override
  Future<void> refresh() async {}
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _range = TimeRange(start: 0, end: 100);

FsmModel _makeModel() => const FsmModel(
  signalRef: 'ref',
  signalPath: 'top.cpu.state',
  timeRange: _range,
  states: [
    FsmState(id: '0', label: 'IDLE', entryCount: 2, firstEntryTime: 0),
    FsmState(id: '1', label: 'RUN', entryCount: 3, firstEntryTime: 10),
    FsmState(id: '2', label: 'DONE', entryCount: 1, firstEntryTime: 50),
  ],
  transitions: [
    FsmTransition(fromId: '0', toId: '1', count: 2, times: [10, 30]),
    FsmTransition(fromId: '1', toId: '0', count: 1, times: [20]),
    FsmTransition(fromId: '1', toId: '2', count: 1, times: [50]),
  ],
  totalTransitionCount: 4,
);

FsmViewState _activeState() {
  final m = _makeModel();
  final l = const FsmLayoutService().compute(m);
  return FsmViewState(signalRef: 'ref', model: m, layout: l);
}

Widget _wrap(FsmViewState state, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: [
        fsmProvider.overrideWith(() => _FakeFsmNotifier(state)),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: FsmPanel()),
      ),
    );

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('FsmPanel — locale sweep', () {
    testWidgets('idle state renders without exception (en)', (tester) async {
      await tester.pumpWidget(_wrap(const FsmViewState()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('idle state renders without exception (zh_CN)', (tester) async {
      await tester.pumpWidget(
        _wrap(const FsmViewState(), locale: const Locale('zh', 'CN')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('idle state renders without exception (ja)', (tester) async {
      await tester.pumpWidget(
        _wrap(const FsmViewState(), locale: const Locale('ja')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('idle state renders without exception (ko)', (tester) async {
      await tester.pumpWidget(
        _wrap(const FsmViewState(), locale: const Locale('ko')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('active state renders without exception (en)', (tester) async {
      await tester.pumpWidget(_wrap(_activeState()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('active state renders without exception (zh_CN)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_activeState(), locale: const Locale('zh', 'CN')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('active state renders without exception (ja)', (tester) async {
      await tester.pumpWidget(
        _wrap(_activeState(), locale: const Locale('ja')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('active state renders without exception (ko)', (tester) async {
      await tester.pumpWidget(
        _wrap(_activeState(), locale: const Locale('ko')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('FsmPanel — empty state', () {
    testWidgets('shows the empty-state hint when no FSM is active', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const FsmViewState()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Visualize as FSM'), findsOneWidget);
    });

    testWidgets('shows the error message when state has an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const FsmViewState(error: 'Something went wrong')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong'), findsOneWidget);
    });
  });

  group('FsmPanel — active state', () {
    testWidgets('shows the signal path in the header', (tester) async {
      await tester.pumpWidget(_wrap(_activeState()));
      await tester.pumpAndSettle();
      expect(find.textContaining('top.cpu.state'), findsOneWidget);
    });

    testWidgets('header shows state and transition counts', (tester) async {
      await tester.pumpWidget(_wrap(_activeState()));
      await tester.pumpAndSettle();
      // 3 states · 4 transitions
      expect(find.textContaining('3'), findsWidgets);
      expect(find.textContaining('4'), findsWidgets);
    });

    testWidgets('Close button clears the FSM state', (tester) async {
      await tester.pumpWidget(_wrap(_activeState()));
      await tester.pumpAndSettle();
      // The TextButton with the close label (l10n.fsmPanelClose).
      final closeButton = find.widgetWithText(TextButton, 'Close');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();
      // After clearing, the empty-state hint reappears.
      expect(find.textContaining('Visualize as FSM'), findsOneWidget);
    });

    testWidgets('renders a CustomPaint for the diagram', (tester) async {
      await tester.pumpWidget(_wrap(_activeState()));
      await tester.pumpAndSettle();
      // The bubble diagram is drawn via CustomPaint.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders an InteractiveViewer for pan/zoom', (tester) async {
      await tester.pumpWidget(_wrap(_activeState()));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });

  group('FsmPanel — single-state edge case', () {
    testWidgets('renders with one state only', (tester) async {
      const m = FsmModel(
        signalRef: 'r',
        signalPath: 'top.const',
        timeRange: _range,
        states: [
          FsmState(id: '0', label: 'IDLE', entryCount: 1, firstEntryTime: 0),
        ],
        transitions: [],
        totalTransitionCount: 0,
      );
      final layout = const FsmLayoutService().compute(m);
      await tester.pumpWidget(
        _wrap(FsmViewState(signalRef: 'r', model: m, layout: layout)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
