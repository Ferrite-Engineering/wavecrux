// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/boards/de10_lite_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/seven_segment_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';

import '_board_test_helpers.dart';

void main() {
  group('De10LiteStageWidget definition', () {
    const board = De10LiteStageWidget();

    test('metadata fields', () {
      expect(board.id, 'de10_lite');
      expect(board.displayName, 'Terasic DE10-Lite');
      expect(board.category, StageWidgetCategory.board);
      expect(board.isCompound, isTrue);
    });

    test(
      'exposes 28 slots: 10 LEDs + 10 switches + 2 buttons + 6 hex displays',
      () {
        expect(board.slots, hasLength(10 + 10 + 2 + 6));
      },
    );

    test(
      'LED slots use Quartus pin names ledr0..ledr9 with LEDR[i] labels',
      () {
        final leds = board.slots
            .where(
              (s) =>
                  s.childWidgetId == LedStageWidget.widgetId &&
                  s.name.startsWith('ledr'),
            )
            .toList();
        expect(leds, hasLength(De10LiteStageWidget.ledCount));
        for (var i = 0; i < De10LiteStageWidget.ledCount; i++) {
          final slot = leds.firstWhere((s) => s.name == 'ledr$i');
          expect(slot.label, 'LEDR[$i]');
        }
      },
    );

    test('switch slots are sw0..sw9 with SW[i] labels', () {
      final switches = board.slots
          .where((s) => s.childWidgetId == ToggleSwitchStageWidget.widgetId)
          .toList();
      expect(switches, hasLength(De10LiteStageWidget.switchCount));
      for (var i = 0; i < De10LiteStageWidget.switchCount; i++) {
        final slot = switches.firstWhere((s) => s.name == 'sw$i');
        expect(slot.label, 'SW[$i]');
      }
    });

    test('push buttons named key0/key1 with KEY[N] labels', () {
      final btns = board.slots
          .where(
            (s) =>
                De10LiteStageWidget.buttonNames.contains(s.name) &&
                s.childWidgetId == LedStageWidget.widgetId,
          )
          .toList();
      expect(btns, hasLength(2));
      final byName = {for (final s in btns) s.name: s.label};
      expect(byName['key0'], 'KEY[0]');
      expect(byName['key1'], 'KEY[1]');
    });

    test('seven-segment digits named hex0..hex5 with HEX{i} labels', () {
      final hex = board.slots
          .where((s) => s.childWidgetId == SevenSegmentStageWidget.widgetId)
          .toList();
      expect(hex, hasLength(De10LiteStageWidget.hexCount));
      for (var i = 0; i < De10LiteStageWidget.hexCount; i++) {
        final slot = hex.firstWhere((s) => s.name == 'hex$i');
        expect(slot.label, 'HEX$i');
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

    test('SW[0] is rightmost (vendor convention)', () {
      final sw0 = board.slots.firstWhere((s) => s.name == 'sw0');
      final sw9 = board.slots.firstWhere((s) => s.name == 'sw9');
      expect(sw0.x, greaterThan(sw9.x));
    });

    test('HEX5 is leftmost (vendor convention)', () {
      final hex0 = board.slots.firstWhere((s) => s.name == 'hex0');
      final hex5 = board.slots.firstWhere((s) => s.name == 'hex5');
      expect(hex5.x, lessThan(hex0.x));
    });

    test('default optionalSignals exposes every slot as a binding', () {
      final names = board.optionalSignals.map((b) => b.name).toSet();
      final slotNames = board.slots.map((s) => s.name).toSet();
      expect(names, equals(slotNames));
    });
  });

  group('De10LiteStageRenderer', () {
    setUp(useBuiltinStageWidgets);
    tearDown(clearStageRegistries);

    StageInstance instance({
      Map<String, StageSignalBinding> bindings = const {},
    }) => StageInstance(
      id: 'de10',
      widgetId: De10LiteStageWidget.widgetId,
      signalBindings: bindings,
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapBoardWidget(
            De10LiteStageRenderer(instance: instance()),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders with vendor-style slot labels', (tester) async {
      await tester.pumpWidget(
        wrapBoardWidget(De10LiteStageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('LEDR[0]'), findsOneWidget);
      expect(find.text('LEDR[9]'), findsOneWidget);
      expect(find.text('HEX0'), findsOneWidget);
      expect(find.text('HEX5'), findsOneWidget);
      expect(find.text('KEY[0]'), findsOneWidget);
    });

    testWidgets('bound switch signal updates child renderer', (tester) async {
      await tester.pumpWidget(
        wrapBoardWidget(
          De10LiteStageRenderer(
            instance: instance(
              bindings: const {
                'sw0': StageSignalBinding(signalRef: 'top.sw0_signal'),
              },
            ),
          ),
          snapshots: {
            'top.sw0_signal': const StageSignalSnapshot.value(
              rawValue: '1',
              bitWidth: 1,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('has a low-chrome trademark info-icon and no theme toggle '
        '(realistic-PCB toggle removed in v0.12.6)', (tester) async {
      await tester.pumpWidget(
        wrapBoardWidget(De10LiteStageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Switch to realistic board representation'),
        findsNothing,
      );
      expect(
        find.byTooltip(
          'DE10-Lite is a trademark of Terasic Inc. This widget is not '
          'affiliated with or endorsed by Terasic or Intel.',
        ),
        findsOneWidget,
      );
    });
  });
}
