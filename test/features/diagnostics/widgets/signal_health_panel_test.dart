// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';
import 'package:wavecrux/features/diagnostics/providers/signal_integrity_provider.dart';
import 'package:wavecrux/features/diagnostics/widgets/signal_health_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// Fake notifier that starts with a pre-set state.
class _FakeSignalIntegrityNotifier extends SignalIntegrityNotifier {
  _FakeSignalIntegrityNotifier(this._initial);
  final AsyncValue<SignalIntegrityReport?> _initial;

  @override
  AsyncValue<SignalIntegrityReport?> build() => _initial;
}

SignalIntegrityReport _emptyReport() => const SignalIntegrityReport(
  constantSignalPaths: [],
  xzOnlySignalPaths: [],
  glitchSignals: {},
  detectedClocks: [],
  stuckAtResetPaths: [],
  analysisTimeMs: 12.5,
  signalsAnalyzed: 10,
);

SignalIntegrityReport _reportWithIssues() => const SignalIntegrityReport(
  constantSignalPaths: ['top.always_zero', 'top.always_one'],
  xzOnlySignalPaths: ['top.undriven'],
  glitchSignals: {'top.glitchy': 3},
  detectedClocks: [
    ClockInfo(
      signalRef: '!',
      signalPath: 'top.clk',
      periodTicks: 20,
      dutyCyclePercent: 50,
      estimatedFrequency: '50.00 MHz',
    ),
  ],
  stuckAtResetPaths: ['top.rst'],
  analysisTimeMs: 42,
  signalsAnalyzed: 25,
);

Widget _wrap(
  Widget child, {
  AsyncValue<SignalIntegrityReport?> state = const AsyncData(null),
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      signalIntegrityProvider.overrideWith(
        () => _FakeSignalIntegrityNotifier(state),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      // The panel is designed to be hosted inside a scrollable container
      // (Tab Diagnostics drawer); wrap with SingleChildScrollView so the
      // standalone test surface can render the panel's full intrinsic
      // height without RenderFlex overflow.
      home: const Scaffold(
        body: SingleChildScrollView(child: SignalHealthPanel()),
      ),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── locale sweep ─────────────────────────────────────────────────────────────

  group('SignalHealthPanel — locale sweep', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale (empty state)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const SignalHealthPanel(), locale: locale),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('renders without exception in $locale (results state)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const SignalHealthPanel(),
            state: AsyncData(_reportWithIssues()),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── empty (initial) state ────────────────────────────────────────────────────

  group('SignalHealthPanel — empty state', () {
    testWidgets('shows placeholder message', (tester) async {
      await tester.pumpWidget(_wrap(const SignalHealthPanel()));
      await tester.pump();
      expect(
        find.text(
          'Run a signal integrity analysis to check for common simulation issues.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows Run Analysis button', (tester) async {
      await tester.pumpWidget(_wrap(const SignalHealthPanel()));
      await tester.pump();
      expect(find.text('Run Analysis'), findsOneWidget);
    });

    testWidgets('Run Analysis button is disabled when no file is loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SignalHealthPanel()));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });
  });

  // ── loading state ─────────────────────────────────────────────────────────────

  group('SignalHealthPanel — loading state', () {
    testWidgets('shows progress indicator', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: const AsyncLoading<SignalIntegrityReport?>(),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Resolves the expected label through L10N rather than hardcoding it. The
    // literal spelling here ("Analyzing..." with three ASCII periods) drifted
    // out of sync with the ARB ("Analyzing…", one typographic ellipsis) and
    // left this test permanently red — a hardcoded copy of a localized string
    // cannot survive a house-style pass on the ARB.
    testWidgets('shows the in-progress label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: const AsyncLoading<SignalIntegrityReport?>(),
        ),
      );
      await tester.pump();
      final l10n = L10N.of(tester.element(find.byType(SignalHealthPanel)));
      expect(find.text(l10n.diagnosticsHealthRunning), findsOneWidget);
    });
  });

  // ── results state — clean report ──────────────────────────────────────────────

  group('SignalHealthPanel — clean results (no issues)', () {
    testWidgets('shows summary with signal count', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncData(_emptyReport()),
        ),
      );
      await tester.pump();
      expect(find.textContaining('10'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows all five section headings', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncData(_emptyReport()),
        ),
      );
      await tester.pump();
      expect(find.text('Constant Signals'), findsOneWidget);
      expect(find.text('X/Z-Only Signals'), findsOneWidget);
      expect(find.text('Glitch Points'), findsOneWidget);
      expect(find.text('Detected Clocks'), findsOneWidget);
      expect(find.text('Stuck at Reset'), findsOneWidget);
    });

    testWidgets('Run Analysis button is present in results state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncData(_emptyReport()),
        ),
      );
      await tester.pump();
      expect(find.text('Run Analysis'), findsOneWidget);
    });
  });

  // ── results state — report with issues ────────────────────────────────────────

  group('SignalHealthPanel — results with issues', () {
    testWidgets('shows correct badge count for constant signals', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncData(_reportWithIssues()),
        ),
      );
      await tester.pump();
      // 2 constant signals — badge should show "2"
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('expanding Constant Signals shows the signal paths', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncData(_reportWithIssues()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Constant Signals'));
      await tester.pumpAndSettle();

      expect(find.text('top.always_zero'), findsOneWidget);
      expect(find.text('top.always_one'), findsOneWidget);
    });

    testWidgets('expanding Detected Clocks shows frequency and duty cycle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncData(_reportWithIssues()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Detected Clocks'));
      await tester.pumpAndSettle();

      expect(find.textContaining('50.00 MHz'), findsOneWidget);
      expect(find.textContaining('50.0%'), findsOneWidget);
    });

    testWidgets('expanding Glitch Points shows signal path and count', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncData(_reportWithIssues()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Glitch Points'));
      await tester.pumpAndSettle();

      expect(find.text('top.glitchy'), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
    });

    testWidgets('groups with 0 issues show "None found" when expanded', (
      tester,
    ) async {
      // Use a report where everything is zero except one clock.
      const report = SignalIntegrityReport(
        constantSignalPaths: [],
        xzOnlySignalPaths: [],
        glitchSignals: {},
        detectedClocks: [],
        stuckAtResetPaths: [],
        analysisTimeMs: 5,
        signalsAnalyzed: 5,
      );

      await tester.pumpWidget(
        _wrap(const SignalHealthPanel(), state: const AsyncData(report)),
      );
      await tester.pump();

      await tester.tap(find.text('Constant Signals'));
      await tester.pumpAndSettle();

      expect(find.text('None found'), findsOneWidget);
    });
  });

  // ── error state ───────────────────────────────────────────────────────────────

  group('SignalHealthPanel — error state', () {
    testWidgets('shows error message text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalHealthPanel(),
          state: AsyncError<SignalIntegrityReport?>(
            Exception('analysis failed'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('analysis failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
