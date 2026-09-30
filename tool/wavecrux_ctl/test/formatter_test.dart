// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:test/test.dart';
import 'package:wavecrux_ctl/src/formatter.dart';

void main() {
  group('Formatter.formatState', () {
    test('shows file, loaded, cursor, zoom, signal count', () {
      final result = <String, dynamic>{
        'file': '/path/to/sim.vcd',
        'is_loaded': true,
        'cursor': 1000,
        'secondary_cursor': null,
        'ticks_per_pixel': 4.0,
        'signal_count': 3,
      };
      final out = Formatter.formatState(result);
      expect(out, contains('/path/to/sim.vcd'));
      expect(out, contains('true'));
      expect(out, contains('1000 ticks'));
      expect(out, contains('4.0000 ticks/px'));
      expect(out, contains('3'));
    });

    test('shows (none) when no file loaded', () {
      final result = <String, dynamic>{
        'file': null,
        'is_loaded': false,
        'cursor': null,
        'secondary_cursor': null,
        'ticks_per_pixel': 1.0,
        'signal_count': 0,
      };
      final out = Formatter.formatState(result);
      expect(out, contains('(none)'));
      expect(out, contains('false'));
    });

    test('shows secondary cursor when present', () {
      final result = <String, dynamic>{
        'file': 'x.vcd',
        'is_loaded': true,
        'cursor': 500,
        'secondary_cursor': 1500,
        'ticks_per_pixel': 1.0,
        'signal_count': 0,
      };
      final out = Formatter.formatState(result);
      expect(out, contains('1500 ticks'));
    });
  });

  group('Formatter.formatItems', () {
    test('returns placeholder when empty', () {
      final out = Formatter.formatItems({'items': <dynamic>[]});
      expect(out, contains('no signals'));
    });

    test('shows item IDs and paths', () {
      final out = Formatter.formatItems({
        'items': [
          {'id': 1, 'path': 'top.cpu.clk'},
          {'id': 2, 'path': 'top.cpu.data'},
        ],
      });
      expect(out, contains('top.cpu.clk'));
      expect(out, contains('top.cpu.data'));
      expect(out, contains('1'));
      expect(out, contains('2'));
    });

    test('shows header row with ID and PATH', () {
      final out = Formatter.formatItems({
        'items': [
          {'id': 42, 'path': 'top.sig'},
        ],
      });
      expect(out, contains('ID'));
      expect(out, contains('PATH'));
    });
  });

  group('Formatter.formatHierarchy', () {
    test('returns placeholder when empty', () {
      final out = Formatter.formatHierarchy({'scopes': <dynamic>[]});
      expect(out, contains('no hierarchy'));
    });

    test('renders scope name and type', () {
      final out = Formatter.formatHierarchy({
        'scopes': [
          {
            'name': 'top',
            'type': 'module',
            'variables': <dynamic>[],
            'children': <dynamic>[],
          },
        ],
      });
      expect(out, contains('top'));
      expect(out, contains('module'));
    });

    test('renders variables with var_type and bit_width', () {
      final out = Formatter.formatHierarchy({
        'scopes': [
          {
            'name': 'top',
            'type': 'module',
            'variables': [
              {'name': 'clk', 'var_type': 'wire', 'bit_width': 1},
              {'name': 'data', 'var_type': 'reg', 'bit_width': 32},
            ],
            'children': <dynamic>[],
          },
        ],
      });
      expect(out, contains('clk'));
      expect(out, contains('wire'));
      expect(out, contains('1b'));
      expect(out, contains('data'));
      expect(out, contains('32b'));
    });

    test('renders nested child scopes', () {
      final out = Formatter.formatHierarchy({
        'scopes': [
          {
            'name': 'top',
            'type': 'module',
            'variables': <dynamic>[],
            'children': [
              {
                'name': 'cpu',
                'type': 'module',
                'variables': <dynamic>[],
                'children': <dynamic>[],
              },
            ],
          },
        ],
      });
      expect(out, contains('top'));
      expect(out, contains('cpu'));
      expect(out, contains('└──'));
    });

    test('uses ├── for non-last and └── for last child', () {
      final out = Formatter.formatHierarchy({
        'scopes': [
          {
            'name': 'top',
            'type': 'module',
            'variables': <dynamic>[],
            'children': [
              {
                'name': 'a',
                'type': 'module',
                'variables': <dynamic>[],
                'children': <dynamic>[],
              },
              {
                'name': 'b',
                'type': 'module',
                'variables': <dynamic>[],
                'children': <dynamic>[],
              },
            ],
          },
        ],
      });
      expect(out, contains('├──'));
      expect(out, contains('└──'));
    });
  });

  group('Formatter.formatValue', () {
    test('formats signal_path, tick, and value', () {
      final out = Formatter.formatValue({
        'signal_path': 'top.cpu.data',
        'time': 1000,
        'value': '0x00FF',
      });
      expect(out, contains('top.cpu.data'));
      expect(out, contains('1000'));
      expect(out, contains('0x00FF'));
    });
  });

  group('Formatter.rawJson', () {
    test('returns valid JSON string', () {
      const result = <String, dynamic>{'ok': true, 'count': 3};
      final out = Formatter.rawJson(result);
      expect(out, '{"ok":true,"count":3}');
    });
  });
}
