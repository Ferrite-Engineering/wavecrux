// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';

void main() {
  group('Scope', () {
    const clk = Variable(
      name: 'clk',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: '0',
      scopePath: 'top',
      bitWidth: 1,
    );
    const data = Variable(
      name: 'data',
      varType: VarType.reg,
      direction: VarDirection.unknown,
      signalRef: '1',
      scopePath: 'top.cpu',
      bitWidth: 8,
    );

    const cpu = Scope(
      name: 'cpu',
      type: ScopeType.module,
      path: 'top.cpu',
      variables: [data],
    );

    const top = Scope(
      name: 'top',
      type: ScopeType.module,
      path: 'top',
      childScopes: [cpu],
      variables: [clk],
    );

    const empty = Scope(
      name: 'empty',
      type: ScopeType.begin,
      path: 'top.empty',
    );

    // ── construction ─────────────────────────────────────────────────────────

    test('stores all fields', () {
      expect(top.name, 'top');
      expect(top.type, ScopeType.module);
      expect(top.path, 'top');
      expect(top.childScopes, hasLength(1));
      expect(top.variables, hasLength(1));
    });

    test('default lists are empty', () {
      expect(empty.childScopes, isEmpty);
      expect(empty.variables, isEmpty);
    });

    // ── totalVariableCount ───────────────────────────────────────────────────

    test('leaf scope with one variable → count 1', () {
      expect(cpu.totalVariableCount, 1);
    });
    test('parent scope counts own + descendants', () {
      // top has 1 direct var (clk) + cpu has 1 var (data) = 2
      expect(top.totalVariableCount, 2);
    });
    test('empty scope → count 0', () {
      expect(empty.totalVariableCount, 0);
    });
    test('deep nesting counts all levels', () {
      const grandchild = Scope(
        name: 'alu',
        type: ScopeType.module,
        path: 'top.cpu.alu',
        variables: [data, data],
      );
      const parent = Scope(
        name: 'cpu',
        type: ScopeType.module,
        path: 'top.cpu',
        childScopes: [grandchild],
        variables: [clk],
      );
      expect(parent.totalVariableCount, 3); // 1 own + 2 grandchild
    });

    // ── copyWith ─────────────────────────────────────────────────────────────

    test('copyWith(name:) changes only name', () {
      final s = top.copyWith(name: 'top2');
      expect(s.name, 'top2');
      expect(s.type, ScopeType.module);
      expect(s.path, 'top');
    });
    test('copyWith(childScopes: []) clears children', () {
      final s = top.copyWith(childScopes: []);
      expect(s.childScopes, isEmpty);
      expect(s.variables, hasLength(1));
    });
    test('copyWith(variables: []) clears variables', () {
      final s = top.copyWith(variables: []);
      expect(s.variables, isEmpty);
      expect(s.childScopes, hasLength(1));
    });
    test('copyWith with no args returns equal object', () {
      expect(top.copyWith(), equals(top));
    });

    // ── equality ─────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const a = Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        childScopes: [cpu],
        variables: [clk],
      );
      const b = Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        childScopes: [cpu],
        variables: [clk],
      );
      expect(a, equals(b));
    });
    test('not equal when name differs', () {
      expect(top, isNot(equals(top.copyWith(name: 'other'))));
    });
    test('not equal when type differs', () {
      expect(top, isNot(equals(top.copyWith(type: ScopeType.task))));
    });
    test('not equal when path differs', () {
      expect(top, isNot(equals(top.copyWith(path: 'other'))));
    });
    test('not equal when childScopes differ', () {
      expect(top, isNot(equals(top.copyWith(childScopes: []))));
    });
    test('not equal when variables differ', () {
      expect(top, isNot(equals(top.copyWith(variables: []))));
    });
    test('hashCode equal for equal objects', () {
      const a = Scope(name: 'top', type: ScopeType.module, path: 'top');
      const b = Scope(name: 'top', type: ScopeType.module, path: 'top');
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── toString ─────────────────────────────────────────────────────────────

    test('toString contains path', () {
      expect(top.toString(), contains('top'));
    });
  });
}
