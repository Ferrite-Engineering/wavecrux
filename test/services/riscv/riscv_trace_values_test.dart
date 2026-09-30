// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/riscv/riscv_trace_values.dart';

void main() {
  group('riscvBitState', () {
    test('decodes scalar levels', () {
      expect(riscvBitState('0'), RiscvBit.low);
      expect(riscvBitState('1'), RiscvBit.high);
    });

    test('decodes a width-1 vector the same as a scalar', () {
      expect(riscvBitState('b0'), RiscvBit.low);
      expect(riscvBitState('b1'), RiscvBit.high);
    });

    test('decodes a wide vector on its least-significant bit', () {
      expect(riscvBitState('00000001'), RiscvBit.high);
      expect(riscvBitState('b11110000'), RiscvBit.low);
    });

    test('treats x / z / null / empty as unknown', () {
      expect(riscvBitState('x'), RiscvBit.unknown);
      expect(riscvBitState('z'), RiscvBit.unknown);
      expect(riscvBitState('b0000x'), RiscvBit.unknown);
      expect(riscvBitState(null), RiscvBit.unknown);
      expect(riscvBitState(''), RiscvBit.unknown);
      expect(riscvBitState('b'), RiscvBit.unknown);
    });
  });

  group('riscvDecodeUint', () {
    test('decodes bit-strings with and without the b prefix', () {
      expect(riscvDecodeUint('1010').value, 10);
      expect(riscvDecodeUint('b1010').value, 10);
      expect(riscvDecodeUint('00000000').value, 0);
    });

    test('flags unknown bits instead of guessing a value', () {
      final decoded = riscvDecodeUint('b1010x');
      expect(decoded.value, isNull);
      expect(decoded.hasUnknown, isTrue);
    });

    test('flags an unloaded / absent signal', () {
      expect(riscvDecodeUint(null).hasUnknown, isTrue);
      expect(riscvDecodeUint('').hasUnknown, isTrue);
    });

    test('rejects a real-valued signal rather than parsing it as bits', () {
      expect(riscvDecodeUint('3.14').value, isNull);
      expect(riscvDecodeUint('1e5').value, isNull);
    });

    test('masks values wider than Dart can hold rather than throwing', () {
      final wide = riscvDecodeUint('1' * 64);
      expect(wide.value, isNotNull);
      expect(wide.hasUnknown, isFalse);
      expect(wide.value, (BigInt.one << 62).toInt() - 1);
    });

    test('decodes a full 32-bit instruction word', () {
      // 0x00500293 — addi t0, zero, 5
      const bits = '00000000010100000000001010010011';
      expect(riscvDecodeUint(bits).value, 0x00500293);
    });
  });
}
