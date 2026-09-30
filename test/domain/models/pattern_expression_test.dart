// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';

void main() {
  // ── ConditionOperator ───────────────────────────────────────────────────────

  group('ConditionOperator', () {
    test('has all eight values', () {
      expect(ConditionOperator.values, hasLength(8));
      expect(
        ConditionOperator.values,
        containsAll([
          ConditionOperator.eq,
          ConditionOperator.neq,
          ConditionOperator.gt,
          ConditionOperator.lt,
          ConditionOperator.gte,
          ConditionOperator.lte,
          ConditionOperator.bitAnd,
          ConditionOperator.bitOr,
        ]),
      );
    });
  });

  // ── SignalCondition ─────────────────────────────────────────────────────────

  group('SignalCondition', () {
    const cond = SignalCondition(
      signalPath: 'top.cpu.en',
      operator: ConditionOperator.eq,
      value: '1',
    );

    test('stores fields', () {
      expect(cond.signalPath, 'top.cpu.en');
      expect(cond.operator, ConditionOperator.eq);
      expect(cond.value, '1');
    });

    test('signalPaths returns the single path', () {
      expect(cond.signalPaths, {'top.cpu.en'});
    });

    test('equality and hashCode', () {
      const same = SignalCondition(
        signalPath: 'top.cpu.en',
        operator: ConditionOperator.eq,
        value: '1',
      );
      expect(cond, same);
      expect(cond.hashCode, same.hashCode);
    });

    test('inequality when fields differ', () {
      expect(
        cond,
        isNot(
          const SignalCondition(
            signalPath: 'top.cpu.other',
            operator: ConditionOperator.eq,
            value: '1',
          ),
        ),
      );
      expect(
        cond,
        isNot(
          const SignalCondition(
            signalPath: 'top.cpu.en',
            operator: ConditionOperator.neq,
            value: '1',
          ),
        ),
      );
      expect(
        cond,
        isNot(
          const SignalCondition(
            signalPath: 'top.cpu.en',
            operator: ConditionOperator.eq,
            value: '0',
          ),
        ),
      );
    });

    test('toString contains signalPath', () {
      expect(cond.toString(), contains('top.cpu.en'));
    });
  });

  // ── AndExpression ───────────────────────────────────────────────────────────

  group('AndExpression', () {
    const left = SignalCondition(
      signalPath: 'top.a',
      operator: ConditionOperator.eq,
      value: '1',
    );
    const right = SignalCondition(
      signalPath: 'top.b',
      operator: ConditionOperator.eq,
      value: '0',
    );
    const expr = AndExpression(left: left, right: right);

    test('signalPaths unions both subtrees', () {
      expect(expr.signalPaths, {'top.a', 'top.b'});
    });

    test('equality and hashCode', () {
      const same = AndExpression(left: left, right: right);
      expect(expr, same);
      expect(expr.hashCode, same.hashCode);
    });

    test('inequality when children differ', () {
      const other = AndExpression(
        left: right, // swapped
        right: left,
      );
      expect(expr, isNot(other));
    });

    test('toString contains AndExpression', () {
      expect(expr.toString(), contains('AndExpression'));
    });
  });

  // ── OrExpression ────────────────────────────────────────────────────────────

  group('OrExpression', () {
    const left = SignalCondition(
      signalPath: 'top.a',
      operator: ConditionOperator.gt,
      value: '5',
    );
    const right = SignalCondition(
      signalPath: 'top.b',
      operator: ConditionOperator.lt,
      value: '10',
    );
    const expr = OrExpression(left: left, right: right);

    test('signalPaths unions both subtrees', () {
      expect(expr.signalPaths, {'top.a', 'top.b'});
    });

    test('equality and hashCode', () {
      const same = OrExpression(left: left, right: right);
      expect(expr, same);
      expect(expr.hashCode, same.hashCode);
    });

    test('inequality for OrExpression vs AndExpression with same children', () {
      const andExpr = AndExpression(left: left, right: right);
      expect(expr, isNot(andExpr));
    });

    test('toString contains OrExpression', () {
      expect(expr.toString(), contains('OrExpression'));
    });
  });

  // ── NotExpression ───────────────────────────────────────────────────────────

  group('NotExpression', () {
    const inner = SignalCondition(
      signalPath: 'top.valid',
      operator: ConditionOperator.neq,
      value: '0',
    );
    const expr = NotExpression(operand: inner);

    test('signalPaths delegates to operand', () {
      expect(expr.signalPaths, {'top.valid'});
    });

    test('equality and hashCode', () {
      const same = NotExpression(operand: inner);
      expect(expr, same);
      expect(expr.hashCode, same.hashCode);
    });

    test('inequality when operand differs', () {
      const other = NotExpression(
        operand: SignalCondition(
          signalPath: 'top.other',
          operator: ConditionOperator.neq,
          value: '0',
        ),
      );
      expect(expr, isNot(other));
    });

    test('toString contains NotExpression', () {
      expect(expr.toString(), contains('NotExpression'));
    });
  });

  // ── nested signalPaths ──────────────────────────────────────────────────────

  group('nested signalPaths', () {
    test('deeply nested tree returns all paths', () {
      const a = SignalCondition(
        signalPath: 'top.a',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const b = SignalCondition(
        signalPath: 'top.b',
        operator: ConditionOperator.eq,
        value: '0',
      );
      const c = SignalCondition(
        signalPath: 'top.c',
        operator: ConditionOperator.gt,
        value: '5',
      );
      const expr = OrExpression(
        left: AndExpression(left: a, right: b),
        right: NotExpression(operand: c),
      );
      expect(expr.signalPaths, {'top.a', 'top.b', 'top.c'});
    });

    test('duplicate paths appear once in the set', () {
      const cond = SignalCondition(
        signalPath: 'top.sig',
        operator: ConditionOperator.eq,
        value: '1',
      );
      const expr = AndExpression(left: cond, right: cond);
      expect(expr.signalPaths, {'top.sig'});
    });
  });
}
