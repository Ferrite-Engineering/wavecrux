// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

// ── fakes & mocks ─────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);

  @override
  String? get currentFilePath => null;

  @override
  Duration? get lastParseTime => null;
}

class _LoadingSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      const AsyncLoading<WaveformDataSource?>();

  @override
  String? get currentFilePath => null;

  @override
  Duration? get lastParseTime => null;
}

// ── helpers ───────────────────────────────────────────────────────────────────

_MockSource _mockSource({
  int signalCount = 0,
  Set<String> loadedRefs = const {},
}) {
  final mock = _MockSource();
  final vars = List.generate(
    signalCount,
    (i) => Variable(
      name: 'sig_$i',
      signalRef: 'sig_$i',
      varType: VarType.wire,
      direction: VarDirection.unknown,
      scopePath: 'top',
      bitWidth: 1,
    ),
  );
  when(() => mock.findVariables(any())).thenReturn(vars);
  for (final v in vars) {
    when(
      () => mock.isSignalLoaded(v.signalRef),
    ).thenReturn(loadedRefs.contains(v.signalRef));
  }
  return mock;
}

/// Creates a container and pre-warms the provider so [build()] is called and
/// [Future.microtask(_update)] is scheduled before returning.
///
/// Tests that need the async update to complete should then
/// `await Future<void>.delayed(Duration.zero)` before reading state.
ProviderContainer _container({
  WaveformDataSource? source,
  bool loadingState = false,
}) {
  final c = ProviderContainer(
    overrides: [
      if (!loadingState)
        waveformSourceProvider.overrideWith(
          () => _FakeSourceNotifier(source),
        ),
      if (loadingState)
        waveformSourceProvider.overrideWith(
          _LoadingSourceNotifier.new,
        ),
    ],
  );
  addTearDown(c.dispose);
  // Trigger build() immediately so the first microtask update is scheduled.
  c.listen<MemoryStats?>(memoryStatsProvider, (_, _) {});
  return c;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(const SignalFilter());
  });

  group('MemoryStatsNotifier — initial state', () {
    test('returns null synchronously before first async update', () {
      final c = _container();
      expect(c.read(memoryStatsProvider), isNull);
    });

    test('returns null when source is loading', () {
      final c = _container(loadingState: true);
      expect(c.read(memoryStatsProvider), isNull);
    });
  });

  group('MemoryStatsNotifier — after async update', () {
    test('populates MemoryStats when source is loaded', () async {
      final src = _mockSource(signalCount: 5);
      final c = _container(source: src);
      // Pump to let Future.microtask(_update) complete.
      await Future<void>.delayed(Duration.zero);

      final stats = c.read(memoryStatsProvider);
      expect(stats, isNotNull);
      expect(stats!.totalSignalCount, 5);
      expect(stats.loadedSignalCount, 0);
    });

    test('state is null when source is null after update', () async {
      final c = _container();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(memoryStatsProvider), isNull);
    });

    test('loadedSignalCount reflects isSignalLoaded results', () async {
      final src = _mockSource(
        signalCount: 4,
        loadedRefs: {'sig_0', 'sig_2'},
      );
      final c = _container(source: src);
      await Future<void>.delayed(Duration.zero);

      final stats = c.read(memoryStatsProvider);
      expect(stats!.loadedSignalCount, 2);
      expect(stats.totalSignalCount, 4);
    });

    test('wellenEstimateBytes is 0 for non-WellenProvider source', () async {
      final c = _container(source: _mockSource(signalCount: 2));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(memoryStatsProvider)!.wellenEstimateBytes, 0);
    });

    test('dartProcessRssBytes is non-negative', () async {
      final c = _container(source: _mockSource(signalCount: 1));
      await Future<void>.delayed(Duration.zero);
      expect(
        c.read(memoryStatsProvider)!.dartProcessRssBytes,
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('MemoryStatsNotifier — disposal', () {
    test('provider disposes cleanly without error', () async {
      final c = _container(source: _mockSource(signalCount: 2));
      await Future<void>.delayed(Duration.zero);
      expect(c.dispose, returnsNormally);
    });
  });
}
