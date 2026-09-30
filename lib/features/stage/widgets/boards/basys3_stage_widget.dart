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

/// Stage compound widget for the Digilent Basys 3 (Xilinx/AMD) FPGA
/// development board.
///
/// The board exposes 16 LEDs, 16 slide switches, 5 push buttons, and a
/// 4-digit common-anode seven-segment display. Slot names mirror the
/// vendor constraint-file pin names (`led0`–`led15`, `sw0`–`sw15`,
/// `btnC`/`btnU`/`btnL`/`btnR`/`btnD`, `digit0`–`digit3`) so users can
/// drop-in their top-level ports.
class Basys3StageWidget extends CompoundStageWidget {
  const Basys3StageWidget();

  static const String widgetId = 'basys3';

  static const int ledCount = 16;
  static const int switchCount = 16;
  static const int digitCount = 4;
  static const List<String> buttonNames = [
    'btnC',
    'btnU',
    'btnL',
    'btnR',
    'btnD',
  ];

  /// Pmod connector names painted as labeled strips on the top edge
  /// of the board, mirroring the silkscreen on real Basys 3 hardware
  /// (JA, JB, JC, JXADC). Visual-only — no signal binding (Pmod is
  /// generic mezzanine I/O; users wire individual Pmod pins to
  /// standalone primitives in their Stage).
  static const List<String> pmodNames = ['JA', 'JB', 'JC', 'JXADC'];

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Digilent Basys 3';

  @override
  String get description =>
      'Educational FPGA board: 16 LEDs, 16 slide switches, 5 push buttons, '
      '4-digit seven-segment display.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.board;

  @override
  (double, double) get defaultSize => (640, 360);

  /// Boards pack 16 LEDs / 16 switches / a 7-segment row into a fixed
  /// proportion, so the per-cell primitives become unreadable below
  /// ~ 480 × 270. The min size keeps the board legible.
  @override
  (double, double) get minSize => (480, 270);

  /// Slot layout in normalized board coordinates (0..1 in each axis).
  ///
  /// Visual layout:
  /// - Seven-segment display: top-left
  /// - Push button cross: top-right (btnU / btnL btnC btnR / btnD)
  /// - 16 LEDs in a row above the switches; LED[0] rightmost
  /// - 16 slide switches at the bottom; SW[0] rightmost
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
    const ledY = 0.58;
    const ledHeight = 0.10;
    // Switches lifted from 0.78 to 0.74 (bottom edge 0.92) so the
    // "SLIDE SWITCHES" silkscreen below them fits inside the board
    // outline at any board size.
    const switchY = 0.74;
    const switchHeight = 0.18;
    const rowLeft = 0.05;
    const rowRight = 0.97;
    const rowSpan = rowRight - rowLeft;
    const cellWidth = rowSpan / ledCount;

    double xForIndex(int i) {
      // SW[0] / LD[0] sit at the right edge; index 15 at the left.
      final idxFromRight = i;
      return rowRight - cellWidth * (idxFromRight + 1);
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

    // Seven-segment display: top-left, four digits left-to-right.
    const segLeft = 0.04;
    const segRight = 0.46;
    const segTop = 0.10;
    const segHeight = 0.30;
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

    // Push buttons in a cross: U at top, L/C/R in the middle row, D at bottom.
    const btnSize = 0.10;
    const btnCx = 0.78;
    const btnCy = 0.25;
    const btnDx = 0.13;
    const btnDy = 0.13;
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

/// Renderer for [Basys3StageWidget].
class Basys3StageRenderer extends ConsumerWidget {
  const Basys3StageRenderer({required this.instance, super.key});

  final StageInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return BoardStageScaffold(
      instance: instance,
      compound: const Basys3StageWidget(),
      backdropBuilder: (context) =>
          CustomPaint(painter: Basys3BackdropPainter()),
      boardName: l10n.stageBasys3DisplayName,
      trademarkDisclaimer: l10n.stageBasys3TrademarkDisclaimer,
    );
  }
}

/// Paints the Basys 3 board backdrop with the stylized palette.
class Basys3BackdropPainter extends CustomPainter {
  Basys3BackdropPainter();

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

    // Pmod connector strips along the top edge — JA, JB, JC, JXADC
    // mirror the silkscreen on real Basys 3 hardware. Visual-only.
    drawPmodStrips(
      canvas,
      size,
      Basys3StageWidget.pmodNames,
      palette,
    );

    // Silkscreen labels for the major regions. Kept short — each row's
    // primitives carry their own per-cell labels (LED[0]…LED[15], etc.)
    // so the silkscreen labels don't need to repeat the index range.
    // BASYS 3 title shifted from 0.04 → 0.08 to clear the new Pmod
    // strip row at y=0.005..0.055.
    drawBoardLabel(
      canvas,
      size,
      'BASYS 3',
      size.width * 0.5,
      0.08,
      palette.silkscreenStrong,
    );
    drawBoardLabel(
      canvas,
      size,
      '7-SEG',
      size.width * 0.25,
      0.43,
      palette.silkscreen,
    );
    // BUTTONS label sits below the cross of push buttons (btnD at
    // y≈0.38, btnSize=0.10 → bottom edge ≈ 0.43). Push the label
    // further down so it doesn't overlap the bottom button.
    drawBoardLabel(
      canvas,
      size,
      'BUTTONS',
      size.width * 0.78,
      0.50,
      palette.silkscreen,
    );
    drawBoardLabel(
      canvas,
      size,
      'LEDs',
      size.width * 0.5,
      0.71,
      palette.silkscreen,
    );
    // Sits in the gap between the switch row (bottom edge ≈ 0.92)
    // and the board outline (1.0). Center at 0.96 so the label has
    // visible breathing room above and below.
    drawBoardLabel(
      canvas,
      size,
      'SLIDE SWITCHES',
      size.width * 0.5,
      0.96,
      palette.silkscreen,
    );
  }

  @override
  bool shouldRepaint(covariant Basys3BackdropPainter old) => false;
}
