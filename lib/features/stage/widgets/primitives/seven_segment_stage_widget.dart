// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Display radix for the [SevenSegmentStageWidget] in value mode.
enum SevenSegmentRadix { decimal, hexadecimal }

/// Pure logic: convert a signal value to the per-digit characters drawn on
/// the seven-segment display in **value mode**.
///
/// Returns a list of characters of length [digitCount]. Each entry is a
/// hex digit `'0'..'9' / 'a'..'f'`, an `'-'` for blank/unbound, or `'x'`
/// when the digit cannot be represented (X / Z / overflow).
List<String> sevenSegmentDigits(
  StageSignalSnapshot snapshot, {
  required int digitCount,
  required SevenSegmentRadix radix,
}) {
  final blank = List<String>.filled(digitCount, '-');
  if (!snapshot.hasValue) return blank;
  if (snapshot.hasX || snapshot.hasZ) {
    return List<String>.filled(digitCount, 'x');
  }
  final value = snapshot.intValue;
  if (value == null) return blank;

  final base = radix == SevenSegmentRadix.hexadecimal ? 16 : 10;
  final maxValue = BigInt.from(base).pow(digitCount) - BigInt.one;
  if (value > maxValue) return List<String>.filled(digitCount, 'x');

  final chars = value.toRadixString(base);
  final padded = chars.padLeft(digitCount, '0');
  return padded.split('');
}

/// Per-digit on/off state for the seven painted segments + decimal
/// point. Used by [SevenSegmentDigitPainter] to render either a
/// value-mode digit (decoded via [SegmentGlyph.fromChar]) or a
/// cathode-mode digit (constructed via [SegmentGlyph.fromCathodes]).
@immutable
class SegmentGlyph {
  const SegmentGlyph({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
    required this.g,
    this.dp = false,
    this.dpVisible = false,
    this.isError = false,
    this.isBlank = false,
  });

  /// Map a character from [sevenSegmentDigits] to its glyph.
  factory SegmentGlyph.fromChar(String ch) {
    if (ch == '-') return blank;
    if (ch == 'x') return error;
    final pattern = _patternForChar[ch] ?? 0;
    return SegmentGlyph(
      a: (pattern & 0x40) != 0,
      b: (pattern & 0x20) != 0,
      c: (pattern & 0x10) != 0,
      d: (pattern & 0x08) != 0,
      e: (pattern & 0x04) != 0,
      f: (pattern & 0x02) != 0,
      g: (pattern & 0x01) != 0,
    );
  }

  /// Construct a glyph from a cathode bus value. Bit assignments
  /// follow the most common convention (bit 0 = a, bit 6 = g).
  /// Pass [activeHigh] false if the user's hardware drives cathodes
  /// active-low (common-anode displays).
  ///
  /// [dpFromBus] is the decimal-point bit (bit 7); when null the DP
  /// state comes from a separately bound `dp` pin via [dpOverride].
  factory SegmentGlyph.fromCathodes(
    int bits, {
    bool activeHigh = true,
    bool? dpFromBus,
    bool? dpOverride,
    bool dpVisible = false,
  }) {
    bool segOn(int bit) {
      final raw = (bits >> bit) & 1 == 1;
      return activeHigh ? raw : !raw;
    }

    return SegmentGlyph(
      a: segOn(0),
      b: segOn(1),
      c: segOn(2),
      d: segOn(3),
      e: segOn(4),
      f: segOn(5),
      g: segOn(6),
      dp: dpOverride ?? dpFromBus ?? false,
      dpVisible: dpVisible,
    );
  }

  /// Blank glyph — all segments off, dim middle bar drawn by the
  /// painter to suggest "no signal".
  static const SegmentGlyph blank = SegmentGlyph(
    a: false,
    b: false,
    c: false,
    d: false,
    e: false,
    f: false,
    g: false,
    isBlank: true,
  );

  /// Error glyph — drawn as an X mark so the user immediately sees a
  /// bad value (X / Z / out-of-range).
  static const SegmentGlyph error = SegmentGlyph(
    a: false,
    b: false,
    c: false,
    d: false,
    e: false,
    f: false,
    g: false,
    isError: true,
  );

  final bool a;
  final bool b;
  final bool c;
  final bool d;
  final bool e;
  final bool f;
  final bool g;
  final bool dp;

  /// True when the renderer should draw the DP indicator at all.
  /// False suppresses any DP rendering (used in value mode without a
  /// bound `dp` pin).
  final bool dpVisible;
  final bool isError;
  final bool isBlank;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SegmentGlyph &&
          a == other.a &&
          b == other.b &&
          c == other.c &&
          d == other.d &&
          e == other.e &&
          f == other.f &&
          g == other.g &&
          dp == other.dp &&
          dpVisible == other.dpVisible &&
          isError == other.isError &&
          isBlank == other.isBlank;

  @override
  int get hashCode => Object.hash(
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    dp,
    dpVisible,
    isError,
    isBlank,
  );
}

/// Internal hex-digit pattern table. Bits are MSB-first per the
/// historical layout used by the painter (bit 6 = a, bit 0 = g).
const Map<String, int> _patternForChar = {
  '0': 0x7E,
  '1': 0x30,
  '2': 0x6D,
  '3': 0x79,
  '4': 0x33,
  '5': 0x5B,
  '6': 0x5F,
  '7': 0x70,
  '8': 0x7F,
  '9': 0x7B,
  'a': 0x77,
  'b': 0x1F,
  'c': 0x4E,
  'd': 0x3D,
  'e': 0x4F,
  'f': 0x47,
};

/// Definition for the seven-segment display primitive.
///
/// Two binding modes are supported. The user can wire either pin
/// (or both — cathode mode wins):
///
/// - **`value`** (4 bits, hex digit 0..15): the renderer decodes the
///   numeric value into the conventional segment pattern. Useful when
///   the user has a decoded digit value in their design.
/// - **`cathodes`** (≥ 7 bits): the renderer drives each segment
///   directly from the bus bits — bit 0 = a (top), bit 1 = b, …,
///   bit 6 = g (middle). This is hardware-faithful: it lets the user
///   bind their actual cathode bus from an FPGA design and watch the
///   physical segment state on the timeline.
/// - **`dp`** (1 bit, optional): drives the decimal-point indicator.
///   In cathode mode, can also come from bit 7 of the cathode bus
///   when the bound signal is ≥ 8 bits. Falls back to off otherwise.
///
/// Compound widgets (Basys 3, DE10-Lite) wire each digit slot to the
/// `value` pin so the existing 4-bit board model continues to work.
class SevenSegmentStageWidget extends StageWidget {
  const SevenSegmentStageWidget();

  static const String widgetId = 'seven_segment';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Seven-Segment Display';

  @override
  String? get displayNameKey => 'stageSevenSegmentDisplayName';

  @override
  String get description =>
      'Bind `cathodes` (≥ 7 bits) to drive segments directly, or `value` '
      '(4 bits) for a decoded hex digit. Optional `dp` pin for the '
      'decimal point.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  /// Both modes are exposed as **optional**: the user binds whichever
  /// matches their design. Cathode mode takes priority when both are
  /// bound. With nothing bound the digit shows the dim middle bar.
  @override
  List<SignalBinding> get requiredSignals => const [];

  @override
  List<SignalBinding> get optionalSignals => const [
    SignalBinding(
      name: 'cathodes',
      description: 'Cathode bus — bit 0=a, bit 1=b, … bit 6=g, bit 7=dp',
    ),
    SignalBinding(
      name: 'value',
      description: 'Decoded numeric value (0..15) for value-mode display',
      bitWidth: 4,
    ),
    SignalBinding(
      name: 'dp',
      description: 'Decimal-point indicator (1 = on)',
      bitWidth: 1,
    ),
  ];

  /// Tall narrow default that matches a single physical digit's
  /// proportions (≈ 0.55 width:height).
  @override
  (double, double) get defaultSize => (70, 130);

  /// Below ~ (40, 70) the segment painter loses readable digit
  /// geometry — segment thickness collapses and the digit blurs.
  @override
  (double, double) get minSize => (40, 70);
}

/// Renders a [SevenSegmentStageWidget] instance.
///
/// Layout: a [FittedBox] wrapping a fixed-size [SizedBox] so the
/// painted geometry stays predictable regardless of how the host tile
/// is resized. The inner Row distributes [digitCount] cells evenly
/// (cathode mode is always single-digit).
class SevenSegmentStageRenderer extends ConsumerWidget {
  const SevenSegmentStageRenderer({
    required this.instance,
    this.digitCount = 1,
    this.radix = SevenSegmentRadix.hexadecimal,
    this.cathodeActiveHigh = true,
    super.key,
  });

  final StageInstance instance;
  final int digitCount;
  final SevenSegmentRadix radix;

  /// Cathode polarity. Most discrete 7-seg displays + Digilent boards
  /// use active-high (1 = segment on). Common-anode designs invert.
  final bool cathodeActiveHigh;

  /// Per-digit pixel size used by the inner [SizedBox]. The outer
  /// [FittedBox] scales these to the slot size.
  static const double _digitWidth = 80;
  static const double _digitHeight = 144;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final clampedDigits = digitCount.clamp(1, 8);

    // Always watch all three providers (a null binding returns the
    // unbound snapshot synchronously, so the cost is trivial). This
    // keeps the watch list stable across rebuilds.
    final cathodesSnap = ref.watch(
      stageBoundSignalProvider(instance.signalBindings['cathodes']),
    );
    final valueSnap = ref.watch(
      stageBoundSignalProvider(instance.signalBindings['value']),
    );
    final dpSnap = ref.watch(
      stageBoundSignalProvider(instance.signalBindings['dp']),
    );

    final glyphs = _computeGlyphs(
      cathodes: cathodesSnap,
      value: valueSnap,
      dp: dpSnap,
      digitCount: clampedDigits,
    );

    return FittedBox(
      child: SizedBox(
        width: _digitWidth * clampedDigits,
        height: _digitHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Semantics(
              label: l10n.stageSevenSegmentSemanticLabel(
                _semanticString(glyphs),
              ),
              child: Row(
                children: [
                  for (final glyph in glyphs)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: SizedBox.expand(
                          child: CustomPaint(
                            painter: SevenSegmentDigitPainter(glyph),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<SegmentGlyph> _computeGlyphs({
    required StageSignalSnapshot cathodes,
    required StageSignalSnapshot value,
    required StageSignalSnapshot dp,
    required int digitCount,
  }) {
    // ── cathode mode (single digit) ────────────────────────────────
    if (cathodes.isBound) {
      if (!cathodes.hasValue) {
        return List<SegmentGlyph>.filled(1, SegmentGlyph.blank);
      }
      if (cathodes.hasX || cathodes.hasZ) {
        return const [SegmentGlyph.error];
      }
      final iv = cathodes.intValue;
      if (iv == null) return const [SegmentGlyph.blank];
      final bits = iv.toInt();
      // DP comes from the explicit `dp` pin if bound; otherwise from
      // bit 7 of the cathode bus when the bus is ≥ 8 bits.
      bool? dpOverride;
      if (dp.isBound && dp.hasValue && !dp.hasX && !dp.hasZ) {
        final dpBits = dp.cleanBits;
        dpOverride =
            dpBits.isNotEmpty &&
            dpBits[dpBits.length - 1] == (cathodeActiveHigh ? '1' : '0');
      }
      final hasDpInBus = cathodes.bitWidth >= 8;
      final dpFromBus = hasDpInBus
          ? ((bits >> 7) & 1 == 1) == cathodeActiveHigh
          : null;
      return [
        SegmentGlyph.fromCathodes(
          bits & 0x7F,
          activeHigh: cathodeActiveHigh,
          dpFromBus: dpFromBus,
          dpOverride: dpOverride,
          dpVisible: dp.isBound || hasDpInBus,
        ),
      ];
    }

    // ── value mode (multi-digit decoded) ───────────────────────────
    if (value.isBound) {
      final chars = sevenSegmentDigits(
        value,
        digitCount: digitCount,
        radix: radix,
      );
      bool? dpOverride;
      if (dp.isBound && dp.hasValue && !dp.hasX && !dp.hasZ) {
        final dpBits = dp.cleanBits;
        dpOverride = dpBits.isNotEmpty && dpBits[dpBits.length - 1] == '1';
      }
      return [
        for (var i = 0; i < chars.length; i++)
          () {
            final base = SegmentGlyph.fromChar(chars[i]);
            // Show DP only on the rightmost digit and only if bound.
            if (i == chars.length - 1 && dpOverride != null) {
              return SegmentGlyph(
                a: base.a,
                b: base.b,
                c: base.c,
                d: base.d,
                e: base.e,
                f: base.f,
                g: base.g,
                dp: dpOverride,
                dpVisible: true,
                isError: base.isError,
                isBlank: base.isBlank,
              );
            }
            return base;
          }(),
      ];
    }

    return List<SegmentGlyph>.filled(digitCount, SegmentGlyph.blank);
  }

  String _semanticString(List<SegmentGlyph> glyphs) => glyphs
      .map(
        (g) => g.isError
            ? 'X'
            : g.isBlank
            ? '-'
            : '*',
      )
      .join();
}

/// Custom painter that draws one seven-segment digit from a
/// [SegmentGlyph]. Public so widget tests can pump it directly.
class SevenSegmentDigitPainter extends CustomPainter {
  SevenSegmentDigitPainter(this.glyph);

  final SegmentGlyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const offColor = Color(0xFF301010);
    const onColor = Color(0xFFFF1744);
    const errorColor = Color(0xFFFFB300);

    final w = size.width;
    final h = size.height;
    // When the decimal point is visible we reserve a column on the
    // right of the cell for the DP dot so the dot doesn't overlap
    // the c segment (lower-right vertical). Without DP the digit
    // fills the full cell as before.
    final hasDp = glyph.dpVisible;
    final dpReservedFrac = hasDp ? 0.20 : 0.0;
    final digitWidth = w * (1 - dpReservedFrac);

    // Segment thickness scales with the digit's effective width so a
    // shrunk digit (DP shown) keeps proportional segments.
    final t = (digitWidth * 0.18).clamp(2.0, 8.0);
    final pad = t * 0.45;

    final ay = pad;
    final dy = h - pad;
    final gy = h / 2;
    final lx = pad;
    final rx = digitWidth - pad;

    void hseg(double y, {required bool on}) {
      final color = on ? onColor : offColor;
      final path = Path()
        ..moveTo(lx + t / 2, y - t / 2)
        ..lineTo(rx - t / 2, y - t / 2)
        ..lineTo(rx, y)
        ..lineTo(rx - t / 2, y + t / 2)
        ..lineTo(lx + t / 2, y + t / 2)
        ..lineTo(lx, y)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    void vseg(double x, double yTop, double yBot, {required bool on}) {
      final color = on ? onColor : offColor;
      final path = Path()
        ..moveTo(x - t / 2, yTop + t / 2)
        ..lineTo(x, yTop)
        ..lineTo(x + t / 2, yTop + t / 2)
        ..lineTo(x + t / 2, yBot - t / 2)
        ..lineTo(x, yBot)
        ..lineTo(x - t / 2, yBot - t / 2)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    hseg(ay, on: glyph.a);
    vseg(rx, ay, gy, on: glyph.b);
    vseg(rx, gy, dy, on: glyph.c);
    hseg(dy, on: glyph.d);
    vseg(lx, gy, dy, on: glyph.e);
    vseg(lx, ay, gy, on: glyph.f);
    hseg(gy, on: glyph.g);

    // Decimal-point dot — positioned in the reserved right-side
    // column, vertically aligned with the bottom segment so it reads
    // as a "lower-right dot" without ever overlapping the c segment.
    if (hasDp) {
      final dpColor = glyph.dp ? onColor : offColor;
      final dpRadius = t * 0.55;
      final dpCx = digitWidth + (w - digitWidth) / 2;
      final dpCy = dy;
      canvas.drawCircle(
        Offset(dpCx, dpCy),
        dpRadius,
        Paint()..color = dpColor,
      );
    }

    if (glyph.isError) {
      final paint = Paint()
        ..color = errorColor
        ..strokeWidth = t * 0.6
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(Offset(lx, ay), Offset(rx, dy), paint)
        ..drawLine(Offset(lx, dy), Offset(rx, ay), paint);
    } else if (glyph.isBlank) {
      // Dim middle bar for blank/unbound — still readable as "no signal".
      hseg(gy, on: true);
    }
  }

  @override
  bool shouldRepaint(covariant SevenSegmentDigitPainter old) =>
      old.glyph != glyph;
}
