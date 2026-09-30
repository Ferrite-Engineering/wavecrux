// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Analog-rendering fixture sweep.
//
// For every VCD in the analog corpus, this opens the trace through the REAL
// wellen FFI parser and snapshots, per signal, the numbers the analog renderer
// would plot — the output of `AnalogValueExtractors` over every recorded value
// change, read through the display format that signal is meant to carry.
//
//   REGENERATE=1 flutter test test/services/waveform/analog_fixture_golden_test.dart
//
// The VCDs themselves come from `dart run tool/generate_analog_fixtures.dart`.
//
// ── What this catches that a painter unit test does not ──────────────────────
//
// The unit tests pin `numericValue` against hand-written bit strings. This one
// pins the whole chain — real parser, real value strings (including the `b`
// prefixes and width padding wellen emits), real format selection — against a
// file that carries analog and digital signals *at the same time*. Two classes
// of regression only show up here:
//
//  * a change that makes every lane analog, or none, because the corpus has
//    both and the golden records which is which;
//  * a change to how the parser hands back x/z runs, which must stay NaN gaps
//    rather than becoming zeros in the middle of a curve.
//
// The replay needs the native wellen library: it skips locally when the
// library is not built and fails in CI, which builds it first.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/value_format/analog_value_extractor.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

/// How each fixture signal is meant to be read.
///
/// `analog: true` marks the signals a user would turn "Render as analog" on
/// for; the rest are here precisely so the golden proves they were *not*
/// silently converted. Real-valued signals carry `analog: true` with a null
/// format — they were always analog and go through the untouched real path.
const _corpus = <String, Map<String, _SignalSpec>>{
  'mixed_analog_digital': {
    'top.clk': _SignalSpec(DisplayFormat.binary, analog: false),
    'top.rst_n': _SignalSpec(DisplayFormat.binary, analog: false),
    'top.vref': _SignalSpec(null, analog: true),
    'top.dsp.sample_q': _SignalSpec(
      DisplayFormat.fixedPointQ,
      analog: true,
      config: {'m': 4, 'n': 12, 'signed': true},
    ),
    'top.dsp.gain_f32': _SignalSpec(DisplayFormat.ieee754Single, analog: true),
    'top.dsp.err_signed': _SignalSpec(
      DisplayFormat.signedDecimal,
      analog: true,
    ),
    'top.dsp.count_u': _SignalSpec(DisplayFormat.hexadecimal, analog: false),
    'top.dsp.gray_ctr': _SignalSpec(DisplayFormat.grayCode, analog: false),
    'top.dsp.bus_xz': _SignalSpec(DisplayFormat.unsignedDecimal, analog: true),
  },
  'analog_edge_cases': {
    'edge.constant_bus': _SignalSpec(
      DisplayFormat.unsignedDecimal,
      analog: true,
    ),
    'edge.single_change': _SignalSpec(
      DisplayFormat.unsignedDecimal,
      analog: true,
    ),
    'edge.full_swing': _SignalSpec(DisplayFormat.signedDecimal, analog: true),
    'edge.always_x': _SignalSpec(DisplayFormat.unsignedDecimal, analog: true),
    'edge.lone_real': _SignalSpec(null, analog: true),
  },
};

class _SignalSpec {
  const _SignalSpec(this.format, {required this.analog, this.config});
  final DisplayFormat? format;
  final bool analog;
  final Map<String, Object?>? config;
}

void main() {
  final regenerate = Platform.environment['REGENERATE'] == '1';

  group('Analog fixture sweep — plotted values from real-parser VCDs', () {
    test('corpus files exist', () {
      for (final name in _corpus.keys) {
        expect(
          File('test/fixtures/analog/$name.vcd').existsSync(),
          isTrue,
          reason: 'run `dart run tool/generate_analog_fixtures.dart`',
        );
        expect(
          File('verification/fixtures/analog/$name.vcd').existsSync(),
          isTrue,
          reason: 'the generator mirrors into verification/ too',
        );
      }
    });

    if (!requireWellenFfiLibrary('analog golden replay')) return;

    for (final entry in _corpus.entries) {
      final name = entry.key;
      final specs = entry.value;

      test(name, () async {
        final provider = WellenProvider();
        await provider.openFile('test/fixtures/analog/$name.vcd');
        try {
          final vars = {
            for (final v in provider.findVariables(const SignalFilter()))
              v.fullPath: v,
          };

          expect(
            vars.keys.toSet(),
            specs.keys.toSet(),
            reason:
                '$name: the fixture and this test disagree about which '
                'signals exist — regenerate the fixture or update _corpus',
          );

          final actual = <String, Object?>{};
          for (final path in specs.keys.toList()..sort()) {
            final spec = specs[path]!;
            final v = vars[path]!;
            await provider.loadSignal(v.signalRef);

            final extract = spec.format == null
                ? AnalogValueExtractors.real
                : AnalogValueExtractors.forDigitalLane(
                    bitWidth: v.bitWidth ?? 0,
                    format: spec.format!,
                    config: spec.config,
                  );

            final changes = provider.changesInRange(
              v.signalRef,
              provider.startTime,
              provider.endTime + 1,
            );
            final plotted = <Object?>[];
            for (final c in changes) {
              final d = extract(c.value);
              // NaN does not survive a JSON round-trip; the golden records the
              // gaps explicitly so "became a gap" and "became zero" can never
              // compare equal.
              plotted.add(d.isNaN ? null : _round(d));
            }

            actual[path] = {
              'analog': spec.analog,
              'format': spec.format?.name,
              'bitWidth': v.bitWidth,
              'changeCount': changes.length,
              'gapCount': plotted.where((e) => e == null).length,
              'min': _minOf(plotted),
              'max': _maxOf(plotted),
              'plotted': plotted,
            };
          }

          final golden = File('test/fixtures/analog/$name.expected.json');
          final mirror = File(
            'verification/fixtures/analog/$name.expected.json',
          );

          if (regenerate) {
            final json =
                '${const JsonEncoder.withIndent('  ').convert(actual)}\n';
            for (final f in [golden, mirror]) {
              f.writeAsStringSync(json);
              // REGENERATE is a developer escape hatch — surface the
              // overwritten path so the operator can review it.
              // ignore: avoid_print
              print('REGENERATE: wrote ${p.relative(f.path)}');
            }
            return;
          }

          expect(
            golden.existsSync(),
            isTrue,
            reason:
                'missing ${p.basename(golden.path)} — '
                'run with REGENERATE=1 to (re)create it',
          );
          expect(
            jsonDecode(jsonEncode(actual)),
            jsonDecode(golden.readAsStringSync()),
            reason:
                '$name: plotted values differ from the committed golden '
                '(run REGENERATE=1 if this change is intended)',
          );
        } finally {
          provider.close();
        }
      });
    }
  });

  group('Analog fixture sweep — the properties the corpus exists to hold', () {
    if (!requireWellenFfiLibrary('analog corpus properties')) return;

    test('the mixed fixture really is mixed', () {
      final specs = _corpus['mixed_analog_digital']!;
      expect(
        specs.values.where((s) => s.analog).length,
        greaterThanOrEqualTo(3),
        reason: 'a corpus with no analog signals proves nothing',
      );
      expect(
        specs.values.where((s) => !s.analog).length,
        greaterThanOrEqualTo(3),
        reason:
            'without digital signals alongside, a change that made every '
            'lane analog would pass',
      );
      expect(
        specs.values.any((s) => s.format == null),
        isTrue,
        reason: 'the native real path must be represented too',
      );
    });

    test('x and z runs are gaps, and the curve resumes after them', () async {
      final provider = WellenProvider();
      await provider.openFile(
        'test/fixtures/analog/mixed_analog_digital.vcd',
      );
      try {
        final v = provider
            .findVariables(const SignalFilter())
            .firstWhere((x) => x.fullPath == 'top.dsp.bus_xz');
        await provider.loadSignal(v.signalRef);
        final extract = AnalogValueExtractors.forDigitalLane(
          bitWidth: v.bitWidth ?? 0,
          format: DisplayFormat.unsignedDecimal,
        );
        final values = [
          for (final c in provider.changesInRange(
            v.signalRef,
            provider.startTime,
            provider.endTime + 1,
          ))
            extract(c.value),
        ];

        expect(values.any((d) => d.isNaN), isTrue, reason: 'no gap found');
        expect(
          values.any((d) => !d.isNaN),
          isTrue,
          reason: 'the whole trace became a gap',
        );
        // The regression that matters: an unknown run rendered as 0 would sit
        // on the axis and look like real data. The fixture never legitimately
        // holds 0 during a gap window, so a 0 adjacent to the gaps is the tell.
        final firstGap = values.indexWhere((d) => d.isNaN);
        expect(values[firstGap - 1].isNaN, isFalse);
        expect(values[firstGap - 1], isNot(0));
      } finally {
        provider.close();
      }
    });
  });
}

double _round(double d) => double.parse(d.toStringAsPrecision(12));

Object? _minOf(List<Object?> xs) {
  final ns = xs.whereType<num>();
  return ns.isEmpty ? null : ns.reduce((a, b) => a < b ? a : b);
}

Object? _maxOf(List<Object?> xs) {
  final ns = xs.whereType<num>();
  return ns.isEmpty ? null : ns.reduce((a, b) => a > b ? a : b);
}
