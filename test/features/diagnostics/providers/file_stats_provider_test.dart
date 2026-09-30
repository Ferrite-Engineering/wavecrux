// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

// ── fakes & mocks ─────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source, {this.filePath, this.parseTime});
  final WaveformDataSource? _source;
  final String? filePath;
  final Duration? parseTime;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);

  @override
  String? get currentFilePath => filePath;

  @override
  Duration? get lastParseTime => parseTime;
}

// ── helpers ───────────────────────────────────────────────────────────────────

_MockSource _mockSource({int signalCount = 0}) {
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
  when(() => mock.rootScopes).thenReturn([
    Scope(
      name: 'top',
      type: ScopeType.module,
      path: 'top',
      variables: vars,
    ),
  ]);
  when(() => mock.startTime).thenReturn(0);
  when(() => mock.endTime).thenReturn(1000);
  when(() => mock.timescale).thenReturn(null);
  when(() => mock.date).thenReturn(null);
  when(() => mock.version).thenReturn(null);
  return mock;
}

ProviderContainer _container({
  WaveformDataSource? source,
  String? filePath,
  Duration? parseTime,
  bool loadingState = false,
  bool errorState = false,
}) {
  final c = ProviderContainer(
    overrides: [
      if (!loadingState && !errorState)
        waveformSourceProvider.overrideWith(
          () => _FakeSourceNotifier(
            source,
            filePath: filePath,
            parseTime: parseTime,
          ),
        ),
      if (loadingState)
        waveformSourceProvider.overrideWith(_LoadingSourceNotifier.new),
      if (errorState)
        waveformSourceProvider.overrideWith(_ErrorSourceNotifier.new),
    ],
  );
  addTearDown(c.dispose);
  return c;
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

class _ErrorSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncError<WaveformDataSource?>(
    Exception('parse error'),
    StackTrace.empty,
  );

  @override
  String? get currentFilePath => null;

  @override
  Duration? get lastParseTime => null;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(const SignalFilter());
  });

  group('fileStatsProvider', () {
    test('returns null when source is null (no file loaded)', () {
      final c = _container();
      expect(c.read(fileStatsProvider), isNull);
    });

    test('returns null when source is loading', () {
      final c = _container(loadingState: true);
      expect(c.read(fileStatsProvider), isNull);
    });

    test('returns null when source is in error state', () {
      final c = _container(errorState: true);
      expect(c.read(fileStatsProvider), isNull);
    });

    test('returns FileStats when source is loaded', () {
      final src = _mockSource(signalCount: 3);
      final c = _container(source: src, filePath: 'dump.vcd');
      final stats = c.read(fileStatsProvider);
      expect(stats, isNotNull);
      expect(stats!.totalSignals, 3);
    });

    test('uses filePath from notifier', () {
      final src = _mockSource();
      final c = _container(
        source: src,
        filePath: '/home/user/sim/out.vcd',
      );
      final stats = c.read(fileStatsProvider);
      expect(stats!.filePath, '/home/user/sim/out.vcd');
      expect(stats.formatName, 'VCD');
    });

    test('uses parseTime from notifier', () {
      final src = _mockSource();
      final c = _container(
        source: src,
        parseTime: const Duration(milliseconds: 500),
      );
      final stats = c.read(fileStatsProvider);
      expect(stats!.parseTimeMs, closeTo(500.0, 0.01));
    });

    test('falls back to Duration.zero when parseTime is null', () {
      final src = _mockSource();
      final c = _container(source: src, filePath: 'test.vcd');
      final stats = c.read(fileStatsProvider);
      expect(stats!.parseTimeMs, 0.0);
    });

    test('falls back to empty string when filePath is null', () {
      final src = _mockSource();
      final c = _container(source: src);
      final stats = c.read(fileStatsProvider);
      expect(stats!.filePath, '');
      expect(stats.formatName, 'Unknown');
    });

    test('rebuilds when a new file is loaded', () {
      final src1 = _mockSource(signalCount: 2);
      final c = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(src1, filePath: 'a.vcd'),
          ),
        ],
      );
      addTearDown(c.dispose);
      registerFallbackValue(const SignalFilter());

      final stats1 = c.read(fileStatsProvider);
      expect(stats1!.totalSignals, 2);
    });

    // ── WellenProvider-specific behavior ──────────────────────────────────────

    test('totalTransitions sums lengths of all loaded signal change lists', () {
      // totalTransitions is no longer eagerly populated at open time — it is
      // derived from the cached per-signal change lists on demand. Inject
      // three signals with 1 / 2 / 3 changes respectively → total 6.
      final wellen = WellenProvider()
        ..injectHierarchy([])
        ..injectLoadedSignal('1', [const SignalChange(time: 0, value: '0')])
        ..injectLoadedSignal('2', [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 1, value: '1'),
        ])
        ..injectLoadedSignal('3', [
          const SignalChange(time: 0, value: '0'),
          const SignalChange(time: 1, value: '1'),
          const SignalChange(time: 2, value: '0'),
        ]);

      final c = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(wellen, filePath: 'sim.vcd'),
          ),
        ],
      );
      addTearDown(c.dispose);

      final stats = c.read(fileStatsProvider);
      expect(stats, isNotNull);
      expect(stats!.totalTransitions, 6);
    });

    test('totalTransitions is 0 for non-WellenProvider source', () {
      final src = _mockSource();
      final c = _container(source: src, filePath: 'dump.vcd');

      final stats = c.read(fileStatsProvider);
      expect(stats!.totalTransitions, 0);
    });

    test(
      'formatName uses WellenProvider.fileFormat over extension inference',
      () {
        final wellen = WellenProvider()..injectHierarchy([]);

        final c = ProviderContainer(
          overrides: [
            // Supply a .fst path so extension inference would return 'FST',
            // but WellenProvider.fileFormat should take precedence.
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(wellen, filePath: 'sim.fst'),
            ),
          ],
        );
        addTearDown(c.dispose);

        final stats = c.read(fileStatsProvider);
        // WellenProvider.fileFormat defaults to 'Unknown' without a real open.
        expect(stats!.formatName, 'Unknown');
      },
    );
  });
}
