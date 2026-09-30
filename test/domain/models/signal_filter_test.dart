// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';

// Helpers ────────────────────────────────────────────────────────────────────

Variable _wire(
  String name, {
  String scopePath = 'top',
  int? bitWidth = 1,
  VarType varType = VarType.wire,
}) => Variable(
  name: name,
  varType: varType,
  direction: VarDirection.unknown,
  signalRef: name,
  scopePath: scopePath,
  bitWidth: bitWidth,
);

void main() {
  group('SignalFilter', () {
    // ── matchesAll ────────────────────────────────────────────────────────────

    test('empty filter matchesAll is true', () {
      expect(const SignalFilter().matchesAll, isTrue);
    });
    test('filter with namePattern matchesAll is false', () {
      expect(const SignalFilter(namePattern: 'clk').matchesAll, isFalse);
    });
    test('filter with varTypes matchesAll is false', () {
      expect(const SignalFilter(varTypes: {VarType.wire}).matchesAll, isFalse);
    });
    test('filter with scopePath matchesAll is false', () {
      expect(const SignalFilter(scopePath: 'top').matchesAll, isFalse);
    });
    test('filter with minBitWidth matchesAll is false', () {
      expect(const SignalFilter(minBitWidth: 1).matchesAll, isFalse);
    });
    test('filter with maxBitWidth matchesAll is false', () {
      expect(const SignalFilter(maxBitWidth: 32).matchesAll, isFalse);
    });

    // ── name matching ─────────────────────────────────────────────────────────

    group('namePattern — substring', () {
      test('null matches any name', () {
        expect(const SignalFilter().matches(_wire('clk')), isTrue);
      });
      test('empty string matches any name', () {
        expect(
          const SignalFilter(namePattern: '').matches(_wire('clk')),
          isTrue,
        );
      });
      test('exact match', () {
        expect(
          const SignalFilter(namePattern: 'clk').matches(_wire('clk')),
          isTrue,
        );
      });
      test('substring match', () {
        expect(
          const SignalFilter(namePattern: 'lk').matches(_wire('clk')),
          isTrue,
        );
      });
      test('case-insensitive', () {
        expect(
          const SignalFilter(namePattern: 'CLK').matches(_wire('clk')),
          isTrue,
        );
      });
      test('no match', () {
        expect(
          const SignalFilter(namePattern: 'xyz').matches(_wire('clk')),
          isFalse,
        );
      });
    });

    group('namePattern — glob *', () {
      test('data_* matches data_out', () {
        expect(
          const SignalFilter(namePattern: 'data_*').matches(_wire('data_out')),
          isTrue,
        );
      });
      test('data_* matches data_ (empty suffix)', () {
        expect(
          const SignalFilter(namePattern: 'data_*').matches(_wire('data_')),
          isTrue,
        );
      });
      test('data_* does not match wr_data', () {
        expect(
          const SignalFilter(namePattern: 'data_*').matches(_wire('wr_data')),
          isFalse,
        );
      });
      test('* matches everything', () {
        expect(
          const SignalFilter(namePattern: '*').matches(_wire('anything')),
          isTrue,
        );
      });
      test('glob is case-insensitive', () {
        expect(
          const SignalFilter(namePattern: 'DATA_*').matches(_wire('data_out')),
          isTrue,
        );
      });
    });

    group('namePattern — glob ?', () {
      test('clk? matches clk0', () {
        expect(
          const SignalFilter(namePattern: 'clk?').matches(_wire('clk0')),
          isTrue,
        );
      });
      test('clk? does not match clk', () {
        expect(
          const SignalFilter(namePattern: 'clk?').matches(_wire('clk')),
          isFalse,
        );
      });
      test('clk? does not match clk00', () {
        expect(
          const SignalFilter(namePattern: 'clk?').matches(_wire('clk00')),
          isFalse,
        );
      });
      test('axi_?_* matches axi_r_valid', () {
        expect(
          const SignalFilter(
            namePattern: 'axi_?_*',
          ).matches(_wire('axi_r_valid')),
          isTrue,
        );
      });
    });

    // ── scopePath matching ────────────────────────────────────────────────────

    group('scopePath', () {
      test('null matches any scope', () {
        expect(
          const SignalFilter().matches(_wire('x', scopePath: 'top.cpu')),
          isTrue,
        );
      });
      test('exact path match', () {
        expect(
          const SignalFilter(
            scopePath: 'top.cpu',
          ).matches(_wire('x', scopePath: 'top.cpu')),
          isTrue,
        );
      });
      test('prefix match includes child scopes', () {
        expect(
          const SignalFilter(
            scopePath: 'top',
          ).matches(_wire('x', scopePath: 'top.cpu.alu')),
          isTrue,
        );
      });
      test('does not match sibling scope', () {
        expect(
          const SignalFilter(
            scopePath: 'top.cpu',
          ).matches(_wire('x', scopePath: 'top.mem')),
          isFalse,
        );
      });
      test('does not match partial name prefix (no dot boundary)', () {
        // 'top.c' must not match 'top.cpu'
        expect(
          const SignalFilter(
            scopePath: 'top.c',
          ).matches(_wire('x', scopePath: 'top.cpu')),
          isFalse,
        );
      });
    });

    // ── varTypes filtering ────────────────────────────────────────────────────

    group('varTypes', () {
      test('null allows all types', () {
        expect(
          const SignalFilter().matches(_wire('x', varType: VarType.reg)),
          isTrue,
        );
      });
      test('matches when type is in set', () {
        expect(
          const SignalFilter(
            varTypes: {VarType.wire, VarType.reg},
          ).matches(_wire('x')),
          isTrue,
        );
      });
      test('rejects when type not in set', () {
        expect(
          const SignalFilter(varTypes: {VarType.reg}).matches(_wire('x')),
          isFalse,
        );
      });
    });

    // ── bitWidth filtering ────────────────────────────────────────────────────

    group('bitWidth', () {
      test('null bounds match any width', () {
        expect(const SignalFilter().matches(_wire('x', bitWidth: 32)), isTrue);
      });
      test('minBitWidth inclusive lower bound', () {
        expect(
          const SignalFilter(minBitWidth: 8).matches(_wire('x', bitWidth: 8)),
          isTrue,
        );
      });
      test('minBitWidth rejects narrower signal', () {
        expect(
          const SignalFilter(minBitWidth: 8).matches(_wire('x', bitWidth: 4)),
          isFalse,
        );
      });
      test('maxBitWidth inclusive upper bound', () {
        expect(
          const SignalFilter(maxBitWidth: 8).matches(_wire('x', bitWidth: 8)),
          isTrue,
        );
      });
      test('maxBitWidth rejects wider signal', () {
        expect(
          const SignalFilter(maxBitWidth: 8).matches(_wire('x', bitWidth: 16)),
          isFalse,
        );
      });
      test('range [4, 16] accepts 8-bit signal', () {
        expect(
          const SignalFilter(
            minBitWidth: 4,
            maxBitWidth: 16,
          ).matches(_wire('x', bitWidth: 8)),
          isTrue,
        );
      });
      test('null bitWidth on variable fails when bounds set', () {
        expect(
          const SignalFilter(
            minBitWidth: 1,
          ).matches(_wire('x', bitWidth: null)),
          isFalse,
        );
      });
    });

    // ── combined criteria ─────────────────────────────────────────────────────

    test('all criteria ANDed together', () {
      const filter = SignalFilter(
        namePattern: 'data*',
        varTypes: {VarType.reg},
        scopePath: 'top',
        minBitWidth: 4,
        maxBitWidth: 32,
      );

      // passes all
      expect(
        filter.matches(_wire('data_out', bitWidth: 8, varType: VarType.reg)),
        isTrue,
      );

      // fails name
      expect(
        filter.matches(_wire('addr', bitWidth: 8, varType: VarType.reg)),
        isFalse,
      );

      // fails type
      expect(filter.matches(_wire('data_out', bitWidth: 8)), isFalse);

      // fails scope
      expect(
        filter.matches(
          _wire(
            'data_out',
            scopePath: 'mem',
            bitWidth: 8,
            varType: VarType.reg,
          ),
        ),
        isFalse,
      );

      // fails width
      expect(
        filter.matches(_wire('data_out', bitWidth: 2, varType: VarType.reg)),
        isFalse,
      );
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith(namePattern:) changes only namePattern', () {
      const f = SignalFilter(namePattern: 'clk', scopePath: 'top');
      final g = f.copyWith(namePattern: 'data');
      expect(g.namePattern, 'data');
      expect(g.scopePath, 'top');
    });
    test('copyWith(clearNamePattern: true) sets namePattern to null', () {
      const f = SignalFilter(namePattern: 'clk');
      expect(f.copyWith(clearNamePattern: true).namePattern, isNull);
    });
    test('copyWith(clearVarTypes: true) sets varTypes to null', () {
      const f = SignalFilter(varTypes: {VarType.wire});
      expect(f.copyWith(clearVarTypes: true).varTypes, isNull);
    });
    test('copyWith with no args returns equal object', () {
      const f = SignalFilter(
        namePattern: 'clk',
        varTypes: {VarType.wire},
        scopePath: 'top',
        minBitWidth: 1,
        maxBitWidth: 8,
      );
      expect(f.copyWith(), equals(f));
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const a = SignalFilter(
        namePattern: 'clk',
        varTypes: {VarType.wire, VarType.reg},
        scopePath: 'top',
        minBitWidth: 1,
        maxBitWidth: 32,
      );
      const b = SignalFilter(
        namePattern: 'clk',
        varTypes: {VarType.reg, VarType.wire}, // different insertion order
        scopePath: 'top',
        minBitWidth: 1,
        maxBitWidth: 32,
      );
      expect(a, equals(b));
    });
    test('varTypes set order does not affect equality', () {
      const a = SignalFilter(varTypes: {VarType.wire, VarType.reg});
      const b = SignalFilter(varTypes: {VarType.reg, VarType.wire});
      expect(a, equals(b));
    });
    test('not equal when namePattern differs', () {
      const a = SignalFilter(namePattern: 'clk');
      const b = SignalFilter(namePattern: 'data');
      expect(a, isNot(equals(b)));
    });
    test('not equal when one varTypes is null', () {
      const a = SignalFilter(varTypes: {VarType.wire});
      const b = SignalFilter();
      expect(a, isNot(equals(b)));
    });
    test('hashCode equal for equal objects', () {
      const a = SignalFilter(
        namePattern: 'clk',
        varTypes: {VarType.wire},
        scopePath: 'top',
      );
      const b = SignalFilter(
        namePattern: 'clk',
        varTypes: {VarType.wire},
        scopePath: 'top',
      );
      expect(a.hashCode, equals(b.hashCode));
    });
    test('hashCode equal regardless of Set insertion order', () {
      const a = SignalFilter(varTypes: {VarType.wire, VarType.reg});
      const b = SignalFilter(varTypes: {VarType.reg, VarType.wire});
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
