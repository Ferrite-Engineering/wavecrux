// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/boards/basys3_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/seven_segment_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';

import '_board_test_helpers.dart';

void main() {
  group('Basys3StageWidget definition', () {
    const board = Basys3StageWidget();

    test('metadata fields', () {
      expect(board.id, 'basys3');
      expect(board.displayName, 'Digilent Basys 3');
      expect(board.category, StageWidgetCategory.board);
      expect(board.isCompound, isTrue);
    });

    test('exposes 41 slots: 16 LEDs + 16 switches + 5 buttons + 4 digits', () {
      expect(board.slots, hasLength(16 + 16 + 5 + 4));
    });

    test(
      'LED slots are named led0..led15 with LED[i] labels and 1-bit hint',
      () {
        final leds = board.slots
            .where(
              (s) =>
                  s.childWidgetId == LedStageWidget.widgetId &&
                  s.name.startsWith('led'),
            )
            .toList();
        expect(leds, hasLength(Basys3StageWidget.ledCount));
        for (var i = 0; i < Basys3StageWidget.ledCount; i++) {
          final slot = leds.firstWhere((s) => s.name == 'led$i');
          expect(slot.label, 'LED[$i]');
        }
      },
    );

    test('switch slots are named sw0..sw15 with SW[i] labels', () {
      final switches = board.slots
          .where((s) => s.childWidgetId == ToggleSwitchStageWidget.widgetId)
          .toList();
      expect(switches, hasLength(Basys3StageWidget.switchCount));
      for (var i = 0; i < Basys3StageWidget.switchCount; i++) {
        final slot = switches.firstWhere((s) => s.name == 'sw$i');
        expect(slot.label, 'SW[$i]');
      }
    });

    test('push buttons match Basys 3 vendor names (btnC/U/L/R/D)', () {
      final buttonSlots = board.slots
          .where(
            (s) =>
                Basys3StageWidget.buttonNames.contains(s.name) &&
                s.childWidgetId == LedStageWidget.widgetId,
          )
          .toList();
      expect(buttonSlots, hasLength(5));
      final names = buttonSlots.map((s) => s.name).toSet();
      expect(names, {'btnC', 'btnU', 'btnL', 'btnR', 'btnD'});
    });

    test('seven-segment digits named digit0..digit3 with AN[i] labels', () {
      final segs = board.slots
          .where((s) => s.childWidgetId == SevenSegmentStageWidget.widgetId)
          .toList();
      expect(segs, hasLength(Basys3StageWidget.digitCount));
      for (var i = 0; i < Basys3StageWidget.digitCount; i++) {
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
      for (var i = 0; i < Basys3StageWidget.ledCount; i++) {
        final led = board.slots.firstWhere((s) => s.name == 'led$i');
        final sw = board.slots.firstWhere((s) => s.name == 'sw$i');
        // LED center column should sit within the switch column range.
        final ledCenter = led.x + led.width / 2;
        final swCenter = sw.x + sw.width / 2;
        expect((ledCenter - swCenter).abs(), lessThan(0.01));
      }
    });

    test('SW[0] is rightmost on the board (vendor convention)', () {
      final sw0 = board.slots.firstWhere((s) => s.name == 'sw0');
      final sw15 = board.slots.firstWhere((s) => s.name == 'sw15');
      expect(sw0.x, greaterThan(sw15.x));
    });

    test('default optionalSignals exposes every slot as a binding', () {
      final names = board.optionalSignals.map((b) => b.name).toSet();
      final slotNames = board.slots.map((s) => s.name).toSet();
      expect(names, equals(slotNames));
    });

    test('LED / switch bindings carry bitWidth: 1', () {
      for (final binding in board.optionalSignals) {
        if (binding.name.startsWith('led') ||
            binding.name.startsWith('sw') ||
            Basys3StageWidget.buttonNames.contains(binding.name)) {
          expect(binding.bitWidth, 1);
        }
      }
    });

    test('Pmod names list matches the real board (JA, JB, JC, JXADC)', () {
      // Visual-only — no signal bindings. The Pmod constants are
      // shared across boards so the backdrop painters can paint a
      // consistent connector strip.
      expect(Basys3StageWidget.pmodNames, ['JA', 'JB', 'JC', 'JXADC']);
    });
  });

  group('Basys3StageRenderer', () {
    setUp(useBuiltinStageWidgets);
    tearDown(clearStageRegistries);

    StageInstance instance({
      Map<String, StageSignalBinding> bindings = const {},
    }) => StageInstance(
      id: 'b3',
      widgetId: Basys3StageWidget.widgetId,
      signalBindings: bindings,
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapBoardWidget(
            Basys3StageRenderer(instance: instance()),
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
        wrapBoardWidget(Basys3StageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 16 LED labels + 16 SW labels + 5 button labels + 4 AN labels.
      expect(find.text('LED[0]'), findsOneWidget);
      expect(find.text('LED[15]'), findsOneWidget);
      expect(find.text('SW[0]'), findsOneWidget);
      expect(find.text('SW[15]'), findsOneWidget);
      expect(find.text('btnC'), findsOneWidget);
      expect(find.text('AN[0]'), findsOneWidget);
    });

    testWidgets('dropping a signal on a seven-segment slot does not crash '
        '(regression: requiredSignals empty for seven-segment)', (
      tester,
    ) async {
      // The seven-segment widget exposes its `value` pin via
      // `optionalSignals` and leaves `requiredSignals` empty. Before
      // the fix, the per-slot drop handler called `firstWhere(...,
      // orElse: () => requiredSignals.first)` and crashed with
      // "Bad state: No element" on the .first call. This test
      // simulates a drag-and-drop on `digit0` to lock the regression.
      await tester.pumpWidget(
        wrapBoardWidget(
          Column(
            children: [
              const Draggable<String>(
                data: 'top.seg',
                feedback: SizedBox.shrink(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Text('SEG'),
                ),
              ),
              SizedBox(
                width: 800,
                height: 360,
                child: Basys3StageRenderer(instance: instance()),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final source = tester.getCenter(find.text('SEG'));
      final target = tester.getCenter(find.text('AN[0]'));
      // Use a slow drag so the gesture goes through the long-press
      // recognizer the same way a real signal-tree drag would.
      final gesture = await tester.startGesture(source);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('bound LED signal propagates "1" to the LED renderer', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapBoardWidget(
          Basys3StageRenderer(
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
      // The LED renderer prints the bit value as text content; '1' should
      // appear at least once now.
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('has a low-chrome trademark info-icon and no theme toggle '
        '(realistic-PCB toggle removed in v0.12.6)', (tester) async {
      await tester.pumpWidget(
        wrapBoardWidget(Basys3StageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      // The old realistic-theme toggle is gone.
      expect(
        find.byTooltip('Switch to realistic board representation'),
        findsNothing,
      );
      // The new persistent info-icon exposes the trademark
      // disclaimer via tooltip — message present even though the
      // tooltip overlay isn't rendered until tap/hover.
      expect(
        find.byTooltip(
          'Basys 3 is a trademark of Digilent, Inc. This widget is not '
          'affiliated with or endorsed by Digilent or AMD.',
        ),
        findsOneWidget,
      );
    });
  });
}
