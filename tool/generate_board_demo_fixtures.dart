// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the compelling per-board "out-of-box demo" Stage fixtures for
// every Open Core FPGA board widget (Basys 3, Nexys A7, DE10-Lite,
// Arty A7).
//
// Re-run with:
//   dart run tool/generate_board_demo_fixtures.dart
//
// For each board this writes TWO VCDs so both auto-bind tiers are
// verifiable against the same animation:
//
//   <board>/<board>_demo_per_bit.vcd  — every LED / switch / numeric
//       button is an individual 1-bit signal named exactly like its
//       board slot (`led0`, `sw0`, `btn0`, `key0`, …). Exercises the
//       per-bit / exact-match auto-bind tier.
//   <board>/<board>_demo_vector.vcd   — LED / switch / numeric-button
//       families collapse to a single packed bus (`leds`, `sws`,
//       `btn`, `key`). Exercises the vector-fan-out auto-bind tier
//       (drop one bus, bind the whole row).
//
// Everything else (named buttons like `btnC`, per-digit seven-segment
// values) is IDENTICAL between the two files — only the family encoding
// differs, so a reviewer binding either file sees the same board come
// alive.
//
// The "demo program" is an exciting, comprehensive self-test — modelled
// on the spirit of the Digilent / Terasic out-of-box (OOB) designs —
// that keeps EVERY part of the board moving while the cursor scrubs:
//
//   - **LED light show** cycles through six lively patterns: cylon
//     knight-rider sweep → VU bar fill/drain → theater chase → switch
//     register (LEDs mirror the live slide switches — the signature OOB
//     behavior) → expand-from-center → sparkle. Every pattern lights
//     the full row, so no LED is ever dead.
//   - **Slide switches** evolve at distinct per-switch rates, as if a
//     user were flipping them; the switch-register LED phase mirrors
//     them so the two rows visibly track each other.
//   - **Seven-segment display** shows a real decoded readout rather than
//     a contrived cascade: Basys 3 runs a free-running hex counter, while
//     the Nexys A7 and DE10-Lite (both carry an on-board accelerometer)
//     show live accelerometer axes — X/Y across the 8 Nexys digits,
//     X/Y/Z across the 6 DE10-Lite digits. Each field is a coherent value
//     tilting through its full range, so every digit is exercised (no
//     pinned digits) while the number still reads as real sensor data —
//     high digits clean, low digits blurring like a real readout.
//   - **Push buttons** fire staggered press pulses.
//
// Timescale is 1 ns; the run is 0..48 µs so every signal has many
// transitions while scrubbing.
//
// Output lands under test/fixtures/stage/boards/<board>/ and is mirrored
// into verification/fixtures/stage/boards/<board>/.

import 'dart:io';

const int _simEndNs = 48000;
const int _stepNs = 40;

// Each LED pattern holds for this long before the show advances to the
// next; six patterns → 18 µs per full cycle, ~2.6 cycles across the run.
const int _modeDurNs = 3000;

void main() {
  for (final board in _boards) {
    for (final asVector in [false, true]) {
      final sigs = _buildSignals(board, asVector: asVector);
      final vcd = _emitVcd(board, sigs, asVector: asVector);
      final suffix = asVector ? 'vector' : 'per_bit';

      final relDir = 'test/fixtures/stage/boards/${board.id}';
      Directory(relDir).createSync(recursive: true);
      final outFile = File('$relDir/${board.id}_demo_$suffix.vcd')
        ..writeAsStringSync(vcd);

      final verDir = 'verification/fixtures/stage/boards/${board.id}';
      Directory(verDir).createSync(recursive: true);
      File('$verDir/${board.id}_demo_$suffix.vcd').writeAsStringSync(vcd);

      // Generator script — print the result so the operator sees what
      // was written. avoid_print is a runtime-app rule; not a tool rule.
      // ignore: avoid_print
      print(
        'Wrote ${outFile.path} '
        '(${outFile.lengthSync()} bytes, ${sigs.length} signals).',
      );
    }
  }
}

// ── board specifications ────────────────────────────────────────────────────

class _BoardSpec {
  const _BoardSpec({
    required this.id,
    required this.displayName,
    required this.ledPrefix,
    required this.ledCount,
    required this.switchCount,
    required this.buttonNames,
    this.buttonVectorName,
    this.digitPrefix,
    this.segFields = const [],
  });

  /// Directory / file stem (e.g. `basys3`).
  final String id;
  final String displayName;

  /// Slot-name prefix for the LED row (`led` or `ledr`).
  final String ledPrefix;
  final int ledCount;
  final int switchCount;

  /// Push-button slot names in board order.
  final List<String> buttonNames;

  /// When non-null the buttons form a numeric family (`btn0..n`,
  /// `key0..n`) and collapse to this packed bus in the vector file.
  final String? buttonVectorName;

  /// Seven-segment digit slot prefix (`digit` / `hex`) or null when the
  /// board has no seven-segment display.
  final String? digitPrefix;

  /// Seven-segment display fields, left-to-right (most-significant digit
  /// group first). Each field is a coherent decoded value (a counter or
  /// an accelerometer axis) spanning `field.digits` hex digits; the total
  /// digit count is the sum of the field widths.
  final List<_SegField> segFields;
}

/// One coherent multi-digit field on a seven-segment display — e.g. a
/// 16-bit counter (4 digits) or an 8-bit accelerometer axis (2 digits).
/// [value] returns the field value in `[0, 16^digits)`; the generator
/// slices it into per-digit nibbles.
class _SegField {
  const _SegField(this.digits, this.value);
  final int digits;
  final num Function(int t) value;
}

final List<_BoardSpec> _boards = [
  const _BoardSpec(
    id: 'basys3',
    displayName: 'Digilent Basys 3',
    ledPrefix: 'led',
    ledCount: 16,
    switchCount: 16,
    buttonNames: ['btnC', 'btnU', 'btnL', 'btnR', 'btnD'],
    digitPrefix: 'digit',
    // Free-running 16-bit hex counter across all 4 digits.
    segFields: [_SegField(4, _counter16)],
  ),
  _BoardSpec(
    id: 'nexys_a7',
    displayName: 'Digilent Nexys A7',
    ledPrefix: 'led',
    ledCount: 16,
    switchCount: 16,
    buttonNames: ['btnC', 'btnU', 'btnL', 'btnR', 'btnD'],
    digitPrefix: 'digit',
    // Accelerometer X (digits 7..4) and Y (digits 3..0), 16-bit each.
    segFields: [
      _SegField(
        4,
        (t) => _triangle(t, periodNs: 8000, phaseNs: 0, maxVal: 0xFFFF),
      ),
      _SegField(
        4,
        (t) => _triangle(t, periodNs: 6000, phaseNs: 1500, maxVal: 0xFFFF),
      ),
    ],
  ),
  _BoardSpec(
    id: 'de10_lite',
    displayName: 'Terasic DE10-Lite',
    ledPrefix: 'ledr',
    ledCount: 10,
    switchCount: 10,
    buttonNames: ['key0', 'key1'],
    buttonVectorName: 'key',
    digitPrefix: 'hex',
    // 3-axis accelerometer X/Y/Z (hex5..4 / 3..2 / 1..0), 8-bit each.
    segFields: [
      _SegField(
        2,
        (t) => _triangle(t, periodNs: 7000, phaseNs: 0, maxVal: 0xFF),
      ),
      _SegField(
        2,
        (t) => _triangle(t, periodNs: 9000, phaseNs: 1200, maxVal: 0xFF),
      ),
      _SegField(
        2,
        (t) => _triangle(t, periodNs: 5500, phaseNs: 600, maxVal: 0xFF),
      ),
    ],
  ),
  const _BoardSpec(
    id: 'arty_a7',
    displayName: 'Digilent Arty A7',
    ledPrefix: 'led',
    ledCount: 8,
    switchCount: 4,
    buttonNames: ['btn0', 'btn1', 'btn2', 'btn3'],
    buttonVectorName: 'btn',
  ),
];

// ── signal model ────────────────────────────────────────────────────────────

class _Sig {
  _Sig(this.name, this.bitWidth, this.gen);
  final String name;
  final int bitWidth;
  final num Function(int t) gen;
}

List<_Sig> _buildSignals(_BoardSpec b, {required bool asVector}) {
  final sigs = <_Sig>[];

  int swMask(int t) => _switchPattern(t, b.switchCount);
  int ledMask(int t) => _ledShow(t, b.ledCount, swMask(t));

  // ── LED family ──
  if (asVector) {
    sigs.add(_Sig('leds', b.ledCount, ledMask));
  } else {
    for (var i = 0; i < b.ledCount; i++) {
      sigs.add(_Sig('${b.ledPrefix}$i', 1, (t) => (ledMask(t) >> i) & 1));
    }
  }

  // ── switch family ──
  if (asVector) {
    sigs.add(_Sig('sws', b.switchCount, swMask));
  } else {
    for (var i = 0; i < b.switchCount; i++) {
      sigs.add(_Sig('sw$i', 1, (t) => (swMask(t) >> i) & 1));
    }
  }

  // ── push buttons ──
  // Numeric-family buttons (btn0.. / key0..) collapse to a packed bus
  // in the vector file. Named buttons (btnC, btnU, …) are not a family
  // and stay individual in both files.
  if (asVector && b.buttonVectorName != null) {
    sigs.add(
      _Sig(b.buttonVectorName!, b.buttonNames.length, (t) {
        var m = 0;
        for (var i = 0; i < b.buttonNames.length; i++) {
          if (_press(t, phaseNs: 2000 + i * 1500) == 1) m |= 1 << i;
        }
        return m;
      }),
    );
  } else {
    for (var i = 0; i < b.buttonNames.length; i++) {
      final phase = 2000 + i * 1500;
      sigs.add(_Sig(b.buttonNames[i], 1, (t) => _press(t, phaseNs: phase)));
    }
  }

  // ── seven-segment decoded readout ──
  // Per-digit 4-bit value signals (value mode → hex digit). The digits
  // render coherent decoded fields (a counter / accelerometer axes), not
  // a per-digit cascade: each field's value is sliced into nibbles, the
  // left-most field taking the highest digit indices. Identical in both
  // files — the seven-seg display is not a fan-out family.
  if (b.digitPrefix != null && b.segFields.isNotEmpty) {
    final digitGen = <int, num Function(int)>{};
    var hi = b.segFields.fold(0, (s, f) => s + f.digits) - 1;
    for (final field in b.segFields) {
      for (var k = 0; k < field.digits; k++) {
        final digitIndex = hi - k;
        final nibbleShift = (field.digits - 1 - k) * 4;
        digitGen[digitIndex] = (t) =>
            (field.value(t).toInt() >> nibbleShift) & 0xF;
      }
      hi -= field.digits;
    }
    for (var i = 0; i < digitGen.length; i++) {
      sigs.add(_Sig('${b.digitPrefix}$i', 4, digitGen[i]!));
    }
  }

  return sigs;
}

// ── animation generators ────────────────────────────────────────────────────

int _maskOf(int width) => width >= 31 ? 0x7FFFFFFF : (1 << width) - 1;

/// Slide-switch pattern: each switch toggles at a unique slow rate so the
/// whole row visibly evolves, as if a user were flipping switches.
int _switchPattern(int t, int n) {
  var m = 0;
  for (var i = 0; i < n; i++) {
    final period = 900 + i * 220;
    if ((t ~/ (period ~/ 2)).isOdd) m |= 1 << i;
  }
  return m;
}

/// The six-pattern LED light show. [swMaskVal] is the current switch
/// pattern, mirrored to the LEDs during the switch-register phase.
int _ledShow(int t, int n, int swMaskVal) {
  final mode = (t ~/ _modeDurNs) % 6;
  switch (mode) {
    case 0:
      return _cylon(t, n, 150);
    case 1:
      return _barVu(t, n, 130);
    case 2:
      return _theaterChase(t, n, 200);
    case 3:
      return swMaskVal & _maskOf(n); // OOB switch-register mirror
    case 4:
      return _expandCenter(t, n, 150);
    default:
      return _sparkle(t, n, 170);
  }
}

/// One-hot knight-rider bounce across [n] bits.
int _cylon(int t, int n, int periodNs) {
  final steps = 2 * n - 2;
  if (steps <= 0) return 1;
  final phase = (t ~/ periodNs) % steps;
  final pos = phase < n ? phase : steps - phase;
  return 1 << pos;
}

/// VU-meter bar that fills 0→n then drains n→0, lighting every LED.
int _barVu(int t, int n, int stepNs) {
  final steps = 2 * n;
  final phase = (t ~/ stepNs) % steps;
  final level = phase <= n ? phase : steps - phase; // 0..n..0
  return level >= n ? _maskOf(n) : (1 << level) - 1;
}

/// Theater-chase: every third LED lit, the pattern marching along the row.
int _theaterChase(int t, int n, int stepNs) {
  final phase = (t ~/ stepNs) % 3;
  var m = 0;
  for (var i = 0; i < n; i++) {
    if ((i + phase) % 3 == 0) m |= 1 << i;
  }
  return m;
}

/// Symmetric bars growing from the centre outward then collapsing back.
int _expandCenter(int t, int n, int stepNs) {
  final half = (n + 1) ~/ 2;
  final steps = 2 * half;
  final phase = (t ~/ stepNs) % steps;
  final level = phase <= half ? phase : steps - phase; // 0..half..0
  final mid = n ~/ 2;
  var m = 0;
  for (var k = 0; k < level; k++) {
    final hi = mid + k;
    final lo = mid - 1 - k;
    if (hi < n) m |= 1 << hi;
    if (lo >= 0) m |= 1 << lo;
  }
  return m;
}

/// Pseudo-random twinkle across the row.
int _sparkle(int t, int n, int stepNs) => _hash(t ~/ stepNs) & _maskOf(n);

/// Free-running 16-bit hex counter (Basys 3 seven-segment). Strided so it
/// spans the full 16-bit range across the trace, exercising all four
/// digits; the low digits blur like a real fast counter while the high
/// digits read cleanly.
int _counter16(int t) => ((t ~/ _stepNs) * 173) & 0xFFFF;

/// Triangle sweep in `[0, maxVal]` with the given period and phase — a
/// coherent value tilting up and down through its full range, used to
/// model an accelerometer axis on the seven-segment display.
int _triangle(
  int t, {
  required int periodNs,
  required int phaseNs,
  required int maxVal,
}) {
  final m = ((t + phaseNs) % periodNs + periodNs) % periodNs;
  final p = m / periodNs; // 0..1
  final tri = p < 0.5 ? p * 2 : (1 - p) * 2;
  return (tri * maxVal).round();
}

/// Short staggered press pulse. Returns 1 during a [widthNs] window once
/// per [periodNs], offset by [phaseNs].
int _press(
  int t, {
  required int phaseNs,
  int periodNs = 7000,
  int widthNs = 350,
}) {
  final local = ((t - phaseNs) % periodNs + periodNs) % periodNs;
  return local < widthNs ? 1 : 0;
}

/// Cheap deterministic hash for the sparkle pattern.
int _hash(int n) {
  var x = (n + 1) * 2654435761;
  x ^= x >> 13;
  x *= 0x9E3779B1;
  x ^= x >> 7;
  return x & 0x7FFFFFFF;
}

// ── VCD writer ──────────────────────────────────────────────────────────────

String _emitVcd(_BoardSpec b, List<_Sig> sigs, {required bool asVector}) {
  final out = StringBuffer();
  final ids = _IdCodeGenerator();
  final idOf = <_Sig, String>{for (final s in sigs) s: ids.next()};

  final kind = asVector ? 'vector buses' : 'individual per-bit signals';
  out
    ..writeln(r'$date')
    ..writeln('  2026-06-07T00:00:00.000Z')
    ..writeln(r'$end')
    ..writeln(r'$version')
    ..writeln('  WaveCrux board demo fixture generator')
    ..writeln(r'$end')
    ..writeln(r'$comment')
    ..writeln('  ${b.displayName} out-of-box demo — $kind.')
    ..writeln(
      '  LED show: cylon / VU bar / chase / switch-mirror / '
      'expand / sparkle.',
    )
    ..writeln(
      '  Seven-seg: decoded readout — counter / accelerometer '
      'axes (all digits live). Buttons: staggered presses.',
    )
    ..writeln(
      '  Re-generate with '
      '`dart run tool/generate_board_demo_fixtures.dart`.',
    )
    ..writeln(r'$end')
    ..writeln(r'$timescale 1 ns $end')
    ..writeln(r'$scope module top $end');
  for (final s in sigs) {
    out.writeln('\$var wire ${s.bitWidth} ${idOf[s]} ${s.name} \$end');
  }
  out
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end');

  String encode(_Sig s, num value) {
    if (s.bitWidth == 1) return '${(value as int) & 1}${idOf[s]}';
    final mask = s.bitWidth >= 31 ? 0x7FFFFFFF : (1 << s.bitWidth) - 1;
    final asInt = (value as int) & mask;
    return 'b${asInt.toRadixString(2)} ${idOf[s]}';
  }

  final last = <_Sig, String>{};
  out
    ..writeln('#0')
    ..writeln(r'$dumpvars');
  for (final s in sigs) {
    final enc = encode(s, s.gen(0));
    last[s] = enc;
    out.writeln(enc);
  }
  out.writeln(r'$end');

  for (var t = _stepNs; t <= _simEndNs; t += _stepNs) {
    final buf = StringBuffer();
    for (final s in sigs) {
      final enc = encode(s, s.gen(t));
      if (last[s] == enc) continue;
      last[s] = enc;
      buf.writeln(enc);
    }
    if (buf.isNotEmpty) {
      out
        ..writeln('#$t')
        ..write(buf);
    }
  }

  return out.toString();
}

/// Hands out unique VCD identifier codes from printable ASCII (33..126),
/// expanding to multi-character codes after the first 94 signals.
class _IdCodeGenerator {
  static const int _start = 33;
  static const int _end = 126;
  int _index = 0;

  String next() {
    const base = _end - _start + 1;
    var n = _index++;
    final chars = <int>[];
    do {
      chars.add(_start + n % base);
      n = n ~/ base;
    } while (n > 0);
    return String.fromCharCodes(chars);
  }
}
