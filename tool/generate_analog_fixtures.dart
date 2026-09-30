// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the analog-rendering fixture corpus.
//
// Output (mirrored to both trees, per the fixture convention):
//   test/fixtures/analog/<name>.vcd
//   verification/fixtures/analog/<name>.vcd
//
// Usage:
//   dart run tool/generate_analog_fixtures.dart
//
// PURE DART (no FFI): emits deterministic `.vcd` text only. The paired
// `.expected.json` parse goldens are produced by the golden test against the
// real parser:
//
//   REGENERATE=1 flutter test test/services/waveform/analog_fixture_golden_test.dart
//
// ── Why this corpus exists ───────────────────────────────────────────────────
//
// WaveCrux could always draw a `real` signal as a curve. What it could not do
// until 2026-08-06 is draw a *digital bus* as a curve — the GTKWave "Data
// Format → Analog" behaviour that a DSP or ML engineer hits in their first
// session, because a Q4.12 or bf16 datapath is unreadable as hex.
//
// The interesting cases are all about the SAME file carrying both kinds at
// once, so `mixed_analog_digital.vcd` deliberately puts real signals, buses
// meant to be plotted, and buses meant to stay digital on one timeline with
// one clock. A fixture with only analog signals would not catch a regression
// that turned every lane analog, and one with only digital signals would not
// catch the reverse.
//
// Every value here is computed, not typed, so the waveform is reproducible and
// the goldens are stable.
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

const _testRoot = 'test/fixtures/analog';
const _verificationRoot = 'verification/fixtures/analog';

/// Simulation spans 0–2000 ns in 10 ns steps: 200 samples, enough for a curve
/// to read as a curve at any sane zoom without bloating the fixture.
const int _stepNs = 10;
const int _steps = 200;

void main() {
  final fixtures = <String, String>{
    'mixed_analog_digital.vcd': _renderMixed(),
    'analog_edge_cases.vcd': _renderEdgeCases(),
  };

  for (final entry in fixtures.entries) {
    for (final root in const [_testRoot, _verificationRoot]) {
      Directory(root).createSync(recursive: true);
      File('$root/${entry.key}').writeAsStringSync(entry.value);
    }
  }

  print('Generated analog fixtures:');
  for (final name in fixtures.keys) {
    print('  $_testRoot/$name');
    print('  $_verificationRoot/$name');
  }
  print(
    '\nNow (re)generate the goldens against the real parser:\n'
    '  REGENERATE=1 flutter test '
    'test/services/waveform/analog_fixture_golden_test.dart',
  );
}

// ── mixed_analog_digital.vcd ─────────────────────────────────────────────────

/// The primary fixture: analog and digital on one timeline.
///
/// | Signal | Width | Meant to be | Exercises |
/// |---|---|---|---|
/// | `top.clk` | 1 | digital | a scalar lane must stay a scalar lane |
/// | `top.rst_n` | 1 | digital | ditto, with a single early edge |
/// | `top.vref` | real | analog (native) | the pre-existing real path, unchanged |
/// | `top.dsp.sample_q` | 16 | **analog** | Q4.12 signed — the migration-blocker case |
/// | `top.dsp.gain_f32` | 32 | **analog** | IEEE-754 single bit-cast |
/// | `top.dsp.err_signed` | 12 | **analog** | two's complement crossing zero |
/// | `top.dsp.count_u` | 8 | digital | an unsigned counter that should stay hex |
/// | `top.dsp.gray_ctr` | 4 | digital | Gray code — decodes to a ramp if plotted |
/// | `top.dsp.bus_xz` | 8 | **analog** | x then z runs must become gaps, not zeros |
String _renderMixed() {
  final b = StringBuffer()
    ..writeln(r'$date 2026-08-06 $end')
    ..writeln(r'$version WaveCrux tool/generate_analog_fixtures.dart $end')
    ..writeln(r'$timescale 1 ns $end')
    ..writeln(r'$scope module top $end')
    ..writeln(r'$var wire 1 ! clk $end')
    ..writeln(r'$var wire 1 " rst_n $end')
    ..writeln(r'$var real 1 # vref $end')
    ..writeln(r'$scope module dsp $end')
    ..writeln(r'$var wire 16 $ sample_q $end')
    ..writeln(r'$var wire 32 % gain_f32 $end')
    ..writeln(r'$var wire 12 & err_signed $end')
    ..writeln(
      r'$var wire 8 '
      "'"
      r' count_u $end',
    )
    ..writeln(r'$var wire 4 ( gray_ctr $end')
    ..writeln(r'$var wire 8 ) bus_xz $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end');

  // Initial state at t=0 via $dumpvars.
  b
    ..writeln(r'$dumpvars')
    ..writeln('0!')
    ..writeln('0"')
    ..writeln('r${_fmtReal(_vref(0))} #')
    ..writeln('b${_bits(_sampleQRaw(0), 16)} \$')
    ..writeln('b${_bits(_gainF32Raw(0), 32)} %')
    ..writeln('b${_bits(_errSignedRaw(0), 12)} &')
    ..writeln("b${_bits(0, 8)} '")
    ..writeln('b${_bits(_grayOf(0), 4)} (')
    ..writeln('b${_bits(0, 8)} )')
    ..writeln(r'$end');

  for (var i = 1; i <= _steps; i++) {
    final t = i * _stepNs;
    b.writeln('#$t');

    // Clock toggles every step; reset releases early.
    b.writeln('${i.isEven ? 0 : 1}!');
    if (i == 3) b.writeln('1"');

    // `real` — a slow cosine around 1.8 V, the native-analog control.
    b.writeln('r${_fmtReal(_vref(i))} #');

    // Q4.12 signed — a full-scale sine. Plotted it is a sine; as hex it is
    // noise, which is exactly the complaint this feature answers.
    b.writeln('b${_bits(_sampleQRaw(i), 16)} \$');

    // IEEE-754 single — a decaying envelope, so the curve has visible shape
    // rather than a constant.
    b.writeln('b${_bits(_gainF32Raw(i), 32)} %');

    // Signed 12-bit crossing zero, so the zero gridline gets exercised.
    b.writeln('b${_bits(_errSignedRaw(i), 12)} &');

    // Plain counters that should remain digital lanes.
    b.writeln("b${_bits(i % 256, 8)} '");
    b.writeln('b${_bits(_grayOf(i % 16), 4)} (');

    // x for one window, z for another, values elsewhere. The analog renderer
    // must produce gaps across both, never a plunge to zero.
    b.writeln('b${_busXz(i)} )');
  }

  return b.toString();
}

// ── analog_edge_cases.vcd ────────────────────────────────────────────────────

/// The degenerate inputs, kept out of the primary fixture so its curves stay
/// readable: a bus that never changes (flat trace, zero auto-range span), a
/// single-sample signal, a full-scale swing between the extremes of a signed
/// range, and a bus that is x for its entire life.
String _renderEdgeCases() {
  final b = StringBuffer()
    ..writeln(r'$date 2026-08-06 $end')
    ..writeln(r'$version WaveCrux tool/generate_analog_fixtures.dart $end')
    ..writeln(r'$timescale 1 ns $end')
    ..writeln(r'$scope module edge $end')
    ..writeln(r'$var wire 8 ! constant_bus $end')
    ..writeln(r'$var wire 8 " single_change $end')
    ..writeln(r'$var wire 16 # full_swing $end')
    ..writeln(r'$var wire 8 $ always_x $end')
    ..writeln(r'$var real 1 % lone_real $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end')
    ..writeln(r'$dumpvars')
    ..writeln('b${_bits(0x42, 8)} !')
    ..writeln('b${_bits(0, 8)} "')
    ..writeln('b${_bits(0x8000, 16)} #') // most negative in 16-bit two's comp
    ..writeln('bxxxxxxxx \$')
    ..writeln('r2.5 %')
    ..writeln(r'$end');

  // A single change well into the trace, then nothing.
  b
    ..writeln('#100')
    ..writeln('b${_bits(0xFF, 8)} "')
    ..writeln('b${_bits(0x7FFF, 16)} #') // most positive
    ..writeln('#200')
    ..writeln('b${_bits(0x8000, 16)} #');

  return b.toString();
}

// ── value generators ─────────────────────────────────────────────────────────

/// `real` control signal: 1.8 V ± 0.2 V, one full cosine over the trace.
double _vref(int i) => 1.8 + 0.2 * math.cos(2 * math.pi * i / _steps);

/// Q4.12 signed 16-bit: a full sine at ~3 cycles over the trace.
///
/// Q4.12 means 4 integer bits and 12 fractional, so the stored integer is
/// `value * 4096`. Amplitude 3.5 keeps it inside the ±8 range without
/// clipping, and makes the plotted curve unmistakably a sine.
int _sampleQRaw(int i) {
  final v = 3.5 * math.sin(2 * math.pi * 3 * i / _steps);
  return _toTwos((v * 4096).round(), 16);
}

/// IEEE-754 single: an exponentially decaying envelope from 1.0 to ~0.05.
int _gainF32Raw(int i) => _float32Bits(math.exp(-3.0 * i / _steps));

/// Signed 12-bit error term: a triangle wave crossing zero twice.
int _errSignedRaw(int i) {
  final phase = (i * 4) % _steps;
  final tri = phase < _steps / 2
      ? (phase / (_steps / 2)) * 2 - 1
      : 3 - (phase / (_steps / 2)) * 2;
  return _toTwos((tri * 2047).round(), 12);
}

/// Binary-reflected Gray code of [n].
int _grayOf(int n) => n ^ (n >> 1);

/// x for steps 60–79, z for steps 140–159, a walking value elsewhere.
String _busXz(int i) {
  if (i >= 60 && i < 80) return 'xxxxxxxx';
  if (i >= 140 && i < 160) return 'zzzzzzzz';
  return _bits((i * 7) % 256, 8);
}

// ── encoding helpers ─────────────────────────────────────────────────────────

/// Two's-complement encoding of [value] in [width] bits.
int _toTwos(int value, int width) {
  final mask = (1 << width) - 1;
  return value & mask;
}

/// [value] as a [width]-bit binary string, MSB first.
String _bits(int value, int width) =>
    value.toRadixString(2).padLeft(width, '0');

/// The IEEE-754 single-precision bit pattern of [v], as a 32-bit integer.
///
/// Hand-rolled rather than via `ByteData` so the tool stays a plain `dart run`
/// with no imports beyond `dart:math` — and so the fixture's numbers are
/// derived by arithmetic a reader can check.
int _float32Bits(double v) {
  if (v == 0.0) return 0;
  final sign = v.isNegative ? 1 : 0;
  var x = v.abs();
  var exp = 0;
  while (x >= 2.0) {
    x /= 2.0;
    exp++;
  }
  while (x < 1.0) {
    x *= 2.0;
    exp--;
  }
  final biased = exp + 127;
  final frac = ((x - 1.0) * 8388608).round(); // 2^23
  return (sign << 31) | ((biased & 0xFF) << 23) | (frac & 0x7FFFFF);
}

/// Formats a real for VCD: enough digits to round-trip, no exponent surprises.
String _fmtReal(double v) => v.toStringAsFixed(6);
