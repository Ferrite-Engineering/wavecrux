// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/services/signal_query/pattern_search_service.dart';

class _MockDataSource extends Mock implements WaveformDataSource {}

void main() {
  late _MockDataSource source;
  late PatternSearchService service;

  const start = 0;
  const end = 1000;

  setUp(() {
    source = _MockDataSource();
    service = const PatternSearchService();
  });

  // ── evaluate: SignalCondition ────────────────────────────────────────────────

  group('evaluate — SignalCondition', () {
    test('eq matches when values are equal (decimal)', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.eq,
        value: '5',
      );
      expect(service.evaluate(cond, {'top.sig': '101'}), isTrue);
    });

    test('eq does not match when values differ', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.eq,
        value: '5',
      );
      expect(service.evaluate(cond, {'top.sig': '100'}), isFalse);
    });

    test('neq matches when values differ', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.neq,
        value: '5',
      );
      expect(service.evaluate(cond, {'top.sig': '110'}), isTrue);
    });

    test('neq does not match when values are equal', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.neq,
        value: '5',
      );
      expect(service.evaluate(cond, {'top.sig': '101'}), isFalse);
    });

    test('gt matches when signal > value', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.gt,
        value: '3',
      );
      expect(service.evaluate(cond, {'top.sig': '100'}), isTrue); // 4 > 3
    });

    test('gt does not match when signal == value', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.gt,
        value: '4',
      );
      expect(service.evaluate(cond, {'top.sig': '100'}), isFalse);
    });

    test('lt matches when signal < value', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.lt,
        value: '10',
      );
      expect(service.evaluate(cond, {'top.sig': '0101'}), isTrue); // 5 < 10
    });

    test('gte matches when signal >= value', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.gte,
        value: '4',
      );
      expect(service.evaluate(cond, {'top.sig': '100'}), isTrue); // 4 >= 4
      expect(service.evaluate(cond, {'top.sig': '101'}), isTrue); // 5 >= 4
      expect(service.evaluate(cond, {'top.sig': '011'}), isFalse); // 3 < 4
    });

    test('lte matches when signal <= value', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.lte,
        value: '4',
      );
      expect(service.evaluate(cond, {'top.sig': '100'}), isTrue); // 4 <= 4
      expect(service.evaluate(cond, {'top.sig': '011'}), isTrue); // 3 <= 4
      expect(service.evaluate(cond, {'top.sig': '101'}), isFalse); // 5 > 4
    });

    test('bitAnd: (signal & value) != 0 → true', () {
      const cond = SignalCondition(
        signalPath: 'top.flags',
        operator: ConditionOperator.bitAnd,
        value: '0x80', // bit 7
      );
      expect(
        service.evaluate(cond, {'top.flags': '10000001'}),
        isTrue,
      ); // bit 7 set
      expect(
        service.evaluate(cond, {'top.flags': '00000001'}),
        isFalse,
      ); // bit 7 clear
    });

    test('bitOr: (signal & value) == value → true', () {
      const cond = SignalCondition(
        signalPath: 'top.flags',
        operator: ConditionOperator.bitOr,
        value: '0x03', // bits 1:0
      );
      expect(
        service.evaluate(cond, {'top.flags': '00000011'}),
        isTrue,
      ); // both bits set
      expect(
        service.evaluate(cond, {'top.flags': '00000010'}),
        isFalse,
      ); // only one bit set
    });

    test('eq with 1-bit "1" signal value', () {
      const cond = SignalCondition(
        signalPath: 'top.en',
        operator: ConditionOperator.eq,
        value: '1',
      );
      expect(service.evaluate(cond, {'top.en': '1'}), isTrue);
      expect(service.evaluate(cond, {'top.en': '0'}), isFalse);
    });

    test('eq with b-prefixed VCD value', () {
      const cond = SignalCondition(
        signalPath: 'top.data',
        operator: ConditionOperator.eq,
        value: '0xFF',
      );
      expect(service.evaluate(cond, {'top.data': 'b11111111'}), isTrue);
      expect(service.evaluate(cond, {'top.data': 'b11111110'}), isFalse);
    });

    test('eq with hex condition value', () {
      const cond = SignalCondition(
        signalPath: 'top.addr',
        operator: ConditionOperator.eq,
        value: '0x1F', // 31
      );
      expect(
        service.evaluate(cond, {'top.addr': '11111'}),
        isTrue,
      ); // 31 == 0x1F
    });

    test('eq with binary condition value', () {
      const cond = SignalCondition(
        signalPath: 'top.ctrl',
        operator: ConditionOperator.eq,
        value: '0b1010',
      );
      expect(service.evaluate(cond, {'top.ctrl': '1010'}), isTrue);
      expect(service.evaluate(cond, {'top.ctrl': '1011'}), isFalse);
    });
  });

  // ── evaluate: x/z handling ──────────────────────────────────────────────────

  group('evaluate — x/z handling', () {
    const cond = SignalCondition(
      signalPath: 'top.sig',
      operator: ConditionOperator.eq,
      value: '0',
    );

    test('x value returns false for eq', () {
      expect(service.evaluate(cond, {'top.sig': 'x'}), isFalse);
    });

    test('z value returns false for eq', () {
      expect(service.evaluate(cond, {'top.sig': 'z'}), isFalse);
    });

    test('x value returns false for neq', () {
      const neqCond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.neq,
        value: '0',
      );
      expect(service.evaluate(neqCond, {'top.sig': 'x'}), isFalse);
    });

    test('partial x in multi-bit value returns false', () {
      const multiCond = SignalCondition(
        signalPath: 'top.bus',
        operator: ConditionOperator.eq,
        value: '0',
      );
      expect(service.evaluate(multiCond, {'top.bus': '10x0'}), isFalse);
    });

    test('real-valued signal returns false', () {
      const realCond = SignalCondition(
        signalPath: 'top.analog',
        operator: ConditionOperator.gt,
        value: '0',
      );
      expect(service.evaluate(realCond, {'top.analog': '3.14'}), isFalse);
    });

    test('missing signal returns false', () {
      expect(service.evaluate(cond, {}), isFalse);
    });

    test(
      'x/z condition value — eq always false even when signal is numeric',
      () {
        const xCond = SignalCondition(
          signalPath: 'top.sig',
          operator: ConditionOperator.eq,
          value: 'xx',
        );
        expect(service.evaluate(xCond, {'top.sig': '0'}), isFalse);
        expect(service.evaluate(xCond, {'top.sig': '1'}), isFalse);
        expect(service.evaluate(xCond, {'top.sig': '11111111'}), isFalse);
      },
    );

    test('x/z condition value — neq always false', () {
      const xCond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.neq,
        value: 'x',
      );
      expect(service.evaluate(xCond, {'top.sig': '0'}), isFalse);
      expect(service.evaluate(xCond, {'top.sig': '1'}), isFalse);
    });

    test('z condition value always false', () {
      const zCond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.eq,
        value: 'z',
      );
      expect(service.evaluate(zCond, {'top.sig': '0'}), isFalse);
    });

    test('zz condition value always false', () {
      const zCond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.gt,
        value: 'zz',
      );
      expect(service.evaluate(zCond, {'top.sig': '11111111'}), isFalse);
    });
  });

  // ── evaluate: AND / OR / NOT ────────────────────────────────────────────────

  group('evaluate — AND', () {
    const condA = SignalCondition(
      signalPath: 'top.a',
      operator: ConditionOperator.eq,
      value: '1',
    );
    const condB = SignalCondition(
      signalPath: 'top.b',
      operator: ConditionOperator.eq,
      value: '0',
    );
    const andExpr = AndExpression(left: condA, right: condB);

    test('true AND true → true', () {
      expect(service.evaluate(andExpr, {'top.a': '1', 'top.b': '0'}), isTrue);
    });

    test('true AND false → false', () {
      expect(
        service.evaluate(andExpr, {'top.a': '1', 'top.b': '1'}),
        isFalse,
      );
    });

    test('false AND true → false', () {
      expect(
        service.evaluate(andExpr, {'top.a': '0', 'top.b': '0'}),
        isFalse,
      );
    });

    test('false AND false → false', () {
      expect(
        service.evaluate(andExpr, {'top.a': '0', 'top.b': '1'}),
        isFalse,
      );
    });
  });

  group('evaluate — OR', () {
    const condA = SignalCondition(
      signalPath: 'top.a',
      operator: ConditionOperator.eq,
      value: '1',
    );
    const condB = SignalCondition(
      signalPath: 'top.b',
      operator: ConditionOperator.eq,
      value: '1',
    );
    const orExpr = OrExpression(left: condA, right: condB);

    test('true OR true → true', () {
      expect(service.evaluate(orExpr, {'top.a': '1', 'top.b': '1'}), isTrue);
    });

    test('true OR false → true', () {
      expect(service.evaluate(orExpr, {'top.a': '1', 'top.b': '0'}), isTrue);
    });

    test('false OR true → true', () {
      expect(service.evaluate(orExpr, {'top.a': '0', 'top.b': '1'}), isTrue);
    });

    test('false OR false → false', () {
      expect(
        service.evaluate(orExpr, {'top.a': '0', 'top.b': '0'}),
        isFalse,
      );
    });
  });

  group('evaluate — NOT', () {
    const cond = SignalCondition(
      signalPath: 'top.en',
      operator: ConditionOperator.eq,
      value: '1',
    );
    const notExpr = NotExpression(operand: cond);

    test('NOT true → false', () {
      expect(service.evaluate(notExpr, {'top.en': '1'}), isFalse);
    });

    test('NOT false → true', () {
      expect(service.evaluate(notExpr, {'top.en': '0'}), isTrue);
    });

    test('double NOT restores original', () {
      const notNot = NotExpression(operand: notExpr);
      expect(service.evaluate(notNot, {'top.en': '1'}), isTrue);
      expect(service.evaluate(notNot, {'top.en': '0'}), isFalse);
    });
  });

  group('evaluate — compound expressions', () {
    test('(A AND B) OR C', () {
      const a = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const b = SignalCondition(
        signalPath: 'top.b',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const c = SignalCondition(
        signalPath: 'top.c',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const expr = OrExpression(
        left: AndExpression(left: a, right: b),
        right: c,
      );

      expect(
        service.evaluate(expr, {'top.a': '1', 'top.b': '1', 'top.c': '0'}),
        isTrue,
      );
      expect(
        service.evaluate(expr, {'top.a': '0', 'top.b': '1', 'top.c': '1'}),
        isTrue,
      );
      expect(
        service.evaluate(expr, {'top.a': '0', 'top.b': '0', 'top.c': '0'}),
        isFalse,
      );
    });

    test('NOT (A OR B)', () {
      const a = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const b = SignalCondition(
        signalPath: 'top.b',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const expr = NotExpression(
        operand: OrExpression(left: a, right: b),
      );

      expect(service.evaluate(expr, {'top.a': '0', 'top.b': '0'}), isTrue);
      expect(service.evaluate(expr, {'top.a': '1', 'top.b': '0'}), isFalse);
    });
  });

  // ── parseExpression ─────────────────────────────────────────────────────────

  group('parseExpression', () {
    test('simple eq with decimal value', () {
      final expr = service.parseExpression('top.en == 1');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.en',
          operator: ConditionOperator.eq,
          value: '1',
        ),
      );
    });

    test('simple neq', () {
      final expr = service.parseExpression('top.sig != 0');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.sig',
          operator: ConditionOperator.neq,
          value: '0',
        ),
      );
    });

    test('gt operator', () {
      final expr = service.parseExpression('top.addr > 100');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.addr',
          operator: ConditionOperator.gt,
          value: '100',
        ),
      );
    });

    test('lt operator', () {
      final expr = service.parseExpression('top.addr < 255');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.addr',
          operator: ConditionOperator.lt,
          value: '255',
        ),
      );
    });

    test('gte operator', () {
      final expr = service.parseExpression('top.cnt >= 10');
      expect(
        (expr as SignalCondition).operator,
        ConditionOperator.gte,
      );
    });

    test('lte operator', () {
      final expr = service.parseExpression('top.cnt <= 10');
      expect(
        (expr as SignalCondition).operator,
        ConditionOperator.lte,
      );
    });

    test('bitAnd operator &', () {
      final expr = service.parseExpression('top.flags & 0x80');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.flags',
          operator: ConditionOperator.bitAnd,
          value: '0x80',
        ),
      );
    });

    test('bitOr operator |', () {
      final expr = service.parseExpression('top.flags | 0x03');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.flags',
          operator: ConditionOperator.bitOr,
          value: '0x03',
        ),
      );
    });

    test('hex value 0x prefix', () {
      final expr = service.parseExpression('top.data == 0x1F');
      expect((expr as SignalCondition).value, '0x1F');
    });

    test('binary value 0b prefix', () {
      final expr = service.parseExpression('top.ctrl == 0b1010');
      expect((expr as SignalCondition).value, '0b1010');
    });

    test('AND keyword', () {
      final expr = service.parseExpression('top.a == 1 AND top.b == 0');
      expect(expr, isA<AndExpression>());
      final and = expr as AndExpression;
      expect((and.left as SignalCondition).signalPath, 'top.a');
      expect((and.right as SignalCondition).signalPath, 'top.b');
    });

    test('OR keyword', () {
      final expr = service.parseExpression('top.a == 1 OR top.b == 1');
      expect(expr, isA<OrExpression>());
    });

    test('NOT keyword', () {
      final expr = service.parseExpression('NOT top.en == 1');
      expect(expr, isA<NotExpression>());
      final not = expr as NotExpression;
      expect((not.operand as SignalCondition).signalPath, 'top.en');
    });

    test('parenthesised sub-expression', () {
      final expr = service.parseExpression('(top.a == 1)');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.a',
          operator: ConditionOperator.eq,
          value: '1',
        ),
      );
    });

    test('NOT with parentheses', () {
      final expr = service.parseExpression('NOT (top.a == 1 OR top.b == 0)');
      expect(expr, isA<NotExpression>());
      expect((expr as NotExpression).operand, isA<OrExpression>());
    });

    test('precedence: AND binds tighter than OR', () {
      // Parses as: (a==1 AND b==1) OR c==1
      final expr = service.parseExpression(
        'top.a == 1 AND top.b == 1 OR top.c == 1',
      );
      expect(expr, isA<OrExpression>());
      final or = expr as OrExpression;
      expect(or.left, isA<AndExpression>());
    });

    test('signal path with dots and brackets', () {
      final expr = service.parseExpression('top.cpu.data[7:0] == 0xFF');
      expect((expr as SignalCondition).signalPath, 'top.cpu.data[7:0]');
    });

    test('signal path with underscores', () {
      final expr = service.parseExpression('tb.dut.axi_valid == 1');
      expect((expr as SignalCondition).signalPath, 'tb.dut.axi_valid');
    });

    test('extra whitespace is ignored', () {
      final expr = service.parseExpression('  top.en   ==   1  ');
      expect(
        expr,
        const SignalCondition(
          signalPath: 'top.en',
          operator: ConditionOperator.eq,
          value: '1',
        ),
      );
    });

    test('right-associative NOT NOT', () {
      final expr = service.parseExpression('NOT NOT top.en == 1');
      expect(expr, isA<NotExpression>());
      expect((expr as NotExpression).operand, isA<NotExpression>());
    });

    // ── x/z value literals ────────────────────────────────────────────────────

    test('data_bus == xx parses without error', () {
      final expr = service.parseExpression('data_bus == xx');
      expect(expr, isA<SignalCondition>());
      final cond = expr as SignalCondition;
      expect(cond.signalPath, 'data_bus');
      expect(cond.operator, ConditionOperator.eq);
      expect(cond.value, 'xx');
    });

    test('chip_select == x parses without error', () {
      final expr = service.parseExpression('chip_select == x');
      expect((expr as SignalCondition).value, 'x');
    });

    test('sig == zz parses without error', () {
      final expr = service.parseExpression('sig == zz');
      expect((expr as SignalCondition).value, 'zz');
    });

    test('sig == z parses without error', () {
      final expr = service.parseExpression('sig == z');
      expect((expr as SignalCondition).value, 'z');
    });

    test('x/z literal in compound expression: data_bus == xx AND cs == 1', () {
      final expr = service.parseExpression('data_bus == xx AND cs == 1');
      expect(expr, isA<AndExpression>());
      final and = expr as AndExpression;
      expect((and.left as SignalCondition).value, 'xx');
      expect((and.right as SignalCondition).value, '1');
    });

    // ── parse errors ──────────────────────────────────────────────────────────

    test('empty string throws FormatException', () {
      expect(
        () => service.parseExpression(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing value after operator throws FormatException', () {
      expect(
        () => service.parseExpression('top.sig =='),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing operator throws FormatException', () {
      expect(
        () => service.parseExpression('top.sig'),
        throwsA(isA<FormatException>()),
      );
    });

    test('unclosed parenthesis throws FormatException', () {
      expect(
        () => service.parseExpression('(top.a == 1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('unexpected extra token throws FormatException', () {
      expect(
        () => service.parseExpression('top.a == 1 garbage'),
        throwsA(isA<FormatException>()),
      );
    });

    test('invalid character throws FormatException', () {
      expect(
        () => service.parseExpression('top.sig @ 1'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ── search ──────────────────────────────────────────────────────────────────

  group('search', () {
    test('no transitions → no matches when expression is always false', () {
      when(
        () => source.changesInRange('top.en', start, end),
      ).thenReturn([]);
      when(() => source.valueAt('top.en', start)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.en',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, isEmpty);
      expect(result.searchRange, const TimeRange(start: start, end: end));
    });

    test('signal always true → single match spanning full range', () {
      when(
        () => source.changesInRange('top.en', start, end),
      ).thenReturn([]);
      when(() => source.valueAt('top.en', start)).thenReturn('1');

      const expr = SignalCondition(
        signalPath: 'top.en',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, hasLength(1));
      expect(result.matches.first.time, start);
      expect(result.matches.first.endTime, end);
    });

    test('single transition into true region', () {
      when(
        () => source.changesInRange('top.en', start, end),
      ).thenReturn([const SignalChange(time: 300, value: '1')]);
      when(() => source.valueAt('top.en', start)).thenReturn('0');
      when(() => source.valueAt('top.en', 300)).thenReturn('1');

      const expr = SignalCondition(
        signalPath: 'top.en',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, hasLength(1));
      expect(result.matches.first.time, 300);
      expect(result.matches.first.endTime, end);
    });

    test('single pulse (true then false)', () {
      when(
        () => source.changesInRange('top.pulse', start, end),
      ).thenReturn([
        const SignalChange(time: 200, value: '1'),
        const SignalChange(time: 400, value: '0'),
      ]);
      when(() => source.valueAt('top.pulse', start)).thenReturn('0');
      when(() => source.valueAt('top.pulse', 200)).thenReturn('1');
      when(() => source.valueAt('top.pulse', 400)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.pulse',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, hasLength(1));
      expect(result.matches.first.time, 200);
      expect(result.matches.first.endTime, 400);
      expect(result.matches.first.duration, 200);
    });

    test('two separate pulses → two matches', () {
      when(
        () => source.changesInRange('top.pulse', start, end),
      ).thenReturn([
        const SignalChange(time: 100, value: '1'),
        const SignalChange(time: 200, value: '0'),
        const SignalChange(time: 500, value: '1'),
        const SignalChange(time: 600, value: '0'),
      ]);
      when(() => source.valueAt('top.pulse', start)).thenReturn('0');
      when(() => source.valueAt('top.pulse', 100)).thenReturn('1');
      when(() => source.valueAt('top.pulse', 200)).thenReturn('0');
      when(() => source.valueAt('top.pulse', 500)).thenReturn('1');
      when(() => source.valueAt('top.pulse', 600)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.pulse',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, hasLength(2));
      expect(result.matches[0].time, 100);
      expect(result.matches[0].endTime, 200);
      expect(result.matches[1].time, 500);
      expect(result.matches[1].endTime, 600);
    });

    test('multi-signal AND: match only when both true simultaneously', () {
      when(
        () => source.changesInRange('top.a', start, end),
      ).thenReturn([
        const SignalChange(time: 100, value: '1'),
        const SignalChange(time: 400, value: '0'),
      ]);
      when(
        () => source.changesInRange('top.b', start, end),
      ).thenReturn([
        const SignalChange(time: 200, value: '1'),
        const SignalChange(time: 300, value: '0'),
      ]);

      // top.a timeline: 0──1(T100)──0(T400)
      // top.b timeline: 0──1(T200)──0(T300)
      // AND is true in [200, 300)
      when(() => source.valueAt('top.a', start)).thenReturn('0');
      when(() => source.valueAt('top.a', 100)).thenReturn('1');
      when(() => source.valueAt('top.a', 200)).thenReturn('1');
      when(() => source.valueAt('top.a', 300)).thenReturn('1');
      when(() => source.valueAt('top.a', 400)).thenReturn('0');
      when(() => source.valueAt('top.b', start)).thenReturn('0');
      when(() => source.valueAt('top.b', 100)).thenReturn('0');
      when(() => source.valueAt('top.b', 200)).thenReturn('1');
      when(() => source.valueAt('top.b', 300)).thenReturn('0');
      when(() => source.valueAt('top.b', 400)).thenReturn('0');

      const expr = AndExpression(
        left: SignalCondition(
          signalPath: 'top.a',
          operator: ConditionOperator.eq,
          value: '1',
        ),
        right: SignalCondition(
          signalPath: 'top.b',
          operator: ConditionOperator.eq,
          value: '1',
        ),
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, hasLength(1));
      expect(result.matches.first.time, 200);
      expect(result.matches.first.endTime, 300);
    });

    test('match extends to endTime when no closing transition', () {
      when(
        () => source.changesInRange('top.en', start, end),
      ).thenReturn([const SignalChange(time: 800, value: '1')]);
      when(() => source.valueAt('top.en', start)).thenReturn('0');
      when(() => source.valueAt('top.en', 800)).thenReturn('1');

      const expr = SignalCondition(
        signalPath: 'top.en',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, hasLength(1));
      expect(result.matches.first.endTime, end);
    });

    test('signal values snapshot captured at match start', () {
      when(
        () => source.changesInRange('top.a', start, end),
      ).thenReturn([
        const SignalChange(time: 100, value: '1'),
        const SignalChange(time: 300, value: '0'),
      ]);
      when(
        () => source.changesInRange('top.b', start, end),
      ).thenReturn([]);
      when(() => source.valueAt('top.a', start)).thenReturn('0');
      when(() => source.valueAt('top.a', 100)).thenReturn('1');
      when(() => source.valueAt('top.a', 300)).thenReturn('0');
      when(() => source.valueAt('top.b', start)).thenReturn('b10101010');
      when(() => source.valueAt('top.b', 100)).thenReturn('b10101010');
      when(() => source.valueAt('top.b', 300)).thenReturn('b10101010');

      const expr = AndExpression(
        left: SignalCondition(
          signalPath: 'top.a',
          operator: ConditionOperator.eq,
          value: '1',
        ),
        right: SignalCondition(
          signalPath: 'top.b',
          operator: ConditionOperator.gt,
          value: '0',
        ),
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, hasLength(1));
      expect(result.matches.first.signalValues['top.a'], '1');
      expect(result.matches.first.signalValues['top.b'], 'b10101010');
    });

    test('x value in signal prevents match', () {
      when(
        () => source.changesInRange('top.sig', start, end),
      ).thenReturn([
        const SignalChange(time: 100, value: 'x'),
        const SignalChange(time: 200, value: '1'),
      ]);
      when(() => source.valueAt('top.sig', start)).thenReturn('x');
      when(() => source.valueAt('top.sig', 100)).thenReturn('x');
      when(() => source.valueAt('top.sig', 200)).thenReturn('1');

      const expr = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      // Match only from T200 onward (x at T0 and T100 does not match).
      expect(result.matches, hasLength(1));
      expect(result.matches.first.time, 200);
    });

    test('result preserves expression and searchRange', () {
      when(
        () => source.changesInRange('top.en', start, end),
      ).thenReturn([]);
      when(() => source.valueAt('top.en', start)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.en',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result.expression, expr);
      expect(result.searchRange, const TimeRange(start: start, end: end));
    });

    test('search over sub-range uses provided start and end', () {
      when(
        () => source.changesInRange('top.sig', 200, 500),
      ).thenReturn([
        const SignalChange(time: 300, value: '1'),
        const SignalChange(time: 400, value: '0'),
      ]);
      when(() => source.valueAt('top.sig', 200)).thenReturn('0');
      when(() => source.valueAt('top.sig', 300)).thenReturn('1');
      when(() => source.valueAt('top.sig', 400)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, 200, 500);

      expect(result.searchRange, const TimeRange(start: 200, end: 500));
      expect(result.matches, hasLength(1));
      expect(result.matches.first.time, 300);
      expect(result.matches.first.endTime, 400);
    });

    test('x/z condition value → 0 matches, no error', () {
      when(
        () => source.changesInRange('top.bus', start, end),
      ).thenReturn([]);
      when(() => source.valueAt('top.bus', start)).thenReturn('11111111');

      const expr = SignalCondition(
        signalPath: 'top.bus',
        operator: ConditionOperator.eq,
        value: 'xx',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, isEmpty);
      expect(result.matchCount, 0);
    });

    test('chip_select == x → 0 matches, no error', () {
      when(
        () => source.changesInRange('top.cs', start, end),
      ).thenReturn([
        const SignalChange(time: 100, value: '1'),
        const SignalChange(time: 200, value: '0'),
      ]);
      when(() => source.valueAt('top.cs', start)).thenReturn('0');
      when(() => source.valueAt('top.cs', 100)).thenReturn('1');
      when(() => source.valueAt('top.cs', 200)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.cs',
        operator: ConditionOperator.eq,
        value: 'x',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, isEmpty);
    });

    test('data_bus == z → 0 matches, no error', () {
      when(
        () => source.changesInRange('top.bus', start, end),
      ).thenReturn([]);
      when(() => source.valueAt('top.bus', start)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.bus',
        operator: ConditionOperator.eq,
        value: 'z',
      );
      final result = service.search(expr, source, start, end);

      expect(result.matches, isEmpty);
    });

    test('empty search range returns no matches', () {
      when(
        () => source.changesInRange('top.sig', 100, 100),
      ).thenReturn([]);
      when(() => source.valueAt('top.sig', 100)).thenReturn('1');

      const expr = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, 100, 100);

      expect(result.matches, isEmpty);
    });

    test('NOT expression: matches when condition is false', () {
      when(
        () => source.changesInRange('top.err', start, end),
      ).thenReturn([
        const SignalChange(time: 300, value: '1'),
        const SignalChange(time: 600, value: '0'),
      ]);
      when(() => source.valueAt('top.err', start)).thenReturn('0');
      when(() => source.valueAt('top.err', 300)).thenReturn('1');
      when(() => source.valueAt('top.err', 600)).thenReturn('0');

      const expr = NotExpression(
        operand: SignalCondition(
          signalPath: 'top.err',
          operator: ConditionOperator.eq,
          value: '1',
        ),
      );
      final result = service.search(expr, source, start, end);

      // True when err == 0: [0, 300) and [600, 1000)
      expect(result.matches, hasLength(2));
      expect(result.matches[0].time, 0);
      expect(result.matches[0].endTime, 300);
      expect(result.matches[1].time, 600);
      expect(result.matches[1].endTime, end);
    });

    test('PatternSearchResult has correct matchCount', () {
      when(
        () => source.changesInRange('top.clk', start, end),
      ).thenReturn([
        const SignalChange(time: 100, value: '1'),
        const SignalChange(time: 200, value: '0'),
        const SignalChange(time: 300, value: '1'),
        const SignalChange(time: 400, value: '0'),
      ]);
      when(() => source.valueAt('top.clk', start)).thenReturn('0');
      when(() => source.valueAt('top.clk', 100)).thenReturn('1');
      when(() => source.valueAt('top.clk', 200)).thenReturn('0');
      when(() => source.valueAt('top.clk', 300)).thenReturn('1');
      when(() => source.valueAt('top.clk', 400)).thenReturn('0');

      const expr = SignalCondition(
        signalPath: 'top.clk',
        operator: ConditionOperator.eq,
        value: '1',
      );
      final result = service.search(expr, source, start, end);

      expect(result, isA<PatternSearchResult>());
      expect(result.matchCount, 2);
      expect(result.hasMatches, isTrue);
    });
  });
}
