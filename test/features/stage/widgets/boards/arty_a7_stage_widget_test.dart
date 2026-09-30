// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/widgets/boards/arty_a7_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '_board_test_helpers.dart';

void main() {
  group('ArtyA7StageWidget definition', () {
    const board = ArtyA7StageWidget();

    test('metadata fields', () {
      expect(board.id, 'artyA7');
      expect(board.displayName, 'Digilent Arty A7');
      expect(board.category, StageWidgetCategory.board);
      expect(board.isCompound, isTrue);
    });

    test('exposes 16 slots: 4 plain LEDs + 4 RGB LED positions + '
        '4 switches + 4 buttons (Pmods are visual-only)', () {
      expect(board.slots, hasLength(4 + 4 + 4 + 4));
    });

    test('plain LED slots are named led0..led3', () {
      final names = board.slots
          .where(
            (s) =>
                s.childWidgetId == LedStageWidget.widgetId &&
                s.name.startsWith('led'),
          )
          .map((s) => s.name)
          .toSet();
      expect(names, containsAll(['led0', 'led1', 'led2', 'led3']));
    });

    test('RGB LED positions are named led4..led7 with "(RGB)" labels '
        'and rendered as plain LEDs in Open Core', () {
      final rgbSlots = board.slots
          .where(
            (s) =>
                s.childWidgetId == LedStageWidget.widgetId &&
                s.name.startsWith('led') &&
                ArtyA7StageWidget.isRgbLedSlotName(s.name),
          )
          .toList();
      expect(rgbSlots, hasLength(ArtyA7StageWidget.rgbLedCount));
      for (var i = 0; i < ArtyA7StageWidget.rgbLedCount; i++) {
        final n = ArtyA7StageWidget.plainLedCount + i;
        final slot = rgbSlots.firstWhere((s) => s.name == 'led$n');
        expect(slot.label, 'LED[$n] (RGB)');
      }
    });

    test('switch slots are named sw0..sw3 with SW[i] labels', () {
      final switches = board.slots
          .where((s) => s.childWidgetId == ToggleSwitchStageWidget.widgetId)
          .toList();
      expect(switches, hasLength(ArtyA7StageWidget.switchCount));
      for (var i = 0; i < ArtyA7StageWidget.switchCount; i++) {
        final slot = switches.firstWhere((s) => s.name == 'sw$i');
        expect(slot.label, 'SW[$i]');
      }
    });

    test('button slots are named btn0..btn3 with BTN[i] labels', () {
      final btns = board.slots
          .where(
            (s) =>
                s.childWidgetId == LedStageWidget.widgetId &&
                s.name.startsWith('btn'),
          )
          .toList();
      expect(btns, hasLength(ArtyA7StageWidget.buttonCount));
      for (var i = 0; i < ArtyA7StageWidget.buttonCount; i++) {
        final slot = btns.firstWhere((s) => s.name == 'btn$i');
        expect(slot.label, 'BTN[$i]');
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

    test('default optionalSignals exposes every slot as a binding', () {
      final names = board.optionalSignals.map((b) => b.name).toSet();
      final slotNames = board.slots.map((s) => s.name).toSet();
      expect(names, equals(slotNames));
    });

    test('RGB LED bindings carry the Pro-upgrade hint sentinel; non-RGB '
        'bindings carry the slot label', () {
      for (final binding in board.optionalSignals) {
        if (ArtyA7StageWidget.isRgbLedSlotName(binding.name)) {
          expect(
            binding.description,
            '__rgb_pro_upgrade_hint__',
            reason:
                'led4..led7 should carry the sentinel for the '
                'bindings pane to resolve to the localized hint',
          );
        } else {
          expect(binding.description, isNot('__rgb_pro_upgrade_hint__'));
        }
      }
    });

    test('LED / switch / button bindings carry bitWidth: 1', () {
      for (final binding in board.optionalSignals) {
        if (binding.name.startsWith('led') ||
            binding.name.startsWith('sw') ||
            binding.name.startsWith('btn')) {
          expect(binding.bitWidth, 1);
        }
      }
    });

    test('Pmod names list matches the real board (JA, JB, JC, JD)', () {
      expect(ArtyA7StageWidget.pmodNames, ['JA', 'JB', 'JC', 'JD']);
    });

    test('isRgbLedSlotName classifies RGB vs plain correctly', () {
      expect(ArtyA7StageWidget.isRgbLedSlotName('led0'), isFalse);
      expect(ArtyA7StageWidget.isRgbLedSlotName('led3'), isFalse);
      expect(ArtyA7StageWidget.isRgbLedSlotName('led4'), isTrue);
      expect(ArtyA7StageWidget.isRgbLedSlotName('led7'), isTrue);
      expect(ArtyA7StageWidget.isRgbLedSlotName('led8'), isFalse);
      expect(ArtyA7StageWidget.isRgbLedSlotName('btn0'), isFalse);
      expect(ArtyA7StageWidget.isRgbLedSlotName('sw0'), isFalse);
    });
  });

  group('resolveBindingDescription', () {
    testWidgets('replaces the sentinel with the localized hint', (
      tester,
    ) async {
      late L10N l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10N.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        resolveBindingDescription(
          '__rgb_pro_upgrade_hint__',
          l10n,
          isMobileHost: false,
        ),
        l10n.stageRgbLedProUpgradeHint,
      );
    });

    testWidgets('uses the neutral note on mobile hosts', (tester) async {
      // The desktop wording ("Open Core renders one channel only. Upgrade to
      // Pro…") describes a shipped feature as partial and carries an external
      // purchase call-to-action — App Store Review Guidelines 2.2 and 3.1.1
      // respectively. On iOS/Android the same behavior is stated plainly.
      late L10N l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10N.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final resolved = resolveBindingDescription(
        '__rgb_pro_upgrade_hint__',
        l10n,
        isMobileHost: true,
      );
      expect(resolved, l10n.stageRgbLedChannelNote);
      expect(resolved, isNot(contains('Pro')));
    });

    testWidgets('passes other strings through unchanged', (tester) async {
      late L10N l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10N.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolveBindingDescription('LED[0]', l10n), 'LED[0]');
      expect(resolveBindingDescription('', l10n), '');
    });
  });

  group('ArtyA7StageRenderer', () {
    setUp(useBuiltinStageWidgets);
    tearDown(clearStageRegistries);

    StageInstance instance({
      Map<String, StageSignalBinding> bindings = const {},
    }) => StageInstance(
      id: 'arty',
      widgetId: ArtyA7StageWidget.widgetId,
      signalBindings: bindings,
    );

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          wrapBoardWidget(
            ArtyA7StageRenderer(instance: instance()),
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
        wrapBoardWidget(ArtyA7StageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('LED[0]'), findsOneWidget);
      expect(find.text('LED[3]'), findsOneWidget);
      expect(find.text('LED[4] (RGB)'), findsOneWidget);
      expect(find.text('LED[7] (RGB)'), findsOneWidget);
      expect(find.text('SW[0]'), findsOneWidget);
      expect(find.text('BTN[0]'), findsOneWidget);
    });

    testWidgets('bound LED signal propagates "1" to the LED renderer', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapBoardWidget(
          ArtyA7StageRenderer(
            instance: instance(
              bindings: const {
                'led0': StageSignalBinding(signalRef: 'top.heartbeat'),
              },
            ),
          ),
          snapshots: {
            'top.heartbeat': const StageSignalSnapshot.value(
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
        wrapBoardWidget(ArtyA7StageRenderer(instance: instance())),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(
          'Arty A7 is a trademark of Digilent, Inc. This widget is not '
          'affiliated with or endorsed by Digilent or AMD.',
        ),
        findsOneWidget,
      );
    });
  });
}
