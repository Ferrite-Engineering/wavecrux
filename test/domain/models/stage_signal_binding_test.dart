// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';

void main() {
  group('StageSignalBinding', () {
    test('default bitIndex is null (whole-signal binding)', () {
      const b = StageSignalBinding(signalRef: 'top.clk');
      expect(b.bitIndex, isNull);
    });

    test('non-null bitIndex preserves the bit index', () {
      const b = StageSignalBinding(signalRef: 'top.leds[15:0]', bitIndex: 3);
      expect(b.bitIndex, 3);
    });

    test('equality compares both fields', () {
      const a = StageSignalBinding(signalRef: 'top.x');
      const b = StageSignalBinding(signalRef: 'top.x');
      const c = StageSignalBinding(signalRef: 'top.y');
      const d = StageSignalBinding(signalRef: 'top.x', bitIndex: 0);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('hashCode matches equality contract', () {
      const a = StageSignalBinding(signalRef: 'top.x', bitIndex: 5);
      const b = StageSignalBinding(signalRef: 'top.x', bitIndex: 5);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith updates fields', () {
      const a = StageSignalBinding(signalRef: 'top.x');
      expect(
        a.copyWith(signalRef: 'top.y'),
        const StageSignalBinding(signalRef: 'top.y'),
      );
      expect(
        a.copyWith(bitIndex: 7),
        const StageSignalBinding(signalRef: 'top.x', bitIndex: 7),
      );
    });

    test('copyWith(clearBitIndex: true) drops the bit index', () {
      const a = StageSignalBinding(signalRef: 'top.x', bitIndex: 7);
      expect(
        a.copyWith(clearBitIndex: true),
        const StageSignalBinding(signalRef: 'top.x'),
      );
    });

    test('toString formats single-bit binding distinctly', () {
      expect(
        const StageSignalBinding(signalRef: 'top.x').toString(),
        'StageSignalBinding(top.x)',
      );
      expect(
        const StageSignalBinding(signalRef: 'top.x', bitIndex: 3).toString(),
        'StageSignalBinding(top.x[3])',
      );
    });

    group('multi-bit slice', () {
      test('non-null bitWidth preserves the slice width', () {
        const b = StageSignalBinding(
          signalRef: 'top.adc_ch',
          bitIndex: 12,
          bitWidth: 12,
        );
        expect(b.bitIndex, 12);
        expect(b.bitWidth, 12);
      });

      test('equality includes bitWidth', () {
        const a = StageSignalBinding(
          signalRef: 'top.adc_ch',
          bitIndex: 0,
          bitWidth: 12,
        );
        const b = StageSignalBinding(
          signalRef: 'top.adc_ch',
          bitIndex: 0,
          bitWidth: 12,
        );
        const c = StageSignalBinding(
          signalRef: 'top.adc_ch',
          bitIndex: 0,
          bitWidth: 8,
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('copyWith updates bitWidth and clearBitWidth drops it', () {
        const base = StageSignalBinding(
          signalRef: 'top.adc_ch',
          bitIndex: 0,
          bitWidth: 12,
        );
        expect(
          base.copyWith(bitWidth: 24),
          const StageSignalBinding(
            signalRef: 'top.adc_ch',
            bitIndex: 0,
            bitWidth: 24,
          ),
        );
        expect(
          base.copyWith(clearBitWidth: true),
          const StageSignalBinding(signalRef: 'top.adc_ch', bitIndex: 0),
        );
      });

      test('toString renders the slice in Verilog [msb:lsb] notation when '
          'bitWidth > 1', () {
        // adc_ch1 ← bits 23..12 of the packed 96-bit ADC bus.
        const slice = StageSignalBinding(
          signalRef: 'top.adc_ch',
          bitIndex: 12,
          bitWidth: 12,
        );
        expect(slice.toString(), 'StageSignalBinding(top.adc_ch[23:12])');
      });

      test('bitWidth: 1 still renders as a single-bit binding', () {
        const single = StageSignalBinding(
          signalRef: 'top.x',
          bitIndex: 4,
          bitWidth: 1,
        );
        expect(single.toString(), 'StageSignalBinding(top.x[4])');
      });
    });
  });
}
