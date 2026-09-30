// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/features/stage/widgets/draggable_resizable_instance.dart'
    show applyBoardSlotDrop;
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

/// Color palette used by board backdrops. Single stylized scheme — the
/// "realistic PCB" alternate that used to live here was removed because
/// the connector silhouettes it added confused users without
/// communicating anything useful about the board.
@immutable
class BoardPalette {
  const BoardPalette({
    required this.pcb,
    required this.pcbBorder,
    required this.silkscreen,
    required this.silkscreenStrong,
    required this.connector,
  });

  final Color pcb;
  final Color pcbBorder;
  final Color silkscreen;
  final Color silkscreenStrong;
  final Color connector;
}

/// Default stylized palette — muted neutrals that let the LEDs and
/// switches read clearly without competing with the board chrome.
const BoardPalette boardPalette = BoardPalette(
  pcb: Color(0xFF1F2933),
  pcbBorder: Color(0xFF3F4D5C),
  silkscreen: Color(0xFF8DA1B7),
  silkscreenStrong: Color(0xFFD7E1EC),
  connector: Color(0xFF607D8B),
);

/// Paints a silkscreen-style label centered at `(cx, size.height *
/// cyFraction)`. Clamps to 90% of the board width and uses ellipsis
/// fallback so the silkscreen never clips against the card border.
///
/// Shared between board backdrop painters so the typographic look is
/// uniform across the lineup.
void drawBoardLabel(
  Canvas canvas,
  Size size,
  String text,
  double cx,
  double cyFraction,
  Color color,
) {
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

/// Paints a row of labeled Pmod connector silhouettes along a strip
/// of the board. Each name in [names] becomes one rounded rectangle
/// with the connector palette color and the name silkscreened on top.
///
/// Shared between board backdrop painters so the visual treatment of
/// Pmod headers is identical across Basys 3, Nexys A7, Arty A7, and
/// any future Open Core board with Pmod connectors.
void drawPmodStrips(
  Canvas canvas,
  Size size,
  List<String> names,
  BoardPalette palette, {
  double stripsLeft = 0.05,
  double stripsRight = 0.95,
  double stripTop = 0.005,
  double stripHeight = 0.05,
}) {
  if (names.isEmpty) return;
  final connectorPaint = Paint()..color = palette.connector;
  final stripsSpan = stripsRight - stripsLeft;
  final stripCellWidth = stripsSpan / names.length;

  for (var i = 0; i < names.length; i++) {
    final cellLeft = stripsLeft + stripCellWidth * i;
    final stripRect = Rect.fromLTWH(
      size.width * (cellLeft + stripCellWidth * 0.10),
      size.height * stripTop,
      size.width * stripCellWidth * 0.80,
      size.height * stripHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(stripRect, const Radius.circular(2)),
      connectorPaint,
    );
    drawBoardLabel(
      canvas,
      size,
      names[i],
      stripRect.left + stripRect.width / 2,
      (stripRect.top + stripRect.height / 2) / size.height,
      palette.silkscreenStrong,
    );
  }
}

/// Builds the painted backdrop for a board widget.
typedef BoardBackdropBuilder = Widget Function(BuildContext context);

/// Lays out a [CompoundStageWidget] over a painted board backdrop.
///
/// Each slot in the compound is rendered by looking up the child
/// widget's renderer in [StageWidgetRendererRegistry] and constructing a
/// derived [StageInstance] with the parent's binding for that slot's
/// `name`. This validates the compound composition model — child widgets
/// receive their bound signals and update as the cursor moves, exactly
/// like standalone primitives.
///
/// A small `ⓘ` icon in the top-right corner exposes the
/// [trademarkDisclaimer] via tooltip — a low-chrome way to credit the
/// trademark holder per Section 4.4.1 without consuming canvas space
/// like a footer line would.
class BoardStageScaffold extends ConsumerWidget {
  const BoardStageScaffold({
    required this.instance,
    required this.compound,
    required this.backdropBuilder,
    required this.boardName,
    required this.trademarkDisclaimer,
    super.key,
  });

  final StageInstance instance;
  final CompoundStageWidget compound;
  final BoardBackdropBuilder backdropBuilder;
  final String boardName;

  /// Trademark + endorsement-disclaimer string shown via the corner
  /// info-icon's tooltip. Each board widget supplies its own.
  final String trademarkDisclaimer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renderers = StageWidgetRendererRegistry.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : compound.defaultSize.$1;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : compound.defaultSize.$2;

        return Stack(
          children: [
            Positioned.fill(child: backdropBuilder(context)),
            for (final slot in compound.slots)
              Positioned(
                key: ValueKey('boardSlot:${instance.id}:${slot.name}'),
                left: slot.x * width,
                top: slot.y * height,
                width: slot.width * width,
                height: slot.height * height,
                child: _BoardSlot(
                  parentInstance: instance,
                  slot: slot,
                  renderer: renderers.get(slot.childWidgetId),
                  parentSlots: compound.slots,
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: _TrademarkInfoIcon(
                key: ValueKey('boardTrademarkInfo:${instance.id}'),
                disclaimer: trademarkDisclaimer,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Small info-icon that surfaces a board's trademark disclaimer via
/// tooltip. Tap-trigger so touch users don't have to long-press; the
/// tooltip lingers a few seconds for readability.
class _TrademarkInfoIcon extends StatelessWidget {
  const _TrademarkInfoIcon({required this.disclaimer, super.key});

  final String disclaimer;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: disclaimer,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      preferBelow: false,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.info_outline,
          size: 14,
          color: Colors.white70,
        ),
      ),
    );
  }
}

/// One child-widget slot inside a board.
///
/// Looks up the child's renderer in [StageWidgetRendererRegistry] and
/// constructs a derived [StageInstance] whose `signalBindings` carry the
/// parent's bindings for this slot.
///
/// **Single-pin slot** (the common case — LED, toggle, seven-segment,
/// bus_readout): the parent's binding stored under `slot.name` is mapped
/// to the child widget's primary input pin (`'in'` for LED / toggle,
/// `'value'` for seven-segment / level_bar / bus_readout / state_indicator
/// / signal_graph).
///
/// **Multi-pin slot** (when `slot.pinBindings != null` — the Pro
/// framebuffer slots on Pro board widgets): each entry in `pinBindings`
/// maps a child-widget pin name to a sibling slot's name; the binding
/// for that pin is read from `parentInstance.signalBindings[<sibling>]`.
/// The slot's own `slot.name` binding is **not** used in this branch —
/// the data pin is sourced from a sibling slot just like the others, so
/// every pin has its own drop target chip in the layout.
class _BoardSlot extends ConsumerWidget {
  const _BoardSlot({
    required this.parentInstance,
    required this.slot,
    required this.renderer,
    required this.parentSlots,
  });

  final StageInstance parentInstance;
  final StageWidgetSlot slot;
  final StageInstanceRenderer? renderer;

  /// All slots on the parent compound widget. Used so the drop handler
  /// can recognise slot families (`led0..led15`) and fan a multi-bit
  /// vector signal out across them.
  final List<StageWidgetSlot> parentSlots;

  String get slotName => slot.name;
  String get childWidgetId => slot.childWidgetId;
  String? get label => slot.label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bindings = <String, StageSignalBinding>{};

    if (slot.isMultiPin) {
      // Each entry: pin name on the child widget → sibling slot name on
      // the parent whose binding feeds that pin.
      for (final entry in slot.pinBindings!.entries) {
        final pinName = entry.key;
        final siblingSlotName = entry.value;
        final binding = parentInstance.signalBindings[siblingSlotName];
        if (binding != null && binding.signalRef.isNotEmpty) {
          bindings[pinName] = binding;
        }
      }
    } else {
      final boundBinding = parentInstance.signalBindings[slotName];
      if (boundBinding != null && boundBinding.signalRef.isNotEmpty) {
        bindings[childInputPinName(childWidgetId)] = boundBinding;
      }
    }

    final childInstance = StageInstance(
      id: '${parentInstance.id}:$slotName',
      widgetId: childWidgetId,
      signalBindings: bindings,
    );

    final body = renderer == null
        ? const SizedBox.shrink()
        : renderer!(context, childInstance);

    final Widget content;
    if (label == null || label!.isEmpty) {
      content = body;
    } else {
      // Compute the label-row height with both a proportional rule
      // and a minimum-height floor:
      //
      // - **Proportional**: 1/3 of slot height (matches the prior 2:1
      //   body:label flex). Works well for LEDs (48 dp slots) and up.
      // - **Minimum floor**: 14 dp regardless of slot height. Slots
      //   like the DE10-Nano `KEY[0..1]` push buttons and `ADC[0..7]`
      //   channels are intrinsically short (0.06 board-height fraction
      //   → ~28 dp tall at the default surface). At 1/3 they'd give
      //   labels just 9.6 dp, which renders below the 8 dp legibility
      //   floor. The floor lifts those to a comfortable ~10 dp label
      //   fontSize.
      // - **Cap at 1/2**: very short slots (HDMI chip strip ~15 dp)
      //   need *some* room left for the body. Capping the label at
      //   half the slot height keeps the LED chip visible even when
      //   the floor would otherwise consume the entire slot.
      //
      // The body's size is monotonic in the slot size so primitives
      // still shrink predictably with the board (no hysteresis from
      // FittedBox-driven re-flow as in the original layout).
      content = LayoutBuilder(
        builder: (context, constraints) {
          final slotHeight = constraints.maxHeight;
          final third = slotHeight / 3;
          final cappedFloor = slotHeight / 2 < 14 ? slotHeight / 2 : 14.0;
          final labelHeight = third > cappedFloor ? third : cappedFloor;
          final bodyHeight = slotHeight - labelHeight;
          return Column(
            children: [
              SizedBox(height: bodyHeight, child: body),
              SizedBox(
                height: labelHeight,
                child: _BoardSlotLabel(label: label!),
              ),
            ],
          );
        },
      );
    }

    // Multi-pin slots (Pro framebuffer / similar peripheral primitives)
    // do not accept drag-to-bind directly — there is no single pin to
    // bind to. Users bind each pin via its sibling chip slot, which is
    // a standard single-pin slot whose name is referenced in
    // `pinBindings`. Returning the content as-is here lets the outer
    // board-tile drop target take over via the gesture arena.
    if (slot.isMultiPin) {
      return content;
    }

    // Per-slot drop target: when a signal is dragged from the tree
    // and dropped on this LED / switch / 7-seg slot, the dropped ref
    // is bound to the slot's pin on the parent board instance —
    // skipping the 30-item disambiguator menu. The slot's deeper
    // DragTarget wins over the outer board-tile target via gesture
    // arena depth.
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        // Look up the child primitive's expected bitWidth so the bit
        // picker fires only when this slot is genuinely 1-bit. LED and
        // switch primitives declare bitWidth: 1 on their input pin in
        // requiredSignals; seven-segment, bus readout, and level bar
        // declare their pins in optionalSignals (with bitWidth: null,
        // i.e. accept any width). Walk both lists and tolerate a
        // missing pin definition — falling back to `null` bitWidth so
        // applyBoardSlotDrop does not prompt for a single bit on a
        // vector-accepting slot.
        final childDef = StageRegistry.instance.get(childWidgetId);
        final pinName = childInputPinName(childWidgetId);
        SignalBinding? childPin;
        if (childDef != null) {
          for (final b in [
            ...childDef.requiredSignals,
            ...childDef.optionalSignals,
          ]) {
            if (b.name == pinName) {
              childPin = b;
              break;
            }
          }
        }
        unawaited(
          applyBoardSlotDrop(
            context,
            ref,
            instanceId: parentInstance.id,
            slotName: slotName,
            pinBitWidth: childPin?.bitWidth,
            signalRef: details.data,
            parentSlots: parentSlots,
          ),
        );
      },
      builder: (context, candidate, rejected) {
        if (candidate.isEmpty) return content;
        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.20),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Renders a board slot's silkscreen label (e.g. `LED[0]`, `SW[15]`,
/// `BTN[U]`, `HDMI OUT`) and degrades gracefully on small board sizes.
///
/// Three behaviour layers, all running off a single `LayoutBuilder`:
///
/// 1. **`BoxFit.contain`** instead of `BoxFit.scaleDown` lets the label
///    scale UP to fill its allocated row when the board is large — the
///    pre-fix renderer capped the label at fontSize 9 so labels stayed
///    tiny even at standard window sizes.
/// 2. **Width-aware abbreviation** for indexed labels: when the full
///    label can't fit at a legible size, fall back to just the bracketed
///    or trailing-digit token. `LED[0]` → `0`, `SW[15]` → `15`,
///    `BTN[U]` → `U`, `HEX0` → `0`, `LED7 (RGB)` → `7`. Multi-word
///    peripheral labels (`HDMI OUT`, `AUDIO MIC`, `ACCEL`) have no
///    short form so they stay full-text — those slots are roomier on
///    every board lineup so legibility was never an issue.
/// 3. **Legibility floor** — only switch to the abbreviation when the
///    full label would render below ~9 dp. Above that floor the full
///    label is readable, so prefer it. This keeps existing widget tests
///    that assert on the full-label string passing at default surface
///    sizes (800 × 480) while small / nested-board renderings get the
///    short form automatically.
class _BoardSlotLabel extends StatelessWidget {
  const _BoardSlotLabel({required this.label});

  final String label;

  /// Approximate width per monospace character at fontSize 1.
  static const double _charWidthRatio = 0.6;

  /// Approximate vertical advance per line at fontSize 1 for `labelSmall`.
  static const double _lineHeightRatio = 1.4;

  /// Effective fontSize below which the label is no longer readable —
  /// the cutoff at which abbreviation kicks in. With the label-row
  /// height floor of 14 dp keeping most slots above this threshold
  /// (KEY/ADC at default board sizes render around fontSize 10 dp),
  /// abbreviation now only fires on genuinely cramped surfaces — small
  /// board widgets nested inside compound layouts, or windows resized
  /// well below normal usage.
  static const double _legibilityFloor = 8;

  /// Returns the abbreviated form of [full] for indexed slot labels.
  ///
  /// - Bracketed token wins: `LED[0]` → `0`, `SW[15]` → `15`,
  ///   `BTN[U]` → `U`, `KEY[C]` → `C`, `LED[4] (RGB)` → `4`.
  /// - Otherwise pick the first run of digits: `HEX0` → `0`,
  ///   `ADC5` → `5`, `LED7 (RGB)` → `7`.
  /// - Falls back to the original string when no abbreviation pattern
  ///   matches: `HDMI OUT`, `AUDIO MIC`, `ACCEL` stay as-is.
  static String abbreviate(String full) {
    final bracketMatch = RegExp(r'\[([^\]]+)\]').firstMatch(full);
    if (bracketMatch != null) return bracketMatch.group(1)!;
    final digitMatch = RegExp(r'\d+').firstMatch(full);
    if (digitMatch != null) return digitMatch.group(0)!;
    return full;
  }

  /// Estimates the maximum legible fontSize for [s] inside a
  /// `width × height` box, preserving aspect ratio. Mirrors what
  /// `BoxFit.contain` would compute for a rendered `Text` of length
  /// `s.length` in a monospace font.
  static double _maxFontSize(String s, double width, double height) {
    if (s.isEmpty) return 0;
    final widthLimit = width / (s.length * _charWidthRatio);
    final heightLimit = height / _lineHeightRatio;
    return widthLimit < heightLimit ? widthLimit : heightLimit;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abbr = abbreviate(label);
    final hasAbbreviation = abbr != label;
    return LayoutBuilder(
      builder: (context, c) {
        final fullSize = _maxFontSize(label, c.maxWidth, c.maxHeight);
        // Use the abbreviation when the full label would render below
        // the legibility floor. At those sizes the limiting dimension
        // is typically the label-row height — the full string and the
        // abbreviation render at the same effective fontSize, but a
        // single character is recognisable where a six-character
        // string smudges into a featureless line. When the limiting
        // dimension is width (rare with the 3:1 body:label flex but
        // possible for narrow slots like the Pmod chip strips), the
        // abbreviation also lets the text render at a bigger fontSize.
        final useAbbr = hasAbbreviation && fullSize < _legibilityFloor;
        final picked = useAbbr ? abbr : label;
        // FittedBox defaults to `BoxFit.contain` + `Alignment.center` —
        // both spelled out via doc comments above; passing them
        // explicitly would trip the redundant-argument lint.
        return FittedBox(
          child: Text(
            picked,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: Colors.white70,
              fontSize: 14,
            ),
            maxLines: 1,
          ),
        );
      },
    );
  }
}

/// Returns the primary signal-input pin name for the child widgets used
/// by built-in board slots.
///
/// Board slots currently bind one signal per child — the LED and toggle
/// switch use `'in'`, the seven-segment uses `'value'`. Unknown child
/// types fall back to `'in'`.
String childInputPinName(String childWidgetId) {
  switch (childWidgetId) {
    case 'seven_segment':
    case 'level_bar':
    case 'bus_readout':
    case 'state_indicator':
    case 'signal_graph':
      return 'value';
    case 'led':
    case 'toggle_switch':
    default:
      return 'in';
  }
}
