// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

const _sampleLog =
    '   100.00ns INFO     cocotb.test_basic                  '
    'Applied reset\n'
    '   200.00ns ERROR    cocotb.test_basic                  Bad value\n';

ProviderContainer _makeContainer({Timescale? timescale}) {
  final container = ProviderContainer(
    overrides: [
      currentTimescaleProvider.overrideWith((ref) => timescale),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('CocotbLog', () {
    test('initial state is null', () {
      final container = _makeContainer();
      expect(container.read(cocotbLogProvider), isNull);
    });

    test('loadFromFile parses and stores the log', () async {
      final container = _makeContainer(
        timescale: const Timescale(
          factor: 1,
          unit: TimescaleUnit.nanoSeconds,
        ),
      );
      final notifier = container.read(cocotbLogProvider.notifier)
        ..reader = (_) async => _sampleLog;
      await notifier.loadFromFile('/tmp/run.log');
      final loaded = container.read(cocotbLogProvider);
      expect(loaded, isNotNull);
      expect(loaded!.entries, hasLength(2));
      expect(loaded.entries[0].severity, CocotbLogSeverity.info);
      expect(loaded.entries[1].severity, CocotbLogSeverity.error);
      expect(loaded.filePath, '/tmp/run.log');
    });

    test('loadFromFile honours the active timescale', () async {
      // 1 ps timescale → 100 ns = 100_000 ticks.
      final container = _makeContainer(
        timescale: const Timescale(
          factor: 1,
          unit: TimescaleUnit.picoSeconds,
        ),
      );
      final notifier = container.read(cocotbLogProvider.notifier)
        ..reader = (_) async => _sampleLog;
      await notifier.loadFromFile('/tmp/run.log');
      final loaded = container.read(cocotbLogProvider)!;
      expect(loaded.entries[0].simTimeTicks, 100000);
      expect(loaded.entries[1].simTimeTicks, 200000);
    });

    test('clear returns to null', () async {
      final container = _makeContainer();
      final notifier = container.read(cocotbLogProvider.notifier)
        ..reader = (_) async => _sampleLog;
      await notifier.loadFromFile('/tmp/run.log');
      expect(container.read(cocotbLogProvider), isNotNull);
      notifier.clear();
      expect(container.read(cocotbLogProvider), isNull);
    });

    test('reader exception propagates to caller', () async {
      final container = _makeContainer();
      final notifier = container.read(cocotbLogProvider.notifier)
        ..reader = (_) async => throw Exception('disk error');
      await expectLater(
        notifier.loadFromFile('/tmp/missing.log'),
        throwsA(isA<Exception>()),
      );
      expect(container.read(cocotbLogProvider), isNull);
    });
  });
}
