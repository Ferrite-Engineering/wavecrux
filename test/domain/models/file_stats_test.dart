// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/file_stats.dart';

const _base = FileStats(
  filePath: '/sim/output.vcd',
  fileSizeBytes: 44040192,
  formatName: 'VCD',
  parseTimeMs: 1234.5,
  totalSignals: 3200,
  scalarCount: 2800,
  vectorCount: 380,
  realCount: 20,
  inputCount: 400,
  outputCount: 600,
  inoutCount: 50,
  unknownDirectionCount: 2150,
  totalTransitions: 14200000,
  hierarchyDepth: 8,
  scopeCount: 120,
  startTime: 0,
  endTime: 1000000,
  timescaleDisplay: '1 ns',
  simulationDate: '2026-04-23',
  simulatorVersion: 'Icarus Verilog 12.0',
);

void main() {
  group('FileStats', () {
    test('stores all required fields', () {
      expect(_base.filePath, '/sim/output.vcd');
      expect(_base.fileSizeBytes, 44040192);
      expect(_base.formatName, 'VCD');
      expect(_base.parseTimeMs, 1234.5);
      expect(_base.totalSignals, 3200);
      expect(_base.scalarCount, 2800);
      expect(_base.vectorCount, 380);
      expect(_base.realCount, 20);
      expect(_base.inputCount, 400);
      expect(_base.outputCount, 600);
      expect(_base.inoutCount, 50);
      expect(_base.unknownDirectionCount, 2150);
      expect(_base.totalTransitions, 14200000);
      expect(_base.hierarchyDepth, 8);
      expect(_base.scopeCount, 120);
      expect(_base.startTime, 0);
      expect(_base.endTime, 1000000);
      expect(_base.timescaleDisplay, '1 ns');
      expect(_base.simulationDate, '2026-04-23');
      expect(_base.simulatorVersion, 'Icarus Verilog 12.0');
    });

    test('nullable fields default to null when omitted', () {
      const s = FileStats(
        filePath: '/x.vcd',
        fileSizeBytes: 100,
        formatName: 'VCD',
        parseTimeMs: 10,
        totalSignals: 1,
        scalarCount: 1,
        vectorCount: 0,
        realCount: 0,
        inputCount: 0,
        outputCount: 1,
        inoutCount: 0,
        unknownDirectionCount: 0,
        totalTransitions: 5,
        hierarchyDepth: 1,
        scopeCount: 1,
        startTime: 0,
        endTime: 100,
      );
      expect(s.timescaleDisplay, isNull);
      expect(s.simulationDate, isNull);
      expect(s.simulatorVersion, isNull);
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith with no args returns equal object', () {
      expect(_base.copyWith(), equals(_base));
    });

    test('copyWith changes only the specified field', () {
      final updated = _base.copyWith(formatName: 'FST');
      expect(updated.formatName, 'FST');
      expect(updated.filePath, _base.filePath);
      expect(updated.totalSignals, _base.totalSignals);
    });

    test('copyWith can clear timescaleDisplay to null', () {
      final updated = _base.copyWith(timescaleDisplay: null);
      expect(updated.timescaleDisplay, isNull);
      expect(updated.formatName, _base.formatName);
    });

    test('copyWith can clear simulationDate to null', () {
      final updated = _base.copyWith(simulationDate: null);
      expect(updated.simulationDate, isNull);
    });

    test('copyWith can clear simulatorVersion to null', () {
      final updated = _base.copyWith(simulatorVersion: null);
      expect(updated.simulatorVersion, isNull);
    });

    test('copyWith can set timescaleDisplay from null to value', () {
      const s = FileStats(
        filePath: '/x.vcd',
        fileSizeBytes: 100,
        formatName: 'VCD',
        parseTimeMs: 1,
        totalSignals: 1,
        scalarCount: 1,
        vectorCount: 0,
        realCount: 0,
        inputCount: 0,
        outputCount: 1,
        inoutCount: 0,
        unknownDirectionCount: 0,
        totalTransitions: 1,
        hierarchyDepth: 1,
        scopeCount: 1,
        startTime: 0,
        endTime: 10,
      );
      final updated = s.copyWith(timescaleDisplay: '10 ps');
      expect(updated.timescaleDisplay, '10 ps');
    });

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal objects compare as equal', () {
      final a = _base.copyWith();
      final b = _base.copyWith();
      expect(a, equals(b));
    });

    test('differing filePath makes objects unequal', () {
      final a = _base.copyWith(filePath: '/a.vcd');
      final b = _base.copyWith(filePath: '/b.vcd');
      expect(a, isNot(equals(b)));
    });

    test('differing totalSignals makes objects unequal', () {
      final a = _base.copyWith(totalSignals: 100);
      final b = _base.copyWith(totalSignals: 200);
      expect(a, isNot(equals(b)));
    });

    test('differing optional field makes objects unequal', () {
      final a = _base.copyWith(timescaleDisplay: '1 ns');
      final b = _base.copyWith(timescaleDisplay: null);
      expect(a, isNot(equals(b)));
    });

    // ── hashCode ──────────────────────────────────────────────────────────────

    test('equal objects have equal hashCodes', () {
      final a = _base.copyWith();
      final b = _base.copyWith();
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains filePath and formatName', () {
      final s = _base.toString();
      expect(s, contains('/sim/output.vcd'));
      expect(s, contains('VCD'));
    });

    test('toString contains signal and transition counts', () {
      final s = _base.toString();
      expect(s, contains('3200'));
      expect(s, contains('14200000'));
    });
  });
}
