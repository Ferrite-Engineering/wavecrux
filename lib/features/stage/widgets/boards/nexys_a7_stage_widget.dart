// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/features/stage/widgets/boards/board_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/seven_segment_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Stage compound widget for the Digilent Nexys A7 (Xilinx/AMD) FPGA
/// development board.
///
/// Step-up from the Basys 3 — same primitive vocabulary (LEDs,
/// switches, buttons, seven-segment) but with **8** seven-segment
/// digits instead of 4 and Pmod connector strips along the top edge.
/// The Pmod headers are drawn as labeled rectangles in the backdrop
/// only — Pmod is a generic mezzanine connector, so users wire
/// individual Pmod pins to standalone primitives in their Stage
/// rather than binding them on the board itself.
///
/// Slot names mirror vendor constraint-file pin names
/// (`led0`–`led15`, `sw0`–`sw15`, `btnC`/`btnU`/`btnL`/`btnR`/`btnD`,
/// `digit0`–`digit7`).
class NexysA7StageWidget extends CompoundStageWidget {
  const NexysA7StageWidget();

  static const String widgetId = 'nexysA7';

  static const int ledCount = 16;
  static const int switchCount = 16;
  static const int digitCount = 8;
  static const List<String> buttonNames = [
    'btnC',
    'btnU',
    'btnL',
    'btnR',
    'btnD',
  ];

  /// Pmod connector names painted as labeled strips on the backdrop.
  /// Visual-only — see class doc.
  static const List<String> pmodNames = ['JA', 'JB', 'JXADC', 'JC', 'JD'];

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Digilent Nexys A7';

  @override
  String get description =>
      'Educational FPGA board: 16 LEDs, 16 slide switches, 5 push buttons, '
      '8-digit seven-segment display, Pmod headers.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.board;

  @override
  (double, double) get defaultSize => (720, 400);

  /// Boards pack 16 LEDs / 16 switches / 8 hex digits / 5 buttons
  /// into a fixed proportion. Below ~ 540 × 300 the per-cell
  /// primitives become unreadable.
  @override
  (double, double) get minSize => (540, 300);

  @override
  List<StageWidgetSlot> get slots => _slots;

  @override
  List<SignalBinding> get requiredSignals => const [];

  @override
  List<SignalBinding> get optionalSignals => [
    for (final slot in _slots)
      SignalBinding(
        name: slot.name,
        description: slot.label ?? slot.name,
        bitWidth: _slotBitWidth(slot),
      ),
  ];

  static int? _slotBitWidth(StageWidgetSlot slot) {
    if (slot.childWidgetId == LedStageWidget.widgetId) return 1;
    if (slot.childWidgetId == ToggleSwitchStageWidget.widgetId) return 1;
    return null;
  }

  static final List<StageWidgetSlot> _slots = _buildSlots();

  static List<StageWidgetSlot> _buildSlots() {
    // Vertical layout (normalized 0..1):
    //   0.00..0.06  Pmod connector strips at the top edge
    //   0.07        NEXYS A7 silkscreen title
    //   0.12..0.40  Seven-segment row + button cross
    //   0.43        7-SEG / BUTTONS silkscreens
    //   0.50..0.60  16 LEDs row
    //   0.62        LEDs silkscreen
    //   0.66..0.84  16 slide switches row
    //   0.88        SLIDE SWITCHES silkscreen

    const ledY = 0.50;
    const ledHeight = 0.10;
    const switchY = 0.66;
    const switchHeight = 0.18;
    const rowLeft = 0.05;
    const rowRight = 0.97;
    const rowSpan = rowRight - rowLeft;
    const cellWidth = rowSpan / ledCount;

    double xForIndex(int i) {
      // SW[0] / LD[0] sit at the right edge; index 15 at the left.
      return rowRight - cellWidth * (i + 1);
    }

    final ledSlots = <StageWidgetSlot>[
      for (var i = 0; i < ledCount; i++)
        StageWidgetSlot(
          name: 'led$i',
          childWidgetId: LedStageWidget.widgetId,
          x: xForIndex(i) + cellWidth * 0.1,
          y: ledY,
          width: cellWidth * 0.8,
          height: ledHeight,
          label: 'LED[$i]',
        ),
    ];

    final switchSlots = <StageWidgetSlot>[
      for (var i = 0; i < switchCount; i++)
        StageWidgetSlot(
          name: 'sw$i',
          childWidgetId: ToggleSwitchStageWidget.widgetId,
          x: xForIndex(i) + cellWidth * 0.05,
          y: switchY,
          width: cellWidth * 0.9,
          height: switchHeight,
          label: 'SW[$i]',
        ),
    ];

    // Eight seven-segment digits across the top-left half.
    const segLeft = 0.04;
    const segRight = 0.62;
    const segTop = 0.12;
    const segHeight = 0.28;
    const segDigitWidth = (segRight - segLeft) / digitCount;
    final segSlots = <StageWidgetSlot>[
      for (var i = 0; i < digitCount; i++)
        StageWidgetSlot(
          name: 'digit$i',
          childWidgetId: SevenSegmentStageWidget.widgetId,
          x: segLeft + segDigitWidth * i + segDigitWidth * 0.05,
          y: segTop,
          width: segDigitWidth * 0.9,
          height: segHeight,
          label: 'AN[$i]',
        ),
    ];

    // Push buttons in a cross: U at top, L/C/R in the middle row, D
    // at bottom. Positioned in the top-right area to leave room for
    // the seven-segment display on the left.
    const btnSize = 0.08;
    const btnCx = 0.83;
    const btnCy = 0.27;
    const btnDx = 0.10;
    const btnDy = 0.10;
    final buttonPositions = <String, (double, double)>{
      'btnU': (btnCx, btnCy - btnDy),
      'btnL': (btnCx - btnDx, btnCy),
      'btnC': (btnCx, btnCy),
      'btnR': (btnCx + btnDx, btnCy),
      'btnD': (btnCx, btnCy + btnDy),
    };
    final btnSlots = <StageWidgetSlot>[
      for (final name in buttonNames)
        StageWidgetSlot(
          name: name,
          childWidgetId: LedStageWidget.widgetId,
          x: buttonPositions[name]!.$1 - btnSize / 2,
          y: buttonPositions[name]!.$2 - btnSize / 2,
          width: btnSize,
          height: btnSize,
          label: name,
        ),
    ];

    return [...segSlots, ...btnSlots, ...ledSlots, ...switchSlots];
  }
}

/// Renderer for [NexysA7StageWidget].
class NexysA7StageRenderer extends ConsumerWidget {
  const NexysA7StageRenderer({required this.instance, super.key});

  final StageInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return BoardStageScaffold(
      instance: instance,
      compound: const NexysA7StageWidget(),
      backdropBuilder: (context) =>
          CustomPaint(painter: NexysA7BackdropPainter()),
      boardName: l10n.stageNexysA7DisplayName,
      trademarkDisclaimer: l10n.stageNexysA7TrademarkDisclaimer,
    );
  }
}

/// Paints the Nexys A7 board backdrop with the stylized palette.
/// Renders the PCB body, region silkscreens, and the five Pmod
/// connector strips along the top edge.
class NexysA7BackdropPainter extends CustomPainter {
  NexysA7BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const palette = boardPalette;
    final rect = Offset.zero & size;

    final pcbPaint = Paint()..color = palette.pcb;
    final pcbBorder = Paint()
      ..color = palette.pcbBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final body = RRect.fromRectAndRadius(
      rect.deflate(2),
      const Radius.circular(8),
    );
    canvas
      ..drawRRect(body, pcbPaint)
      ..drawRRect(body, pcbBorder);

    drawPmodStrips(
      canvas,
      size,
      NexysA7StageWidget.pmodNames,
      palette,
      stripsLeft: 0.04,
      stripsRight: 0.96,
    );

    drawBoardLabel(
      canvas,
      size,
      'NEXYS A7',
      size.width * 0.5,
      0.09,
      palette.silkscreenStrong,
    );
    drawBoardLabel(
      canvas,
      size,
      '7-SEG',
      size.width * 0.30,
      0.43,
      palette.silkscreen,
    );
    drawBoardLabel(
      canvas,
      size,
      'BUTTONS',
      size.width * 0.83,
      0.43,
      palette.silkscreen,
    );
    drawBoardLabel(
      canvas,
      size,
      'LEDs',
      size.width * 0.5,
      0.62,
      palette.silkscreen,
    );
    drawBoardLabel(
      canvas,
      size,
      'SLIDE SWITCHES',
      size.width * 0.5,
      0.88,
      palette.silkscreen,
    );
  }

  @override
  bool shouldRepaint(covariant NexysA7BackdropPainter old) => false;
}
