// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/boards/nexys_a7_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/seven_segment_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';

import '_board_test_helpers.dart';

void main() {
  group('NexysA7StageWidget definition', () {
    const board = NexysA7StageWidget();

    test('metadata fields', () {
      expect(board.id, 'nexysA7');
      expect(board.displayName, 'Digilent Nexys A7');
      expect(board.category, StageWidgetCategory.board);
      expect(board.isCompound, isTrue);
    });

    test('exposes 45 slots: 16 LEDs + 16 switches + 5 buttons + 8 digits', () {
      expect(board.slots, hasLength(16 + 16 + 5 + 8));
    });

    test('LED slots are named led0..led15 with LED[i] labels', () {
      final leds = board.slots
          .where(
            (s) =>
                s.childWidgetId == LedStageWidget.widgetId &&
                s.name.startsWith('led'),
          )
          .toList();
      expect(leds, hasLength(NexysA7StageWidget.ledCount));
      for (var i = 0; i < NexysA7StageWidget.ledCount; i++) {
        final slot = leds.firstWhere((s) => s.name == 'led$i');
        expect(slot.label, 'LED[$i]');
      }
    });

    test('switch slots are named sw0..sw15 with SW[i] labels', () {
      final switches = board.slots
          .where((s) => s.childWidgetId == ToggleSwitchStageWidget.widgetId)
          .toList();
      expect(switches, hasLength(NexysA7StageWidget.switchCount));
      for (var i = 0; i < NexysA7StageWidget.switchCount; i++) {
        final slot = switches.firstWhere((s) => s.name == 'sw$i');
        expect(slot.label, 'SW[$i]');
      }
    });

    test('push buttons match Nexys A7 vendor names (btnC/U/L/R/D)', () {
      final buttonSlots = board.slots
          .where(
            (s) =>
                NexysA7StageWidget.buttonNames.contains(s.name) &&
                s.childWidgetId == LedStageWidget.widgetId,
          )
          .toList();
      expect(buttonSlots, hasLength(5));
      final names = buttonSlots.map((s) => s.name).toSet();
      expect(names, {'btnC', 'btnU', 'btnL', 'btnR', 'btnD'});
    });

    test('seven-segment digits named digit0..digit7 with AN[i] labels '
        '(8-digit display, double the Basys 3 4-digit display)', () {
      final segs = board.slots
          .where((s) => s.childWidgetId == SevenSegmentStageWidget.widgetId)
          .toList();
      expect(segs, hasLength(NexysA7StageWidget.digitCount));
      expect(NexysA7StageWidget.digitCount, 8);
      for (var i = 0; i < NexysA7StageWidget.digitCount; i++) {
        final slot = segs.firstWhere((s) => s.name == 'digit$i');
        expect(slot.label, 'AN[$i]');
      }
    });

    test('every slot has normalized 0..1 coordinates', () {
      for (final slot in board.slots) {
        expect(slot.x, inInclusiveRange(0.0, 1.0));
        expect(slot.y, inInclusiveRange(0.0, 1.0));
        expect(slot.width, inInclusiveRange(0.0, 1.0));
        expect(slot.height, inInclusiveRange(0.0, 1.0));
        expect(slot.x + slot.width, lessThanOrEqualTo(1.001));
        expect(slot.y + slot.height, lessThanOrEqualTo(1.001));
      }
    });

    test('slot names are unique', () {
      final names = board.slots.map((s) => s.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('LEDs and switches are spatially aligned (same column per index)', () {
      for (var i = 0; i < NexysA7StageWidget.ledCount; i++) {
        final led = board.slots.firstWhere((s) => s.name == 'led$i');
        final sw = board.slots.firstWhere((s) => s.name == 'sw$i');
        final ledCenter = led.x + led.width / 2;
        final swCenter = sw.x + sw.width / 2;
        expect((ledCenter - swCenter).abs(), lessThan(0.01));
      }
    });

    test('SW[0] / LED[0] sit at the right edge (vendor convention)', () {
      final sw0 = board.slots.firstWhere((s) => s.name == 'sw0');
      final sw15 = board.slots.firstWhere((s) => s.name == 'sw15');
      expect(sw0.x, greaterThan(sw15.x));
    });

    test('default optionalSignals exposes every slot as a binding', () {
      final names = board.optionalSignals.map((b) => b.name).toSet();
      final slotNames = board.slots.map((s) => s.name).toSet();
      expect(names, equals(slotNames));
    });

    test('LED / switch / button bindings carry bitWidth: 1', () {
      for (final binding in board.optionalSignals) {
        if (binding.name.startsWith('led') ||
            binding.name.startsWith('sw') ||
            NexysA7StageWidget.buttonNames.contains(binding.name)) {
          expect(binding.bitWidth, 1);
        }
      }
    });

    test('Pmod names list matches the real board (JA, JB, JXADC, JC, JD)', () {
      expect(NexysA7StageWidget.pmodNames, ['JA', 'JB', 'JXADC', 'JC', 'JD']);
    });
  });

  group('NexysA7StageRenderer', () {
    setUp(useBuiltinStageWidgets);
    tearDown(clearStageRegistries);

    StageInstance instance({
      Map<String, StageSignalBinding> bindings = const {},
    }) => StageInstance(
      id: 'nexys',
      widgetId: NexysA7StageWidget.widgetId,
      signalBindings: bindings,
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapBoardWidget(
            NexysA7StageRenderer(instance: instance()),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders with all slots unbound (no exceptions)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapBoardWidget(NexysA7StageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('LED[0]'), findsOneWidget);
      expect(find.text('LED[15]'), findsOneWidget);
      expect(find.text('SW[0]'), findsOneWidget);
      expect(find.text('SW[15]'), findsOneWidget);
      expect(find.text('btnC'), findsOneWidget);
      expect(find.text('AN[0]'), findsOneWidget);
      expect(find.text('AN[7]'), findsOneWidget);
    });

    testWidgets('bound LED signal propagates "1" to the LED renderer', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapBoardWidget(
          NexysA7StageRenderer(
            instance: instance(
              bindings: const {
                'led0': StageSignalBinding(signalRef: 'top.led_active'),
              },
            ),
          ),
          snapshots: {
            'top.led_active': const StageSignalSnapshot.value(
              rawValue: '1',
              bitWidth: 1,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('surfaces the trademark disclaimer via info-icon tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapBoardWidget(NexysA7StageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(
          'Nexys A7 is a trademark of Digilent, Inc. This widget is not '
          'affiliated with or endorsed by Digilent or AMD.',
        ),
        findsOneWidget,
      );
    });
  });
}
