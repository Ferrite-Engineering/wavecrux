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

/// Stage compound widget for the Terasic DE10-Lite (Intel/Altera) FPGA
/// development board.
///
/// The board exposes 10 LEDs, 10 slide switches, two push buttons, and
/// six independent seven-segment displays. Slot names mirror the vendor
/// constraint-file pin names (`ledr0`–`ledr9`, `sw0`–`sw9`, `key0` /
/// `key1`, `hex0`–`hex5`) so users can drop-in their top-level ports
/// from a Quartus design.
class De10LiteStageWidget extends CompoundStageWidget {
  const De10LiteStageWidget();

  static const String widgetId = 'de10_lite';

  static const int ledCount = 10;
  static const int switchCount = 10;
  static const int hexCount = 6;
  static const List<String> buttonNames = ['key0', 'key1'];

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Terasic DE10-Lite';

  @override
  String get description =>
      'Educational FPGA board: 10 LEDs, 10 slide switches, 2 push buttons, '
      'six 7-segment displays.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.board;

  @override
  (double, double) get defaultSize => (640, 360);

  /// Boards pack 10 LEDs / 10 switches / 6 hex digits into a fixed
  /// proportion, so the per-cell primitives become unreadable below
  /// ~ 460 × 260. The min size keeps the board legible.
  @override
  (double, double) get minSize => (460, 260);

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
    const ledY = 0.55;
    const ledHeight = 0.10;
    const switchY = 0.72;
    const switchHeight = 0.20;
    const rowLeft = 0.05;
    const rowRight = 0.97;
    const rowSpan = rowRight - rowLeft;
    const cellWidth = rowSpan / ledCount;

    double xForIndex(int i) {
      // LEDR[0] / SW[0] sit at the right edge; index 9 at the left.
      return rowRight - cellWidth * (i + 1);
    }

    final ledSlots = <StageWidgetSlot>[
      for (var i = 0; i < ledCount; i++)
        StageWidgetSlot(
          name: 'ledr$i',
          childWidgetId: LedStageWidget.widgetId,
          x: xForIndex(i) + cellWidth * 0.1,
          y: ledY,
          width: cellWidth * 0.8,
          height: ledHeight,
          label: 'LEDR[$i]',
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

    // Six seven-segment displays: HEX5 leftmost, HEX0 rightmost.
    const segLeft = 0.05;
    const segRight = 0.65;
    const segTop = 0.10;
    const segHeight = 0.30;
    const segDigitWidth = (segRight - segLeft) / hexCount;
    final hexSlots = <StageWidgetSlot>[
      for (var i = 0; i < hexCount; i++)
        StageWidgetSlot(
          name: 'hex$i',
          childWidgetId: SevenSegmentStageWidget.widgetId,
          // HEX5 sits leftmost so place index from right side.
          x:
              segLeft +
              segDigitWidth * (hexCount - 1 - i) +
              segDigitWidth * 0.05,
          y: segTop,
          width: segDigitWidth * 0.9,
          height: segHeight,
          label: 'HEX$i',
        ),
    ];

    // Two push buttons: KEY[1] left, KEY[0] right.
    const btnSize = 0.10;
    const btnY = 0.20;
    final buttonPositions = <String, double>{
      'key1': 0.78,
      'key0': 0.91,
    };
    final btnSlots = <StageWidgetSlot>[
      for (final name in buttonNames)
        StageWidgetSlot(
          name: name,
          childWidgetId: LedStageWidget.widgetId,
          x: buttonPositions[name]! - btnSize / 2,
          y: btnY,
          width: btnSize,
          height: btnSize,
          label: 'KEY[${name.substring(3)}]',
        ),
    ];

    return [...hexSlots, ...btnSlots, ...ledSlots, ...switchSlots];
  }
}

/// Renderer for [De10LiteStageWidget].
class De10LiteStageRenderer extends ConsumerWidget {
  const De10LiteStageRenderer({required this.instance, super.key});

  final StageInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return BoardStageScaffold(
      instance: instance,
      compound: const De10LiteStageWidget(),
      backdropBuilder: (context) =>
          CustomPaint(painter: De10LiteBackdropPainter()),
      boardName: l10n.stageDe10LiteDisplayName,
      trademarkDisclaimer: l10n.stageDe10LiteTrademarkDisclaimer,
    );
  }
}

/// Paints the DE10-Lite board backdrop with the stylized palette.
class De10LiteBackdropPainter extends CustomPainter {
  De10LiteBackdropPainter();

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

    // Silkscreen labels for the major regions. Each primitive carries
    // its own per-cell label (HEX0…HEX5, LEDR[i], SW[i]) so the
    // backdrop labels stay short.
    _drawLabel(
      canvas,
      size,
      'DE10-Lite',
      size.width * 0.5,
      0.04,
      palette.silkscreenStrong,
    );
    _drawLabel(
      canvas,
      size,
      'HEX',
      size.width * 0.35,
      0.43,
      palette.silkscreen,
    );
    // KEYs label sits below the two push buttons (key0/key1 at y≈0.20
    // with size 0.10 → bottom edge ≈ 0.25). Move the label far enough
    // away that the centered text doesn't crowd the buttons at small
    // board sizes.
    _drawLabel(
      canvas,
      size,
      'KEYs',
      size.width * 0.85,
      0.40,
      palette.silkscreen,
    );
    _drawLabel(
      canvas,
      size,
      'LEDs',
      size.width * 0.5,
      0.68,
      palette.silkscreen,
    );
    _drawLabel(
      canvas,
      size,
      'SWITCHES',
      size.width * 0.5,
      0.96,
      palette.silkscreen,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Size size,
    String text,
    double cx,
    double cyFraction,
    Color color,
  ) {
    // Clamp to 90% of the board width and let TextPainter ellipsis the
    // overflow so the silkscreen never clips against the card border.
    final maxWidth = size.width * 0.9;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: (size.height * 0.025).clamp(8, 14),
          letterSpacing: 1.1,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, size.height * cyFraction - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant De10LiteBackdropPainter old) => false;
}
