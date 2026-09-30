// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/riscv/riscv_abi_register_name.dart';

void main() {
  group('riscvAbiRegisterName', () {
    test('names the whole integer file', () {
      expect(riscvAbiRegisterName(0), 'zero');
      expect(riscvAbiRegisterName(1), 'ra');
      expect(riscvAbiRegisterName(2), 'sp');
      expect(riscvAbiRegisterName(5), 't0');
      expect(riscvAbiRegisterName(8), 's0');
      expect(riscvAbiRegisterName(10), 'a0');
      expect(riscvAbiRegisterName(17), 'a7');
      expect(riscvAbiRegisterName(31), 't6');
    });

    test('covers exactly 32 registers', () {
      expect(kRiscvAbiRegisterNames, hasLength(32));
      expect(kRiscvAbiRegisterNames.toSet(), hasLength(32));
      for (final name in kRiscvAbiRegisterNames) {
        expect(name, isNotEmpty);
      }
    });

    test('is total — out-of-range indices fall back to R<index>', () {
      expect(riscvAbiRegisterName(32), 'R32');
      expect(riscvAbiRegisterName(63), 'R63');
      expect(riscvAbiRegisterName(-1), 'R-1');
    });

    // The Pro Register File widget's `RegisterNamingService` delegates its
    // `riscvAbi` scheme here. That delegation is only behaviour-preserving if
    // the fallback shape matches what it used to render itself, so the shape
    // is asserted rather than left to a comment.
    test('fallback shape matches the Pro naming service contract', () {
      for (var i = 32; i < 64; i++) {
        expect(riscvAbiRegisterName(i), 'R$i');
      }
    });
  });

  group('riscvNumericRegisterName', () {
    test('uses the RISC-V x-spelling, not the generic R-spelling', () {
      expect(riscvNumericRegisterName(0), 'x0');
      expect(riscvNumericRegisterName(10), 'x10');
      expect(riscvNumericRegisterName(31), 'x31');
    });

    test('negative indices fall back to R<index>', () {
      expect(riscvNumericRegisterName(-4), 'R-4');
    });
  });

  group('riscvRegisterNameWithIndex', () {
    test('shows both spellings', () {
      expect(riscvRegisterNameWithIndex(10), 'a0 (x10)');
      expect(riscvRegisterNameWithIndex(0), 'zero (x0)');
    });

    test('negative indices degrade to the numeric fallback', () {
      expect(riscvRegisterNameWithIndex(-1), 'R-1');
    });
  });
}
