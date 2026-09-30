// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/diagnostics/providers/dev_tools_provider.dart';
import 'package:wavecrux/features/diagnostics/widgets/parser_benchmark_runner.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSignalFilter extends Fake implements SignalFilter {}

/// Fake notifier with no source loaded (file path = null).
class _NoFileSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      const AsyncData<WaveformDataSource?>(null);

  @override
  String? get currentFilePath => null;

  @override
  Duration? get lastParseTime => null;
}

/// Fake notifier with a file "loaded" (non-null source, non-null path).
class _LoadedSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() {
    final src = _MockSource();
    when(() => src.findVariables(any())).thenReturn([]);
    when(() => src.rootScopes).thenReturn([]);
    when(() => src.startTime).thenReturn(0);
    when(() => src.endTime).thenReturn(1000);
    when(() => src.timescale).thenReturn(null);
    when(() => src.date).thenReturn(null);
    when(() => src.version).thenReturn(null);
    return AsyncData<WaveformDataSource?>(src);
  }

  @override
  String? get currentFilePath => 'test/fixtures/vcd/scalar_basics.vcd';

  @override
  Duration? get lastParseTime => const Duration(milliseconds: 42);
}

/// Fake notifier that pre-populates a [BenchmarkResult] so the results table
/// renders without requiring the test to actually run the (FFI-backed)
/// benchmark.
class _PrePopulatedDevToolsNotifier extends DevToolsNotifier {
  _PrePopulatedDevToolsNotifier(this._initial);
  final DevToolsState _initial;

  @override
  DevToolsState build() => _initial;
}

Widget _wrap(
  Widget child, {
  bool fileLoaded = false,
  DevToolsState devToolsState = const DevToolsState(),
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      waveformSourceProvider.overrideWith(
        fileLoaded ? _LoadedSourceNotifier.new : _NoFileSourceNotifier.new,
      ),
      devToolsProvider.overrideWith(
        () => _PrePopulatedDevToolsNotifier(devToolsState),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      // The runner is designed to be hosted inside a scrollable container
      // (Tab Diagnostics drawer); wrap with SingleChildScrollView so the
      // standalone test surface can render the runner's full intrinsic
      // height without RenderFlex overflow.
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSignalFilter());
  });

  // ── Locale sweep ────────────────────────────────────────────────────────────

  group('ParserBenchmarkRunner — locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(const ParserBenchmarkRunner(), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Static structure ────────────────────────────────────────────────────────

  group('ParserBenchmarkRunner — structure', () {
    testWidgets('renders the Run Benchmark button', (tester) async {
      await tester.pumpWidget(_wrap(const ParserBenchmarkRunner()));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows empty placeholder when no benchmark has been run', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ParserBenchmarkRunner()));
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.diagnosticsBenchmarkEmpty), findsOneWidget);
    });
  });

  // ── Button enablement ────────────────────────────────────────────────────────

  group('ParserBenchmarkRunner — Run button', () {
    testWidgets('disabled when no file is loaded', (tester) async {
      await tester.pumpWidget(_wrap(const ParserBenchmarkRunner()));
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('enabled when a file is loaded', (tester) async {
      await tester.pumpWidget(
        _wrap(const ParserBenchmarkRunner(), fileLoaded: true),
      );
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });
  });

  // ── Result rendering ────────────────────────────────────────────────────────

  group('ParserBenchmarkRunner — results display', () {
    testWidgets('renders the results table when benchmark has completed', (
      tester,
    ) async {
      const result = BenchmarkResult(
        fileSizeBytes: 1024 * 1024,
        signalCount: 1234,
        parseMs: 50,
      );
      await tester.pumpWidget(
        _wrap(
          const ParserBenchmarkRunner(),
          fileLoaded: true,
          devToolsState: const DevToolsState(benchmarkResult: result),
        ),
      );
      // Signal count appears verbatim in the results table.
      expect(find.text('1234'), findsOneWidget);
      // Parse time appears as '50 ms'.
      expect(find.text('50 ms'), findsOneWidget);
    });

    testWidgets('renders the error card when benchmark has failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ParserBenchmarkRunner(),
          fileLoaded: true,
          devToolsState: const DevToolsState(benchmarkError: 'kaboom'),
        ),
      );
      expect(find.text('kaboom'), findsOneWidget);
    });
  });
}
