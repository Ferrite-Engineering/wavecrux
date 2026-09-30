// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests for SignalIntegrityService.
//
// Uses real fixture files and small inline VCDs (written to temp files and
// loaded via WellenProvider) to verify each of the five integrity checks
// independently.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/diagnostics/signal_integrity_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

const _service = SignalIntegrityService();

Future<WellenProvider> _fromString(String vcd) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_integrity_');
  final file = File('${dir.path}/inline.vcd');
  await file.writeAsString(vcd);
  final provider = WellenProvider();
  await provider.openFile(file.path);
  addTearDown(() async {
    provider.close();
    try {
      await dir.delete(recursive: true);
    } on Object catch (_) {
      // Best-effort cleanup.
    }
  });
  return provider;
}

// ── fixture VCDs ──────────────────────────────────────────────────────────────

/// A single wire that starts 0 and never changes — should be constant.
const _constantVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! static_sig $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#100
''';

/// A wire whose every value is x or z — should be X/Z-only.
const _xzOnlyVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! xz_sig $end
$upscope $end
$enddefinitions $end
$dumpvars
x!
$end
#10
z!
#20
x!
#100
''';

/// A signal with two changes at the same timestamp — should register a glitch.
const _glitchVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! glitch_sig $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#50
1!
0!
#100
''';

/// A periodic 1-bit clock at 50 MHz (1 ns timescale, 20-tick period).
const _clockVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#10
1!
#20
0!
#30
1!
#40
0!
#50
1!
#60
0!
#70
1!
#80
0!
#90
1!
#100
0!
#110
1!
#120
0!
''';

/// A signal that is X at t=0, transitions to 1 once, and never changes again.
const _stuckAtResetVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! stuck_sig $end
$upscope $end
$enddefinitions $end
$dumpvars
x!
$end
#10
1!
#100
''';

/// A signal with a single X entry in dumpvars and no further changes.
/// Must be classified as X/Z-only, NOT constant.
const _singleEntryXzVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! undriven_sig $end
$upscope $end
$enddefinitions $end
$dumpvars
x!
$end
#100
''';

/// A regular signal with multiple transitions — none of the special checks
/// should fire.
const _normalVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! normal_sig $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
$end
#10
1!
#30
0!
#50
1!
#70
0!
#100
''';

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  if (!requireWellenFfiLibrary('signal integrity service')) return;

  // ── scalar_basics.vcd (real fixture) ────────────────────────────────────────

  group('SignalIntegrityService — scalar_basics.vcd', () {
    late WellenProvider provider;

    setUpAll(() async {
      provider = WellenProvider();
      await provider.openFile('test/fixtures/vcd/scalar_basics.vcd');
    });

    tearDownAll(() => provider.close());

    test('analyses all 3 signals', () async {
      final report = await _service.analyze(provider);
      expect(report.signalsAnalyzed, 3);
    });

    test('analysisTimeMs is non-negative', () async {
      final report = await _service.analyze(provider);
      expect(report.analysisTimeMs, greaterThanOrEqualTo(0));
    });

    test('detects clk as a clock signal', () async {
      final report = await _service.analyze(provider);
      expect(report.detectedClocks, isNotEmpty);
      final clockPaths = report.detectedClocks.map((c) => c.signalPath);
      expect(clockPaths, contains('top.clk'));
    });

    test('detected clock has a frequency string', () async {
      final report = await _service.analyze(provider);
      final clk = report.detectedClocks.firstWhere(
        (c) => c.signalPath == 'top.clk',
      );
      expect(clk.estimatedFrequency, isNotEmpty);
      expect(clk.estimatedFrequency, contains('MHz'));
    });

    test('clk duty cycle is near 50%', () async {
      final report = await _service.analyze(provider);
      final clk = report.detectedClocks.firstWhere(
        (c) => c.signalPath == 'top.clk',
      );
      expect(clk.dutyCyclePercent, closeTo(50.0, 1.0));
    });

    test('no glitch signals in clean fixture', () async {
      final report = await _service.analyze(provider);
      expect(report.glitchSignals, isEmpty);
    });
  });

  // ── constant signal ──────────────────────────────────────────────────────────

  group('SignalIntegrityService — constant signal', () {
    test('static_sig appears in constantSignalPaths', () async {
      final provider = await _fromString(_constantVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.constantSignalPaths, contains('top.static_sig'));
    });

    test('constant signal does not appear in xzOnlySignalPaths', () async {
      final provider = await _fromString(_constantVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.xzOnlySignalPaths, isNot(contains('top.static_sig')));
    });
  });

  // ── X/Z-only signal ──────────────────────────────────────────────────────────

  group('SignalIntegrityService — X/Z-only signal', () {
    test('xz_sig appears in xzOnlySignalPaths', () async {
      final provider = await _fromString(_xzOnlyVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.xzOnlySignalPaths, contains('top.xz_sig'));
    });

    test('xz_sig does not appear in constantSignalPaths', () async {
      final provider = await _fromString(_xzOnlyVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.constantSignalPaths, isNot(contains('top.xz_sig')));
    });
  });

  // ── single-entry X/Z signal (regression for constant misclassification) ──────

  group('SignalIntegrityService — single-entry X/Z signal', () {
    test(
      'undriven_sig (single x entry) appears in xzOnlySignalPaths',
      () async {
        final provider = await _fromString(_singleEntryXzVcd);
        addTearDown(provider.close);

        final report = await _service.analyze(provider);
        expect(report.xzOnlySignalPaths, contains('top.undriven_sig'));
      },
    );

    test(
      'undriven_sig (single x entry) does not appear in constantSignalPaths',
      () async {
        final provider = await _fromString(_singleEntryXzVcd);
        addTearDown(provider.close);

        final report = await _service.analyze(provider);
        expect(report.constantSignalPaths, isNot(contains('top.undriven_sig')));
      },
    );
  });

  // ── glitch detection ──────────────────────────────────────────────────────────

  group('SignalIntegrityService — glitch detection', () {
    test('glitch_sig appears in glitchSignals', () async {
      final provider = await _fromString(_glitchVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.glitchSignals.keys, contains('top.glitch_sig'));
    });

    test('glitch count is at least 1', () async {
      final provider = await _fromString(_glitchVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.glitchSignals['top.glitch_sig'], greaterThanOrEqualTo(1));
    });
  });

  // ── clock detection ──────────────────────────────────────────────────────────

  group('SignalIntegrityService — clock detection', () {
    test('clk is detected as a clock', () async {
      final provider = await _fromString(_clockVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      final clockPaths = report.detectedClocks.map((c) => c.signalPath);
      expect(clockPaths, contains('top.clk'));
    });

    test('detected clock period is 20 ticks', () async {
      final provider = await _fromString(_clockVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      final clk = report.detectedClocks.firstWhere(
        (c) => c.signalPath == 'top.clk',
      );
      expect(clk.periodTicks, 20);
    });

    test('detected clock duty cycle is ~50%', () async {
      final provider = await _fromString(_clockVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      final clk = report.detectedClocks.firstWhere(
        (c) => c.signalPath == 'top.clk',
      );
      expect(clk.dutyCyclePercent, closeTo(50.0, 1.0));
    });

    test('clock frequency string contains MHz', () async {
      final provider = await _fromString(_clockVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      final clk = report.detectedClocks.firstWhere(
        (c) => c.signalPath == 'top.clk',
      );
      // 1 ns timescale, 20-tick period → 50 MHz
      expect(clk.estimatedFrequency, contains('MHz'));
    });
  });

  // ── stuck-at-reset ────────────────────────────────────────────────────────────

  group('SignalIntegrityService — stuck at reset', () {
    test('stuck_sig appears in stuckAtResetPaths', () async {
      final provider = await _fromString(_stuckAtResetVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.stuckAtResetPaths, contains('top.stuck_sig'));
    });

    test('stuck_sig does not appear in constantSignalPaths', () async {
      final provider = await _fromString(_stuckAtResetVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.constantSignalPaths, isNot(contains('top.stuck_sig')));
    });
  });

  // ── normal signal ─────────────────────────────────────────────────────────────

  group('SignalIntegrityService — normal signal', () {
    test('normal_sig appears in none of the problem lists', () async {
      final provider = await _fromString(_normalVcd);
      addTearDown(provider.close);

      final report = await _service.analyze(provider);
      expect(report.constantSignalPaths, isNot(contains('top.normal_sig')));
      expect(report.xzOnlySignalPaths, isNot(contains('top.normal_sig')));
      expect(report.glitchSignals.keys, isNot(contains('top.normal_sig')));
      expect(report.stuckAtResetPaths, isNot(contains('top.normal_sig')));
    });
  });

  // ── progress callback ─────────────────────────────────────────────────────────

  group('SignalIntegrityService — progress callback', () {
    test('onProgress is called for each signal', () async {
      final provider = await _fromString(_constantVcd);
      addTearDown(provider.close);

      final calls = <(int, int)>[];
      await _service.analyze(
        provider,
        onProgress: (analyzed, total) => calls.add((analyzed, total)),
      );

      expect(calls, isNotEmpty);
      // Final call should have analyzed == total.
      expect(calls.last.$1, calls.last.$2);
    });

    test('onProgress total equals signalsAnalyzed', () async {
      final provider = await _fromString(_constantVcd);
      addTearDown(provider.close);

      late int reportedTotal;
      final report = await _service.analyze(
        provider,
        onProgress: (_, total) => reportedTotal = total,
      );

      expect(reportedTotal, report.signalsAnalyzed);
    });
  });
}
