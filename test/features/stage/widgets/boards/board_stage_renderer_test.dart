// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/features/stage/widgets/boards/board_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';

void main() {
  group('boardPalette', () {
    test('exposes the stylized palette as a const', () {
      expect(boardPalette.pcb, isA<Color>());
      expect(boardPalette.silkscreen, isA<Color>());
      expect(boardPalette.silkscreenStrong, isA<Color>());
      expect(boardPalette.connector, isA<Color>());
      // The PCB body and the strong silkscreen should be different
      // colors so silkscreen labels are readable against the body.
      expect(boardPalette.pcb, isNot(equals(boardPalette.silkscreenStrong)));
    });
  });

  group('childInputPinName', () {
    test('LED → "in"', () {
      expect(childInputPinName('led'), 'in');
    });

    test('toggle_switch → "in"', () {
      expect(childInputPinName('toggle_switch'), 'in');
    });

    test('seven_segment → "value"', () {
      expect(childInputPinName('seven_segment'), 'value');
    });

    test('level_bar → "value"', () {
      expect(childInputPinName('level_bar'), 'value');
    });

    test('bus_readout → "value"', () {
      expect(childInputPinName('bus_readout'), 'value');
    });

    test('state_indicator → "value"', () {
      expect(childInputPinName('state_indicator'), 'value');
    });

    test('signal_graph → "value"', () {
      expect(childInputPinName('signal_graph'), 'value');
    });

    test('unknown widget id falls back to "in"', () {
      expect(childInputPinName('unregistered_widget'), 'in');
    });
  });

  group('BoardPalette', () {
    test('exposes Color fields for all palette slots', () {
      const p = BoardPalette(
        pcb: Color(0xFF112233),
        pcbBorder: Color(0xFF223344),
        silkscreen: Color(0xFF334455),
        silkscreenStrong: Color(0xFF445566),
        connector: Color(0xFF556677),
      );
      expect(p.pcb.toARGB32(), 0xFF112233);
      expect(p.pcbBorder.toARGB32(), 0xFF223344);
      expect(p.silkscreen.toARGB32(), 0xFF334455);
      expect(p.silkscreenStrong.toARGB32(), 0xFF445566);
      expect(p.connector.toARGB32(), 0xFF556677);
    });
  });

  group('BoardStageScaffold — multi-pin slots (pinBindings)', () {
    // Captures the StageInstance the registered renderer is invoked
    // with, so tests can assert which signal bindings landed on the
    // child instance.
    final captured = <String, StageInstance>{};

    setUp(captured.clear);

    Widget captureRenderer(BuildContext context, StageInstance instance) {
      captured[instance.widgetId] = instance;
      return const SizedBox.shrink();
    }

    setUpAll(() {
      // Register a generic capture renderer for every fake widget id
      // we use below. The renderer registry is a singleton so we share
      // it across tests in this group; the captured map is cleared in
      // setUp above so each test starts fresh.
      StageWidgetRendererRegistry.instance.register(
        _kMultiPinChild,
        captureRenderer,
      );
      StageWidgetRendererRegistry.instance.register(
        _kSinglePinChild,
        captureRenderer,
      );
    });

    testWidgets(
      'multi-pin slot populates child instance bindings from sibling slots',
      (tester) async {
        const parent = StageInstance(
          id: 'parent',
          widgetId: 'fake_compound',
          signalBindings: {
            // The four sibling chip slots hold the actual bindings:
            'hdmi_data': StageSignalBinding(signalRef: 'top.hdmi.data'),
            'hdmi_pixel_clk': StageSignalBinding(
              signalRef: 'top.hdmi.pixel_clk',
            ),
            'hdmi_hsync': StageSignalBinding(signalRef: 'top.hdmi.hsync'),
            'hdmi_vsync': StageSignalBinding(signalRef: 'top.hdmi.vsync'),
          },
        );

        await _pumpFakeBoard(
          tester,
          parent,
          slots: const [
            // The multi-pin "framebuffer" slot — its name does NOT
            // appear in any pinBindings entry so its own
            // parentInstance.signalBindings['hdmi'] (if any) is
            // intentionally ignored. All bindings are sourced from the
            // sibling slots below.
            StageWidgetSlot(
              name: 'hdmi',
              childWidgetId: _kMultiPinChild,
              x: 0.05,
              y: 0.05,
              width: 0.4,
              height: 0.4,
              pinBindings: {
                'data': 'hdmi_data',
                'pixelClk': 'hdmi_pixel_clk',
                'hSync': 'hdmi_hsync',
                'vSync': 'hdmi_vsync',
              },
            ),
            // Sibling chip slots — their childWidgetId here is the
            // single-pin capture renderer. In real Pro boards these
            // would be LedStageWidget chips.
            StageWidgetSlot(
              name: 'hdmi_data',
              childWidgetId: _kSinglePinChild,
              x: 0.5,
              y: 0.05,
              width: 0.1,
              height: 0.1,
            ),
            StageWidgetSlot(
              name: 'hdmi_pixel_clk',
              childWidgetId: _kSinglePinChild,
              x: 0.5,
              y: 0.2,
              width: 0.1,
              height: 0.1,
            ),
            StageWidgetSlot(
              name: 'hdmi_hsync',
              childWidgetId: _kSinglePinChild,
              x: 0.5,
              y: 0.35,
              width: 0.1,
              height: 0.1,
            ),
            StageWidgetSlot(
              name: 'hdmi_vsync',
              childWidgetId: _kSinglePinChild,
              x: 0.5,
              y: 0.5,
              width: 0.1,
              height: 0.1,
            ),
          ],
        );

        // The multi-pin child instance should carry all four bindings,
        // each routed to its declared pin name on the child widget.
        final mp = captured[_kMultiPinChild];
        expect(mp, isNotNull, reason: 'multi-pin renderer was invoked');
        expect(mp!.signalBindings['data']?.signalRef, 'top.hdmi.data');
        expect(
          mp.signalBindings['pixelClk']?.signalRef,
          'top.hdmi.pixel_clk',
        );
        expect(mp.signalBindings['hSync']?.signalRef, 'top.hdmi.hsync');
        expect(mp.signalBindings['vSync']?.signalRef, 'top.hdmi.vsync');
        // Confirm the child is NOT receiving the parent's own slot-name
        // binding — multi-pin slots ignore the slot's `name` entry.
        expect(mp.signalBindings.containsKey('in'), isFalse);
        expect(mp.signalBindings.containsKey('value'), isFalse);
      },
    );

    testWidgets(
      'unbound sibling slot omits its pin from the child binding map',
      (tester) async {
        // Only `hdmi_data` is bound; `hdmi_pixel_clk` is intentionally
        // missing so we can verify it does not show up in the child's
        // bindings (rather than appearing as an empty StageSignalBinding).
        const parent = StageInstance(
          id: 'parent',
          widgetId: 'fake_compound',
          signalBindings: {
            'hdmi_data': StageSignalBinding(signalRef: 'top.hdmi.data'),
          },
        );

        await _pumpFakeBoard(
          tester,
          parent,
          slots: const [
            StageWidgetSlot(
              name: 'hdmi',
              childWidgetId: _kMultiPinChild,
              x: 0.05,
              y: 0.05,
              width: 0.4,
              height: 0.4,
              pinBindings: {
                'data': 'hdmi_data',
                'pixelClk': 'hdmi_pixel_clk',
              },
            ),
            StageWidgetSlot(
              name: 'hdmi_data',
              childWidgetId: _kSinglePinChild,
              x: 0.5,
              y: 0.05,
              width: 0.1,
              height: 0.1,
            ),
            StageWidgetSlot(
              name: 'hdmi_pixel_clk',
              childWidgetId: _kSinglePinChild,
              x: 0.5,
              y: 0.2,
              width: 0.1,
              height: 0.1,
            ),
          ],
        );

        final mp = captured[_kMultiPinChild]!;
        expect(mp.signalBindings['data']?.signalRef, 'top.hdmi.data');
        expect(mp.signalBindings.containsKey('pixelClk'), isFalse);
      },
    );

    testWidgets(
      'single-pin slot still maps slot.name binding to childInputPinName',
      (tester) async {
        const parent = StageInstance(
          id: 'parent',
          widgetId: 'fake_compound',
          signalBindings: {
            'led0': StageSignalBinding(signalRef: 'top.led0'),
          },
        );

        await _pumpFakeBoard(
          tester,
          parent,
          slots: const [
            StageWidgetSlot(
              name: 'led0',
              childWidgetId: 'led',
              x: 0,
              y: 0,
              width: 0.1,
              height: 0.1,
            ),
          ],
        );

        // We don't have a renderer for 'led' registered above, so
        // nothing is captured. This test asserts no exception is
        // thrown for the standard single-pin path with the new
        // _BoardSlot.slot field plumbing.
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Slot label legibility', () {
    // The renderer's `_BoardSlotLabel` shrinks to its abbreviated form
    // (`LED[0]` → `0`, `SW[15]` → `15`, `BTN[U]` → `U`, ...) when the
    // full label would render below ~9 dp tall. At the default test
    // surface the full label is comfortably readable so existing
    // boards' tests still see `LED[0]` etc; tiny slots embedded in
    // small board widgets get the abbreviation automatically.
    //
    // Indirect verification: `_BoardSlotLabel` is private, so we
    // render a minimal `_FakeCompound` and probe the visible text.

    testWidgets(
      'standard 100×60 slot in a 400×300 board renders the full label',
      (tester) async {
        const parent = StageInstance(
          id: 'parent',
          widgetId: 'fake_compound',
        );
        await _pumpFakeBoard(
          tester,
          parent,
          slots: const [
            StageWidgetSlot(
              name: 'led0',
              childWidgetId: 'led',
              x: 0.1,
              y: 0.1,
              // 0.25 × 400 = 100 dp wide, 0.20 × 300 = 60 dp tall →
              // 1/4 label-row gives 15 dp tall, plenty for 'LED[0]'
              // to render above the 9 dp legibility floor.
              width: 0.25,
              height: 0.20,
              label: 'LED[0]',
            ),
          ],
        );
        expect(find.text('LED[0]'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tiny 30×30 slot (small board widget / nested compound) drops to '
      'the abbreviated label',
      (tester) async {
        const parent = StageInstance(
          id: 'parent',
          widgetId: 'fake_compound',
        );
        await _pumpFakeBoard(
          tester,
          parent,
          slots: const [
            StageWidgetSlot(
              name: 'led0',
              childWidgetId: 'led',
              x: 0.1,
              y: 0.1,
              // 0.05 × 400 = 20 dp wide, 0.07 × 300 = 21 dp tall.
              // The label row clamps to 14 dp (its minimum), and a
              // 6-character full label squeezed into 20 dp wide
              // renders at ~7 dp — below the 9 dp legibility floor,
              // so the renderer falls back to the abbreviation.
              width: 0.05,
              height: 0.07,
              label: 'LED[0]',
            ),
          ],
        );
        // Abbreviated form is visible — no full-string label.
        expect(find.text('LED[0]'), findsNothing);
        expect(find.text('0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('abbreviates SW[15] to 15 at tiny slot sizes', (tester) async {
      const parent = StageInstance(
        id: 'parent',
        widgetId: 'fake_compound',
      );
      await _pumpFakeBoard(
        tester,
        parent,
        slots: const [
          StageWidgetSlot(
            name: 'sw15',
            childWidgetId: 'toggle_switch',
            x: 0.1,
            y: 0.1,
            // 0.05 × 400 = 20 dp wide, 0.07 × 300 = 21 dp tall →
            // forces the label below the legibility floor regardless
            // of the exact threshold tuning.
            width: 0.05,
            height: 0.07,
            label: 'SW[15]',
          ),
        ],
      );
      expect(find.text('SW[15]'), findsNothing);
      expect(find.text('15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('abbreviates BTN[U] to U at tiny slot sizes', (tester) async {
      const parent = StageInstance(
        id: 'parent',
        widgetId: 'fake_compound',
      );
      await _pumpFakeBoard(
        tester,
        parent,
        slots: const [
          StageWidgetSlot(
            name: 'btnU',
            childWidgetId: 'led',
            x: 0.1,
            y: 0.1,
            // 0.05 × 400 = 20 dp wide, 0.07 × 300 = 21 dp tall →
            // forces the label below the legibility floor regardless
            // of the exact threshold tuning.
            width: 0.05,
            height: 0.07,
            label: 'BTN[U]',
          ),
        ],
      );
      expect(find.text('BTN[U]'), findsNothing);
      expect(find.text('U'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'abbreviates trailing-digit labels (HEX0 → 0) at tiny slot sizes',
      (tester) async {
        const parent = StageInstance(
          id: 'parent',
          widgetId: 'fake_compound',
        );
        await _pumpFakeBoard(
          tester,
          parent,
          slots: const [
            StageWidgetSlot(
              name: 'hex0',
              childWidgetId: 'seven_segment',
              x: 0.1,
              y: 0.1,
              // Same tiny-slot dimensions as the LED/SW/BTN cases:
              // 0.05 × 400 = 20 dp wide, 0.07 × 300 = 21 dp tall.
              width: 0.05,
              height: 0.07,
              label: 'HEX0',
            ),
          ],
        );
        expect(find.text('HEX0'), findsNothing);
        expect(find.text('0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'descriptive peripheral labels stay full when no abbreviation '
      'pattern matches (HDMI OUT)',
      (tester) async {
        const parent = StageInstance(
          id: 'parent',
          widgetId: 'fake_compound',
        );
        await _pumpFakeBoard(
          tester,
          parent,
          slots: const [
            StageWidgetSlot(
              name: 'hdmi_out',
              childWidgetId: 'led',
              x: 0.1,
              y: 0.1,
              width: 0.20,
              height: 0.15,
              label: 'HDMI OUT',
            ),
          ],
        );
        expect(find.text('HDMI OUT'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

const String _kMultiPinChild = '_test_multi_pin_child';
const String _kSinglePinChild = '_test_single_pin_child';

class _FakeCompound extends CompoundStageWidget {
  const _FakeCompound({required this.fakeSlots});
  final List<StageWidgetSlot> fakeSlots;

  @override
  String get id => 'fake_compound';

  @override
  String get displayName => 'Fake Compound';

  @override
  String get description => 'test fixture';

  @override
  StageWidgetCategory get category => StageWidgetCategory.board;

  @override
  List<StageWidgetSlot> get slots => fakeSlots;

  @override
  List<SignalBinding> get requiredSignals => const [];

  @override
  List<SignalBinding> get optionalSignals => [
    for (final s in fakeSlots) SignalBinding(name: s.name, description: s.name),
  ];
}

Future<void> _pumpFakeBoard(
  WidgetTester tester,
  StageInstance instance, {
  required List<StageWidgetSlot> slots,
  Size size = const Size(400, 300),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: BoardStageScaffold(
            instance: instance,
            compound: _FakeCompound(fakeSlots: slots),
            backdropBuilder: (_) => const SizedBox.shrink(),
            boardName: 'Fake',
            trademarkDisclaimer: 'fake — not a real board',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
