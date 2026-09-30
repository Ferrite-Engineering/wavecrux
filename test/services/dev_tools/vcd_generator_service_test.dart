// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/dev_tools/vcd_generator_service.dart';

void main() {
  final service = VcdGeneratorService();

  // ── Format validity ─────────────────────────────────────────────────────────

  group('VcdGeneratorService — output format', () {
    test('produces non-empty output', () {
      expect(service.generate(const VcdGeneratorConfig()), isNotEmpty);
    });

    test('contains all required VCD section keywords', () {
      final vcd = service.generate(const VcdGeneratorConfig());
      expect(vcd, contains(r'$timescale'));
      expect(vcd, contains(r'$scope'));
      expect(vcd, contains(r'$var'));
      expect(vcd, contains(r'$enddefinitions'));
      expect(vcd, contains(r'$dumpvars'));
    });

    test('has a top-level module scope', () {
      final vcd = service.generate(const VcdGeneratorConfig());
      expect(vcd, contains(r'$scope module top $end'));
    });

    test('enddefinitions comes before dumpvars', () {
      final vcd = service.generate(const VcdGeneratorConfig());
      final defsPos = vcd.indexOf(r'$enddefinitions');
      final dumpPos = vcd.indexOf(r'$dumpvars');
      expect(defsPos, lessThan(dumpPos));
    });

    test('timestamps are non-decreasing', () {
      final vcd = service.generate(
        const VcdGeneratorConfig(signalCount: 20, duration: 5000),
      );
      final times = RegExp(
        r'^#(\d+)',
        multiLine: true,
      ).allMatches(vcd).map((m) => int.parse(m.group(1)!)).toList();
      expect(times, isNotEmpty);
      for (var i = 1; i < times.length; i++) {
        expect(
          times[i],
          greaterThanOrEqualTo(times[i - 1]),
          reason:
              'timestamp at index $i (${times[i]}) < previous (${times[i - 1]})',
        );
      }
    });

    test('max timestamp does not exceed duration', () {
      const duration = 1000;
      final vcd = service.generate(
        const VcdGeneratorConfig(duration: duration),
      );
      final times = RegExp(
        r'^#(\d+)',
        multiLine: true,
      ).allMatches(vcd).map((m) => int.parse(m.group(1)!)).toList();
      expect(times.reduce(max), lessThanOrEqualTo(duration));
    });
  });

  // ── Determinism ─────────────────────────────────────────────────────────────

  group('VcdGeneratorService — determinism', () {
    test('same seed produces identical output', () {
      const cfg = VcdGeneratorConfig(seed: 99);
      expect(service.generate(cfg), equals(service.generate(cfg)));
    });

    test('different seeds produce different output', () {
      final a = service.generate(const VcdGeneratorConfig(seed: 1));
      final b = service.generate(const VcdGeneratorConfig(seed: 2));
      expect(a, isNot(equals(b)));
    });
  });

  // ── Configuration ────────────────────────────────────────────────────────────

  group('VcdGeneratorService — signal count', () {
    for (final count in [1, 5, 10, 50]) {
      test('signalCount=$count produces exactly $count \$var declarations', () {
        final vcd = service.generate(VcdGeneratorConfig(signalCount: count));
        expect(
          RegExp(r'\$var', multiLine: true).allMatches(vcd).length,
          equals(count),
        );
      });
    }

    test('first signal is always clk', () {
      final vcd = service.generate(const VcdGeneratorConfig());
      expect(vcd, contains('clk'));
    });
  });

  group('VcdGeneratorService — analog signals', () {
    test('includeAnalog=true adds at least one real-typed variable', () {
      // Use enough signals and a seed that will roll an analog signal.
      const cfg = VcdGeneratorConfig(
        signalCount: 30,
        includeAnalog: true,
        seed: 7,
      );
      final vcd = service.generate(cfg);
      expect(vcd, contains(r'$var real'));
    });

    test('includeAnalog=false produces no real-typed variables', () {
      const cfg = VcdGeneratorConfig(
        signalCount: 50,
        seed: 1,
      );
      final vcd = service.generate(cfg);
      expect(vcd, isNot(contains(r'$var real')));
    });
  });

  group('VcdGeneratorService — X/Z values', () {
    test('includeXz=true produces x or z in value changes', () {
      // Run multiple seeds until one produces x/z (the probability is ~15%).
      var found = false;
      for (var seed = 0; seed < 20 && !found; seed++) {
        final vcd = service.generate(
          VcdGeneratorConfig(signalCount: 50, includeXz: true, seed: seed),
        );
        // Check bus value lines (start with 'b') for x or z characters.
        final busLines = vcd
            .split('\n')
            .where((l) => l.startsWith('b'))
            .map((l) => l.substring(1, l.indexOf(' ')));
        if (busLines.any((b) => b.contains('x') || b.contains('z'))) {
          found = true;
        }
        // Check scalar lines for x or z values.
        final scalarX = RegExp('^x', multiLine: true).hasMatch(vcd);
        final scalarZ = RegExp('^z', multiLine: true).hasMatch(vcd);
        if (scalarX || scalarZ) found = true;
      }
      expect(
        found,
        isTrue,
        reason: 'expected at least one x/z value across 20 seeds',
      );
    });

    test('includeXz=false produces no x/z in bus values', () {
      const cfg = VcdGeneratorConfig(
        signalCount: 30,
        seed: 1,
      );
      final vcd = service.generate(cfg);
      final busValues = vcd
          .split('\n')
          .where((l) => l.startsWith('b'))
          .map((l) => l.substring(1, l.indexOf(' ')));
      for (final bits in busValues) {
        expect(bits, isNot(contains('x')));
        expect(bits, isNot(contains('z')));
      }
    });
  });

  // ── File output ──────────────────────────────────────────────────────────────

  group('VcdGeneratorService — generateToTempFile', () {
    test('writes a non-empty file and returns its path', () async {
      const cfg = VcdGeneratorConfig(signalCount: 3, duration: 500);
      final path = await service.generateToTempFile(cfg);
      addTearDown(() => File(path).deleteSync());

      final file = File(path);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
    });

    test('file content matches generate() output', () async {
      const cfg = VcdGeneratorConfig(signalCount: 5, duration: 1000, seed: 3);
      final path = await service.generateToTempFile(cfg);
      addTearDown(() => File(path).deleteSync());

      final fileContent = await File(path).readAsString();
      expect(fileContent, equals(service.generate(cfg)));
    });
  });
}
