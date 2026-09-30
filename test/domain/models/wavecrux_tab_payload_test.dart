// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/wavecrux_tab_payload.dart';

void main() {
  group('WaveCruxTabPayload', () {
    test('default constructor produces null/false fields', () {
      const p = WaveCruxTabPayload();
      expect(p.filePath, isNull);
      expect(p.sessionFilePath, isNull);
      expect(p.sessionExportPath, isNull);
      expect(p.isDetached, isFalse);
    });

    test('positional construction round-trips fields', () {
      const p = WaveCruxTabPayload(
        filePath: '/tmp/a.vcd',
        sessionFilePath: '/tmp/opened.wavecrux',
        sessionExportPath: '/tmp/a.wavecrux',
        isDetached: true,
      );
      expect(p.filePath, '/tmp/a.vcd');
      expect(p.sessionFilePath, '/tmp/opened.wavecrux');
      expect(p.sessionExportPath, '/tmp/a.wavecrux');
      expect(p.isDetached, isTrue);
    });

    test('copyWith carries sessionFilePath and isDetached', () {
      const original = WaveCruxTabPayload(filePath: '/tmp/a.vcd');
      final updated = original.copyWith(
        sessionFilePath: '/tmp/s.wavecrux',
        isDetached: true,
      );
      expect(updated.filePath, '/tmp/a.vcd');
      expect(updated.sessionFilePath, '/tmp/s.wavecrux');
      expect(updated.isDetached, isTrue);
    });

    test('== distinguishes sessionFilePath and isDetached', () {
      const a = WaveCruxTabPayload(filePath: '/tmp/x.vcd');
      const b = WaveCruxTabPayload(
        filePath: '/tmp/x.vcd',
        sessionFilePath: '/tmp/s.wavecrux',
      );
      const c = WaveCruxTabPayload(filePath: '/tmp/x.vcd', isDetached: true);
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });

    test('copyWith preserves unset fields', () {
      const original = WaveCruxTabPayload(filePath: '/tmp/a.vcd');
      final updated = original.copyWith(sessionExportPath: '/tmp/a.wavecrux');
      expect(updated.filePath, '/tmp/a.vcd');
      expect(updated.sessionExportPath, '/tmp/a.wavecrux');
    });

    test('copyWith replaces supplied fields', () {
      const original = WaveCruxTabPayload(
        filePath: '/tmp/a.vcd',
        sessionExportPath: '/tmp/a.wavecrux',
      );
      final updated = original.copyWith(filePath: '/tmp/b.fst');
      expect(updated.filePath, '/tmp/b.fst');
      expect(updated.sessionExportPath, '/tmp/a.wavecrux');
    });

    test('== and hashCode are value-based', () {
      const a = WaveCruxTabPayload(filePath: '/tmp/x.vcd');
      const b = WaveCruxTabPayload(filePath: '/tmp/x.vcd');
      const c = WaveCruxTabPayload(filePath: '/tmp/y.vcd');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes both fields', () {
      const p = WaveCruxTabPayload(
        filePath: '/tmp/a.vcd',
        sessionExportPath: '/tmp/a.wavecrux',
      );
      final s = p.toString();
      expect(s, contains('/tmp/a.vcd'));
      expect(s, contains('/tmp/a.wavecrux'));
    });
  });
}
