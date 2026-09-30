// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_visible_markers_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

CocotbLogEntry _e(int line, int? ticks) => CocotbLogEntry(
  severity: CocotbLogSeverity.info,
  loggerName: 'cocotb.test',
  message: 'm$line',
  lineNumber: line,
  simTimeTicks: ticks,
);

CocotbLogFile _file(List<CocotbLogEntry> entries) => CocotbLogFile(
  filePath: '/tmp/run.log',
  entries: List.unmodifiable(entries),
  testNames: const [],
  severityCounts: const {},
  testResults: const {},
);

ProviderContainer _container({
  required CocotbLogFile? file,
  required (int, int) range,
}) {
  final container = ProviderContainer(
    overrides: [
      visibleTimeRangeProvider.overrideWith((ref) => range),
      cocotbLogProvider.overrideWith(_FixedLog.new),
    ],
  );
  if (file != null) {
    container.read(cocotbLogProvider.notifier).state = file;
  }
  addTearDown(container.dispose);
  return container;
}

class _FixedLog extends CocotbLog {
  @override
  CocotbLogFile? build() => null;
}

void main() {
  group('cocotbVisibleMarkers', () {
    test('returns empty list when no log loaded', () {
      final container = _container(file: null, range: (0, 1000));
      expect(container.read(cocotbVisibleMarkersProvider), isEmpty);
    });

    test('returns empty list when range is degenerate', () {
      final container = _container(
        file: _file([_e(1, 100)]),
        range: (500, 500),
      );
      expect(container.read(cocotbVisibleMarkersProvider), isEmpty);
    });

    test('includes entries within the visible range', () {
      final container = _container(
        file: _file([
          _e(1, 50),
          _e(2, 150),
          _e(3, 250),
          _e(4, 1500),
        ]),
        range: (100, 1000),
      );
      final visible = container.read(cocotbVisibleMarkersProvider);
      expect(visible.map((e) => e.lineNumber), [2, 3]);
    });

    test('excludes entries with null timestamps', () {
      final container = _container(
        file: _file([
          _e(1, 100),
          _e(2, null),
          _e(3, 200),
        ]),
        range: (0, 1000),
      );
      final visible = container.read(cocotbVisibleMarkersProvider);
      expect(visible.map((e) => e.lineNumber), [1, 3]);
    });

    test('inclusive bounds — start and end times match', () {
      final container = _container(
        file: _file([
          _e(1, 100),
          _e(2, 200),
        ]),
        range: (100, 200),
      );
      final visible = container.read(cocotbVisibleMarkersProvider);
      expect(visible, hasLength(2));
    });
  });
}
