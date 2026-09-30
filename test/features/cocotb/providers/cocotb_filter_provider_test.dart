// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_filter_state.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';

ProviderContainer _makeContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('CocotbFilter', () {
    test('builds with empty default state', () {
      final container = _makeContainer();
      expect(
        container.read(cocotbFilterProvider),
        const CocotbFilterState(),
      );
    });

    test('setTestName updates only that field', () {
      final container = _makeContainer();
      container.read(cocotbFilterProvider.notifier).setTestName('test_basic');
      expect(
        container.read(cocotbFilterProvider).testNameFilter,
        'test_basic',
      );
      expect(
        container.read(cocotbFilterProvider).severityFilter,
        isEmpty,
      );
    });

    test('setTestName(null) clears testName', () {
      final container = _makeContainer();
      final notifier = container.read(cocotbFilterProvider.notifier)
        ..setTestName('test_x');
      expect(container.read(cocotbFilterProvider).testNameFilter, 'test_x');
      notifier.setTestName(null);
      expect(container.read(cocotbFilterProvider).testNameFilter, isNull);
    });

    test('toggleSeverity adds and removes severities', () {
      final container = _makeContainer();
      final notifier = container.read(cocotbFilterProvider.notifier)
        ..toggleSeverity(CocotbLogSeverity.info);
      expect(
        container.read(cocotbFilterProvider).severityFilter,
        {CocotbLogSeverity.info},
      );
      notifier.toggleSeverity(CocotbLogSeverity.error);
      expect(
        container.read(cocotbFilterProvider).severityFilter,
        {CocotbLogSeverity.info, CocotbLogSeverity.error},
      );
      // Toggling an existing severity removes it.
      notifier.toggleSeverity(CocotbLogSeverity.info);
      expect(
        container.read(cocotbFilterProvider).severityFilter,
        {CocotbLogSeverity.error},
      );
    });

    test('setKeyword updates keyword field', () {
      final container = _makeContainer();
      container.read(cocotbFilterProvider.notifier).setKeyword('reset');
      expect(
        container.read(cocotbFilterProvider).keywordFilter,
        'reset',
      );
    });

    test('clearAll resets every field', () {
      final container = _makeContainer();
      container.read(cocotbFilterProvider.notifier)
        ..setTestName('test_x')
        ..toggleSeverity(CocotbLogSeverity.info)
        ..setKeyword('reset')
        ..clearAll();
      expect(
        container.read(cocotbFilterProvider),
        const CocotbFilterState(),
      );
    });
  });
}
