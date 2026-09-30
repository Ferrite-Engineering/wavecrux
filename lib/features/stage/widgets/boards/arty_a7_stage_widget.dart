// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/features/stage/widgets/boards/board_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Stage compound widget for the Digilent Arty A7 (Xilinx/AMD)
/// maker / RISC-V hobbyist FPGA development board.
///
/// I/O: 4 plain LEDs (`led0`–`led3`), 4 **RGB-capable** LED positions
/// (`led4`–`led7`), 4 push buttons (`btn0`–`btn3`), 4 slide switches
/// (`sw0`–`sw3`), and four Pmod headers (`JA`/`JB`/`JC`/`JD`) drawn
/// as labeled connector strips.
///
/// **Open Core RGB rendering:** the four RGB LED positions are
/// rendered as plain LEDs driven by a single bound channel. The
/// bindings pane row for those slots surfaces an upgrade hint
/// pointing the user at the Pro RGB LED widget for full three-channel
/// rendering. This is the documented "graceful degradation for
/// Pro-peripheral pins" pattern: Open Core boards with pins wired to
/// peripherals beyond the free primitive set render those pins with a
/// free fallback (plain LED for RGB, no-op for unknown peripherals)
/// and surface a discoverable upgrade hint, keeping the Open Core
/// experience honest without hiding the Pro capability.
class ArtyA7StageWidget extends CompoundStageWidget {
  const ArtyA7StageWidget();

  static const String widgetId = 'artyA7';

  static const int plainLedCount = 4;
  static const int rgbLedCount = 4;
  static const int switchCount = 4;
  static const int buttonCount = 4;

  /// Pmod connector names painted as labeled strips on the backdrop.
  /// Visual-only — no signal binding (Pmod is generic).
  static const List<String> pmodNames = ['JA', 'JB', 'JC', 'JD'];

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Digilent Arty A7';

  @override
  String get description =>
      'Pmod-centric maker FPGA board: 4 LEDs, 4 RGB LED positions, '
      '4 push buttons, 4 slide switches, 4 Pmod headers.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.board;

  @override
  (double, double) get defaultSize => (560, 360);

  @override
  (double, double) get minSize => (440, 280);

  @override
  List<StageWidgetSlot> get slots => _slots;

  @override
  List<SignalBinding> get requiredSignals => const [];

  /// Slots for which the bindings pane should surface the
  /// "Upgrade to Pro for full RGB rendering" hint instead of the
  /// generic slot label. Matches the LD4–LD7 RGB-capable positions.
  static bool _isRgbLedSlot(StageWidgetSlot slot) =>
      slot.childWidgetId == LedStageWidget.widgetId &&
      slot.name.startsWith('led') &&
      (int.tryParse(slot.name.substring(3)) ?? -1) >= plainLedCount;

  /// Look-up used by widget tests so the Pro-upgrade hint pattern is
  /// shared with future boards instead of being baked into one place.
  static bool isRgbLedSlotName(String slotName) =>
      slotName.startsWith('led') &&
      (int.tryParse(slotName.substring(3)) ?? -1) >= plainLedCount &&
      (int.tryParse(slotName.substring(3)) ?? -1) < plainLedCount + rgbLedCount;

  @override
  List<SignalBinding> get optionalSignals => [
    for (final slot in _slots) _bindingForSlot(slot),
  ];

  /// Builds a [SignalBinding] for [slot]. RGB LED slots receive a
  /// description placeholder that the renderer (which has access to
  /// localized strings) substitutes with the upgrade hint when
  /// rendering the bindings pane. Non-RGB slots use the slot label.
  SignalBinding _bindingForSlot(StageWidgetSlot slot) {
    final isRgb = _isRgbLedSlot(slot);
    return SignalBinding(
      name: slot.name,
      // The literal `__rgb_pro_upgrade_hint__` sentinel is replaced
      // with the localized hint string by the renderer / bindings
      // pane. We can't access [BuildContext]/L10N from a const
      // optionalSignals getter, so this is the simplest decoupling.
      description: isRgb
          ? '__rgb_pro_upgrade_hint__'
          : (slot.label ?? slot.name),
      bitWidth: _slotBitWidth(slot),
    );
  }

  static int? _slotBitWidth(StageWidgetSlot slot) {
    if (slot.childWidgetId == LedStageWidget.widgetId) return 1;
    if (slot.childWidgetId == ToggleSwitchStageWidget.widgetId) return 1;
    return null;
  }

  static final List<StageWidgetSlot> _slots = _buildSlots();

  static List<StageWidgetSlot> _buildSlots() {
    // Vertical layout (normalized 0..1):
    //   0.00..0.06  Pmod connector strips at the top edge (4 strips)
    //   0.07        ARTY A7 silkscreen title
    //   0.20..0.32  Plain LEDs row (LD0..LD3, left)
    //               + RGB LED positions row (LD4..LD7, right)
    //   0.36        LEDs / RGB silkscreens
    //   0.50..0.62  Buttons row + Switches row
    //   0.66        BUTTONS / SWITCHES silkscreens
    //   0.74..0.92  (free space — Arty A7 doesn't have switch silkscreen text)

    const ledRowY = 0.22;
    const ledRowHeight = 0.10;
    const switchRowY = 0.55;
    const switchRowHeight = 0.18;
    const btnRowY = 0.55;
    const btnRowHeight = 0.10;

    // Plain LEDs LD0..LD3 in the left half (right-most = LD0).
    const plainLedsLeft = 0.06;
    const plainLedsRight = 0.46;
    const plainCellSpan = (plainLedsRight - plainLedsLeft) / plainLedCount;
    final plainLedSlots = <StageWidgetSlot>[
      for (var i = 0; i < plainLedCount; i++)
        StageWidgetSlot(
          name: 'led$i',
          childWidgetId: LedStageWidget.widgetId,
          // LD0 right-most for vendor-pin convention parity.
          x: plainLedsRight - plainCellSpan * (i + 1) + plainCellSpan * 0.10,
          y: ledRowY,
          width: plainCellSpan * 0.80,
          height: ledRowHeight,
          label: 'LED[$i]',
        ),
    ];

    // RGB LED positions LD4..LD7 in the right half (right-most = LD4).
    const rgbLedsLeft = 0.54;
    const rgbLedsRight = 0.94;
    const rgbCellSpan = (rgbLedsRight - rgbLedsLeft) / rgbLedCount;
    final rgbLedSlots = <StageWidgetSlot>[
      for (var i = 0; i < rgbLedCount; i++)
        StageWidgetSlot(
          name: 'led${plainLedCount + i}',
          childWidgetId: LedStageWidget.widgetId,
          x: rgbLedsRight - rgbCellSpan * (i + 1) + rgbCellSpan * 0.10,
          y: ledRowY,
          width: rgbCellSpan * 0.80,
          height: ledRowHeight,
          label: 'LED[${plainLedCount + i}] (RGB)',
        ),
    ];

    // Slide switches SW0..SW3 in the left half (right-most = SW0).
    const switchesLeft = 0.06;
    const switchesRight = 0.46;
    const switchCellSpan = (switchesRight - switchesLeft) / switchCount;
    final switchSlots = <StageWidgetSlot>[
      for (var i = 0; i < switchCount; i++)
        StageWidgetSlot(
          name: 'sw$i',
          childWidgetId: ToggleSwitchStageWidget.widgetId,
          x: switchesRight - switchCellSpan * (i + 1) + switchCellSpan * 0.05,
          y: switchRowY,
          width: switchCellSpan * 0.90,
          height: switchRowHeight,
          label: 'SW[$i]',
        ),
    ];

    // Push buttons BTN0..BTN3 in the right half (right-most = BTN0).
    const btnsLeft = 0.54;
    const btnsRight = 0.94;
    const btnCellSpan = (btnsRight - btnsLeft) / buttonCount;
    final buttonSlots = <StageWidgetSlot>[
      for (var i = 0; i < buttonCount; i++)
        StageWidgetSlot(
          name: 'btn$i',
          childWidgetId: LedStageWidget.widgetId,
          x: btnsRight - btnCellSpan * (i + 1) + btnCellSpan * 0.20,
          y: btnRowY + (switchRowHeight - btnRowHeight) / 2,
          width: btnCellSpan * 0.60,
          height: btnRowHeight,
          label: 'BTN[$i]',
        ),
    ];

    return [
      ...plainLedSlots,
      ...rgbLedSlots,
      ...switchSlots,
      ...buttonSlots,
    ];
  }
}

/// Renderer for [ArtyA7StageWidget].
///
/// Looks up the localized RGB Pro-upgrade hint and substitutes it
/// into the bindings pane via the same `optionalSignals` plumbing
/// the standalone primitives use — see
/// `[ArtyA7StageWidget._bindingForSlot]` for the sentinel string.
class ArtyA7StageRenderer extends ConsumerWidget {
  const ArtyA7StageRenderer({required this.instance, super.key});

  final StageInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return BoardStageScaffold(
      instance: instance,
      compound: const ArtyA7StageWidget(),
      backdropBuilder: (context) =>
          CustomPaint(painter: ArtyA7BackdropPainter()),
      boardName: l10n.stageArtyA7DisplayName,
      trademarkDisclaimer: l10n.stageArtyA7TrademarkDisclaimer,
    );
  }
}

/// Resolves the placeholder description string used by RGB LED slots
/// on Open Core boards into the localized "Upgrade to Pro for full
/// RGB rendering" hint. The bindings pane calls this on every
/// [SignalBinding.description] before rendering so the descriptions
/// can be authored at the slot-definition level (where there's no
/// [BuildContext]) and resolved at draw time.
/// [isMobileHost] is a test seam; `null` defers to the real
/// [isMobileHostPlatform]. It exists because `flutter_test` reports
/// `TargetPlatform.android` by default, so a bare platform read would silently
/// give every widget test the mobile wording.
String resolveBindingDescription(
  String raw,
  L10N l10n, {
  bool? isMobileHost,
}) {
  if (raw == '__rgb_pro_upgrade_hint__') {
    // On iOS/Android the upsell wording is dropped in favor of a plain
    // statement of what the slot renders. "Open Core renders one channel
    // only" describes a shipped feature as partial (App Store Review
    // Guideline 2.2), and "Upgrade to Pro" is an external purchase call-to-
    // action inside the app (3.1.1). The behavior is identical either way —
    // only the framing differs, and only on the store-distributed hosts.
    return (isMobileHost ?? isMobileHostPlatform)
        ? l10n.stageRgbLedChannelNote
        : l10n.stageRgbLedProUpgradeHint;
  }
  return raw;
}

/// Paints the Arty A7 board backdrop with the stylized palette.
class ArtyA7BackdropPainter extends CustomPainter {
  ArtyA7BackdropPainter();

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
      ArtyA7StageWidget.pmodNames,
      palette,
      stripsLeft: 0.06,
      stripsRight: 0.94,
    );

    drawBoardLabel(
      canvas,
      size,
      'ARTY A7',
      size.width * 0.5,
      0.10,
      palette.silkscreenStrong,
    );
    drawBoardLabel(
      canvas,
      size,
      'LEDs',
      size.width * 0.26,
      0.36,
      palette.silkscreen,
    );
    drawBoardLabel(
      canvas,
      size,
      'RGB',
      size.width * 0.74,
      0.36,
      palette.silkscreen,
    );
    drawBoardLabel(
      canvas,
      size,
      'SWITCHES',
      size.width * 0.26,
      0.78,
      palette.silkscreen,
    );
    drawBoardLabel(
      canvas,
      size,
      'BUTTONS',
      size.width * 0.74,
      0.78,
      palette.silkscreen,
    );
  }

  @override
  bool shouldRepaint(covariant ArtyA7BackdropPainter old) => false;
}
