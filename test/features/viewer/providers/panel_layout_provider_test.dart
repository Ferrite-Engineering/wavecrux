// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';

import '../../../helpers/product_telemetry_config.dart';

void main() {
  group('PanelLayoutState', () {
    test('default values', () {
      const state = PanelLayoutState();
      expect(state.signalTreeVisible, isTrue);
      expect(state.valueColumnVisible, isTrue);
      expect(state.transactionViewVisible, isFalse);
      expect(state.statisticsStripVisible, isFalse);
      expect(state.cocotbLogPanelVisible, isFalse);
    });

    test('copyWith overrides specified fields', () {
      const state = PanelLayoutState();
      final updated = state.copyWith(transactionViewVisible: true);
      expect(updated.signalTreeVisible, isTrue);
      expect(updated.valueColumnVisible, isTrue);
      expect(updated.transactionViewVisible, isTrue);
    });

    test('copyWith preserves unspecified fields', () {
      const original = PanelLayoutState(
        signalTreeVisible: false,
        valueColumnVisible: false,
        transactionViewVisible: true,
      );
      final copy = original.copyWith(signalTreeVisible: true);
      expect(copy.signalTreeVisible, isTrue);
      expect(copy.valueColumnVisible, isFalse);
      expect(copy.transactionViewVisible, isTrue);
    });

    test('equality — identical values are equal', () {
      const a = PanelLayoutState();
      const b = PanelLayoutState();
      expect(a, equals(b));
    });

    test('equality — differing values are not equal', () {
      const a = PanelLayoutState();
      final b = a.copyWith(signalTreeVisible: false);
      expect(a, isNot(equals(b)));
    });

    test('hashCode matches for equal instances', () {
      const a = PanelLayoutState();
      const b = PanelLayoutState();
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('PanelLayoutNotifier', () {
    ProviderContainer makeContainer() =>
        ProviderContainer(overrides: [productTelemetryConfig]);

    test('initial state matches defaults', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(
        container.read(panelLayoutProvider),
        equals(const PanelLayoutState()),
      );
    });

    test('toggleSignalTree flips signalTreeVisible', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(
        container.read(panelLayoutProvider).signalTreeVisible,
        isTrue,
      );
      container.read(panelLayoutProvider.notifier).toggleSignalTree();
      expect(
        container.read(panelLayoutProvider).signalTreeVisible,
        isFalse,
      );
      container.read(panelLayoutProvider.notifier).toggleSignalTree();
      expect(
        container.read(panelLayoutProvider).signalTreeVisible,
        isTrue,
      );
    });

    test('toggleValueColumn flips valueColumnVisible', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier).toggleValueColumn();
      expect(
        container.read(panelLayoutProvider).valueColumnVisible,
        isFalse,
      );
    });

    test('toggleTransactionView flips transactionViewVisible', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier).toggleTransactionView();
      expect(
        container.read(panelLayoutProvider).transactionViewVisible,
        isTrue,
      );
    });

    test('setSignalTreeVisible sets to exact value', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container
          .read(panelLayoutProvider.notifier)
          .setSignalTreeVisible(visible: false);
      expect(
        container.read(panelLayoutProvider).signalTreeVisible,
        isFalse,
      );
      container
          .read(panelLayoutProvider.notifier)
          .setSignalTreeVisible(visible: false);
      expect(
        container.read(panelLayoutProvider).signalTreeVisible,
        isFalse,
      );
    });

    test('setValueColumnVisible sets to exact value', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container
          .read(panelLayoutProvider.notifier)
          .setValueColumnVisible(visible: false);
      expect(
        container.read(panelLayoutProvider).valueColumnVisible,
        isFalse,
      );
    });

    test('setTransactionViewVisible sets to exact value', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container
          .read(panelLayoutProvider.notifier)
          .setTransactionViewVisible(visible: true);
      expect(
        container.read(panelLayoutProvider).transactionViewVisible,
        isTrue,
      );
    });

    test('default rtlSourceVisible is false', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(
        container.read(panelLayoutProvider).rtlSourceVisible,
        isFalse,
      );
    });

    test('toggleRtlSource flips rtlSourceVisible', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier).toggleRtlSource();
      expect(
        container.read(panelLayoutProvider).rtlSourceVisible,
        isTrue,
      );
      container.read(panelLayoutProvider.notifier).toggleRtlSource();
      expect(
        container.read(panelLayoutProvider).rtlSourceVisible,
        isFalse,
      );
    });

    test('setRtlSourceVisible sets to exact value', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container
          .read(panelLayoutProvider.notifier)
          .setRtlSourceVisible(visible: true);
      expect(
        container.read(panelLayoutProvider).rtlSourceVisible,
        isTrue,
      );
      container
          .read(panelLayoutProvider.notifier)
          .setRtlSourceVisible(visible: false);
      expect(
        container.read(panelLayoutProvider).rtlSourceVisible,
        isFalse,
      );
    });

    test('default statisticsStripVisible is false', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(
        container.read(panelLayoutProvider).statisticsStripVisible,
        isFalse,
      );
    });

    test('toggleStatisticsStrip flips statisticsStripVisible', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier).toggleStatisticsStrip();
      expect(
        container.read(panelLayoutProvider).statisticsStripVisible,
        isTrue,
      );
      container.read(panelLayoutProvider.notifier).toggleStatisticsStrip();
      expect(
        container.read(panelLayoutProvider).statisticsStripVisible,
        isFalse,
      );
    });

    test('setStatisticsStripVisible sets to exact value', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container
          .read(panelLayoutProvider.notifier)
          .setStatisticsStripVisible(visible: true);
      expect(
        container.read(panelLayoutProvider).statisticsStripVisible,
        isTrue,
      );
      container
          .read(panelLayoutProvider.notifier)
          .setStatisticsStripVisible(visible: false);
      expect(
        container.read(panelLayoutProvider).statisticsStripVisible,
        isFalse,
      );
    });

    test('default cocotbLogPanelVisible is false', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(
        container.read(panelLayoutProvider).cocotbLogPanelVisible,
        isFalse,
      );
    });

    test('toggleCocotbLogPanel flips cocotbLogPanelVisible', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier).toggleCocotbLogPanel();
      expect(
        container.read(panelLayoutProvider).cocotbLogPanelVisible,
        isTrue,
      );
      container.read(panelLayoutProvider.notifier).toggleCocotbLogPanel();
      expect(
        container.read(panelLayoutProvider).cocotbLogPanelVisible,
        isFalse,
      );
    });

    test('setCocotbLogPanelVisible sets to exact value', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container
          .read(panelLayoutProvider.notifier)
          .setCocotbLogPanelVisible(visible: true);
      expect(
        container.read(panelLayoutProvider).cocotbLogPanelVisible,
        isTrue,
      );
    });

    test('pane sizes default to null', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final state = container.read(panelLayoutProvider);
      expect(state.leftPaneSize, isNull);
      expect(state.rightPaneSize, isNull);
      expect(state.bottomPaneSize, isNull);
    });

    test('setLeftPaneSize / setRightPaneSize / setBottomPaneSize persist '
        'the drag-resize value', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(panelLayoutProvider.notifier)
        ..setLeftPaneSize(320)
        ..setRightPaneSize(180)
        ..setBottomPaneSize(260);
      final state = container.read(panelLayoutProvider);
      expect(state.leftPaneSize, 320);
      expect(state.rightPaneSize, 180);
      expect(state.bottomPaneSize, 260);
    });
  });
}
