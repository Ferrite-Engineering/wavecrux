// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/ahb_lite_decoder.dart';

// ── test helpers ──────────────────────────────────────────────────────────────

SignalValueQuery makeQuery(Map<String, List<(int, String)>> changes) {
  return (signal, time) {
    final list = changes[signal] ?? [];
    String? held;
    for (final (t, v) in list) {
      if (t > time) break;
      held = v;
    }
    return held;
  };
}

SignalChangesQuery makeChangesQuery(
  Map<String, List<(int, String)>> changes,
) {
  return (signal, start, end) {
    final list = changes[signal] ?? [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };
}

/// Encodes a vector value as a VCD-style binary literal (`b<bits>`).
String bv(int v, int width) =>
    'b${v.toUnsigned(width).toRadixString(2).padLeft(width, '0')}';

AhbLiteDecoder makeDecoder({
  Map<String, String>? bindings,
  Map<String, dynamic>? parameters,
}) {
  return AhbLiteDecoder(
    DecoderConfig(
      signalBindings: bindings ?? _defaultBindings,
      parameters: parameters ?? _defaultParams,
    ),
  );
}

const _defaultBindings = {
  'hclk': 'tb.HCLK',
  'hresetn': 'tb.HRESETN',
  'haddr': 'tb.HADDR',
  'htrans': 'tb.HTRANS',
  'hwrite': 'tb.HWRITE',
  'hsize': 'tb.HSIZE',
  'hburst': 'tb.HBURST',
  'hwdata': 'tb.HWDATA',
  'hrdata': 'tb.HRDATA',
  'hready': 'tb.HREADY',
  'hresp': 'tb.HRESP',
};

const _defaultParams = <String, dynamic>{
  'addr_width': 32,
  'data_width': '32',
  'check_alignment': true,
  'wait_state_threshold': 256,
};

const _bindingsWithProtLock = <String, String>{
  ..._defaultBindings,
  'hprot': 'tb.HPROT',
  'hmastlock': 'tb.HMASTLOCK',
};

// ── fixture-driven tests ──────────────────────────────────────────────────────

/// Loads `path` (mirrored under `test/fixtures/protocol/ahb_lite/generated/`) as a
/// list of expected JSON transactions and returns a `Map<String, dynamic>`
/// per row.
List<Map<String, dynamic>> _loadExpected(String name) {
  final file = File(
    'test/fixtures/protocol/ahb_lite/generated/$name'
    '.expected_transactions.json',
  );
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'fixture not found at ${file.path}; '
        'regenerate via `dart run tool/generate_ahb_lite_fixtures.dart`',
  );
  final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  return [for (final row in list) row as Map<String, dynamic>];
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AhbLiteDecoder', () {
    // ── definition ────────────────────────────────────────────────────────────

    group('definition', () {
      test('id, displayName, category, tier', () {
        const def = AhbLiteDecoder.decoderDefinition;
        expect(def.id, 'ahb_lite');
        expect(def.displayName, 'AHB-Lite');
        expect(def.category, DecoderCategory.amba);
        expect(def.requiredTier, LicenseTier.openCore);
      });

      test('required signals cover the AHB-Lite handshake set', () {
        const def = AhbLiteDecoder.decoderDefinition;
        final names = def.requiredSignals.map((s) => s.name).toSet();
        expect(
          names,
          containsAll(<String>{
            'hclk',
            'hresetn',
            'haddr',
            'htrans',
            'hwrite',
            'hsize',
            'hburst',
            'hwdata',
            'hrdata',
            'hready',
            'hresp',
          }),
        );
      });

      test('optional signals are hprot and hmastlock', () {
        const def = AhbLiteDecoder.decoderDefinition;
        final names = def.optionalSignals.map((s) => s.name).toSet();
        expect(names, equals(<String>{'hprot', 'hmastlock'}));
      });

      test('parameters expose addr_width, data_width, check_alignment, '
          'wait_state_threshold', () {
        const def = AhbLiteDecoder.decoderDefinition;
        final byName = {for (final p in def.parameters) p.name: p};

        expect(byName['addr_width']?.type, DecoderParameterType.integer);
        expect(byName['addr_width']?.defaultValue, 32);

        expect(byName['data_width']?.type, DecoderParameterType.enumeration);
        expect(byName['data_width']?.defaultValue, '32');
        expect(
          byName['data_width']?.enumValues,
          containsAll(<String>['8', '16', '32', '64']),
        );

        expect(byName['check_alignment']?.type, DecoderParameterType.boolean);
        expect(byName['check_alignment']?.defaultValue, true);

        expect(
          byName['wait_state_threshold']?.type,
          DecoderParameterType.integer,
        );
        expect(byName['wait_state_threshold']?.defaultValue, 256);
      });
    });

    // ── single-transfer round-trip from fixtures ──────────────────────────────

    group('SINGLE basic fixture', () {
      test('matches expected_transactions.json (read + write OKAY)', () {
        final expected = _loadExpected('ahb_lite_single_basic');

        // Reproduce the same scenario inline so we don't depend on VCD
        // parsing. Each beat: address phase at edge T, data sampled at
        // edge T+10.
        final changes = <String, List<(int, String)>>{
          'hclk': [
            (5, '1'),
            (10, '0'),
            (15, '1'),
            (20, '0'),
            (25, '1'),
            (30, '0'),
            (35, '1'),
            (40, '0'),
            (45, '1'),
            (50, '0'),
            (55, '1'),
            (60, '0'),
          ],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          // c0 (t=2): NONSEQ READ from 0x100.
          'htrans': [
            (0, bv(0, 2)),
            (2, bv(2, 2)),
            (12, bv(2, 2)),
            (22, bv(0, 2)),
          ],
          'hwrite': [(0, '0'), (2, '0'), (12, '1'), (22, '0')],
          'hsize': [(0, bv(0, 3)), (2, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [
            (0, bv(0, 32)),
            (2, bv(0x100, 32)),
            (12, bv(0x200, 32)),
            (22, bv(0, 32)),
          ],
          'hwdata': [(0, bv(0, 32)), (22, bv(0xDEADBEEF, 32)), (32, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0x12345678, 32)), (32, bv(0, 32))],
        };

        final txs = makeDecoder().decode(
          0,
          60,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        // Two beats expected. Order matches the JSON.
        expect(txs.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          expect(txs[i].label, expected[i]['label'] as String);
          expect(txs[i].isError, expected[i]['isError'] as bool);
          expect(
            txs[i].fields,
            equals((expected[i]['fields'] as Map).cast<String, String>()),
          );
        }
      });
    });

    group('INCR4 burst fixture', () {
      test('emits 4 beats + 1 parent matching expected JSON', () {
        final expected = _loadExpected('ahb_lite_incr_burst');
        // 5 records: 4 beats + 1 parent burst summary.
        expect(expected.length, 5);
        final parentFields = expected[1]['fields'] as Map;
        expect(parentFields['type'], 'Burst');
        expect(parentFields['beats'], '4');
        expect(parentFields['burst'], 'INCR4');

        final beatLabels = [
          for (final tx in expected)
            if ((tx['fields'] as Map)['type'] != 'Burst') tx['label'] as String,
        ];
        expect(beatLabels, [
          'R 0x00000100 → 0xA0A0A0A0 [INCR4 1]',
          'R 0x00000104 → 0xB1B1B1B1 [INCR4 2]',
          'R 0x00000108 → 0xC2C2C2C2 [INCR4 3]',
          'R 0x0000010C → 0xD3D3D3D3 [INCR4 4]',
        ]);
      });
    });

    group('WRAP4 burst fixture', () {
      test('beats wrap inside 16-byte window starting at 0x108', () {
        final expected = _loadExpected('ahb_lite_wrap_burst');
        final beatAddrs = [
          for (final tx in expected)
            if ((tx['fields'] as Map)['type'] != 'Burst')
              (tx['fields'] as Map)['address'] as String,
        ];
        expect(beatAddrs, [
          '0x00000108',
          '0x0000010C',
          '0x00000100', // wrap
          '0x00000104',
        ]);
        // No spurious violations.
        for (final tx in expected) {
          expect(
            tx['isError'],
            isFalse,
            reason:
                'WRAP4 fixture should be violation-free: '
                '${tx['errorMessage']}',
          );
        }
      });
    });

    group('INCR (undefined) burst fixture', () {
      test('3 beats with mid-burst BUSY, ended by IDLE', () {
        final expected = _loadExpected('ahb_lite_incr_undefined');
        final beats = [
          for (final tx in expected)
            if ((tx['fields'] as Map)['type'] != 'Burst') tx,
        ];
        expect(beats.length, 3);
        expect((beats[0]['fields'] as Map)['address'], '0x00000200');
        expect((beats[1]['fields'] as Map)['address'], '0x00000204');
        expect((beats[2]['fields'] as Map)['address'], '0x00000208');
        // Parent record present.
        final parents = [
          for (final tx in expected)
            if ((tx['fields'] as Map)['type'] == 'Burst') tx,
        ];
        expect(parents.length, 1);
        expect((parents[0]['fields'] as Map)['burst'], 'INCR');
        expect((parents[0]['fields'] as Map)['beats'], '3');
      });
    });

    group('wait-state fixture', () {
      test('single beat with wait_states recorded', () {
        final expected = _loadExpected('ahb_lite_wait_states');
        // Exactly one beat (the read with wait states); no spurious
        // violations.
        expect(expected.length, 1);
        final tx = expected[0];
        expect(tx['isError'], isFalse);
        expect((tx['fields'] as Map)['address'], '0x00000100');
        expect(
          int.parse((tx['fields'] as Map)['wait_states'] as String),
          greaterThanOrEqualTo(2),
        );
      });
    });

    group('two-cycle ERROR response fixture', () {
      test('emits ERROR beat without violation 7 surfacing', () {
        final expected = _loadExpected('ahb_lite_error_response');
        expect(expected.length, 1);
        final tx = expected[0];
        expect(tx['isError'], isTrue);
        expect((tx['fields'] as Map)['response'], 'ERROR');
        // Two-cycle handshake satisfied → errorMessage is the simple
        // "Response = ERROR" form, not the violation-7 message.
        expect(tx['errorMessage'], 'Response = ERROR');
      });
    });

    group('locked transfer fixture', () {
      test('HPROT and HMASTLOCK propagate into transaction fields', () {
        final expected = _loadExpected('ahb_lite_locked_transfer');
        for (final tx in expected) {
          final fields = (tx['fields'] as Map).cast<String, String>();
          expect(
            fields['locked'],
            '1',
            reason: 'every beat in this fixture is HMASTLOCK-protected',
          );
          expect(fields['hprot'], '0x3');
          expect(fields['hprot_data_or_instr'], 'data');
          expect(fields['hprot_privileged'], '1');
          expect(fields['hprot_bufferable'], '0');
          expect(fields['hprot_cacheable'], '0');
        }
      });
    });

    group('protocol violations fixture', () {
      late List<Map<String, dynamic>> expected;
      setUpAll(() {
        expected = _loadExpected('ahb_lite_violations');
      });

      String? messageContaining(String fragment) {
        for (final tx in expected) {
          if (tx['isError'] != true) continue;
          final m = tx['errorMessage'] as String?;
          if (m != null && m.contains(fragment)) return m;
        }
        return null;
      }

      test('violation 1 — BUSY without active burst', () {
        expect(messageContaining('HTRANS=BUSY'), isNotNull);
      });

      test('violation 2 — SEQ without preceding NONSEQ', () {
        expect(messageContaining('without a preceding NONSEQ'), isNotNull);
      });

      test('violation 3 — HBURST changed mid-burst', () {
        expect(messageContaining('HBURST changed mid-burst'), isNotNull);
      });

      test('violation 4 — HADDR does not match expected next beat', () {
        expect(
          messageContaining('does not match expected next beat'),
          isNotNull,
        );
      });

      test('violation 5 — HSIZE wider than data_width', () {
        expect(messageContaining('HSIZE encodes a 64-bit'), isNotNull);
      });

      test('violation 6 — misaligned HADDR', () {
        expect(messageContaining('Misaligned HADDR'), isNotNull);
      });

      test('violation 7 — single-cycle ERROR (no two-cycle handshake)', () {
        expect(messageContaining('without two-cycle handshake'), isNotNull);
      });
    });

    // ── parameter behavior ────────────────────────────────────────────────────

    group('check_alignment parameter', () {
      test('check_alignment=false suppresses misalignment violation', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          // Misaligned address.
          'haddr': [(0, bv(0, 32)), (2, bv(0x101, 32)), (12, bv(0, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32))],
        };

        final withCheck = makeDecoder(
          parameters: {..._defaultParams, 'check_alignment': true},
        ).decode(0, 25, makeQuery(changes), makeChangesQuery(changes));
        expect(
          withCheck.any(
            (t) => t.errorMessage?.contains('Misaligned HADDR') ?? false,
          ),
          isTrue,
          reason: 'check_alignment=true should flag misalignment',
        );

        final withoutCheck = makeDecoder(
          parameters: {..._defaultParams, 'check_alignment': false},
        ).decode(0, 25, makeQuery(changes), makeChangesQuery(changes));
        expect(
          withoutCheck.any(
            (t) => t.errorMessage?.contains('Misaligned HADDR') ?? false,
          ),
          isFalse,
          reason: 'check_alignment=false should suppress misalignment',
        );
      });
    });

    group('data_width parameter', () {
      test('64-bit data_width allows HSIZE=doubleword without violation', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          // HSIZE=3 (64-bit doubleword)
          'hsize': [(0, bv(3, 3))],
          'hburst': [(0, bv(0, 3))],
          // 64-bit-aligned address.
          'haddr': [(0, bv(0, 64)), (2, bv(0x108, 64)), (12, bv(0, 64))],
          'hwdata': [(0, bv(0, 64))],
          'hrdata': [(0, bv(0, 64)), (12, bv(0xCAFE, 64))],
        };

        final txs = makeDecoder(
          parameters: {..._defaultParams, 'data_width': '64'},
        ).decode(0, 25, makeQuery(changes), makeChangesQuery(changes));

        expect(
          txs.any((t) => t.errorMessage?.contains('wider than') ?? false),
          isFalse,
          reason: 'HSIZE=64-bit should be valid when data_width=64',
        );
      });
    });

    // ── empty trace ───────────────────────────────────────────────────────────

    group('empty trace', () {
      test('returns an empty transaction list when no clock activity', () {
        final txs = makeDecoder().decode(
          0,
          1000,
          (_, _) => null,
          (_, _, _) => const [],
        );
        expect(txs, isEmpty);
      });
    });

    // ── multi-instance independence ───────────────────────────────────────────

    group('multi-instance independence', () {
      test('two AhbLiteDecoder instances with different configs do not '
          'interfere', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [(0, bv(0, 32)), (2, bv(0x101, 32)), (12, bv(0, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0xAA, 32))],
        };

        final query = makeQuery(changes);
        final cq = makeChangesQuery(changes);

        final strict = makeDecoder(
          parameters: const <String, dynamic>{
            'addr_width': 32,
            'data_width': '32',
            'check_alignment': true,
            'wait_state_threshold': 256,
          },
        );
        final lax = makeDecoder(
          parameters: const <String, dynamic>{
            'addr_width': 32,
            'data_width': '32',
            'check_alignment': false,
            'wait_state_threshold': 256,
          },
        );

        final strictTx = strict.decode(0, 25, query, cq);
        final laxTx = lax.decode(0, 25, query, cq);

        final strictHasViol = strictTx.any(
          (t) => t.errorMessage?.contains('Misaligned') ?? false,
        );
        final laxHasViol = laxTx.any(
          (t) => t.errorMessage?.contains('Misaligned') ?? false,
        );

        expect(strictHasViol, isTrue);
        expect(
          laxHasViol,
          isFalse,
          reason:
              'lax instance must independently honor its own '
              'check_alignment=false',
        );
      });
    });

    // ── optional binding presence ─────────────────────────────────────────────

    group('optional bindings', () {
      test('hprot and hmastlock fields are absent when unbound', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [(0, bv(0, 32)), (2, bv(0x100, 32)), (12, bv(0, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0xAA, 32))],
        };
        final txs = makeDecoder().decode(
          0,
          25,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs, isNotEmpty);
        final fields = txs.first.fields;
        expect(fields.containsKey('locked'), isFalse);
        expect(fields.containsKey('hprot'), isFalse);
      });

      test('hprot and hmastlock fields appear when bound', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [(0, bv(0, 32)), (2, bv(0x100, 32)), (12, bv(0, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0xAA, 32))],
          'hprot': [(0, bv(0, 4)), (2, bv(0xB, 4))], // cacheable+priv+data
          'hmastlock': [(0, '0'), (2, '1')],
        };
        final txs = makeDecoder(
          bindings: _bindingsWithProtLock,
        ).decode(0, 25, makeQuery(changes), makeChangesQuery(changes));
        expect(txs, isNotEmpty);
        final fields = txs.first.fields;
        expect(fields['locked'], '1');
        expect(fields['hprot'], '0xB');
        expect(fields['hprot_cacheable'], '1');
        expect(fields['hprot_data_or_instr'], 'data');
      });
    });

    // ── reset behavior ────────────────────────────────────────────────────────

    group('reset', () {
      test('mid-burst reset emits the parent record and starts clean', () {
        // Open INCR4 at 0x100, beat 1 lands, then reset at edge 3,
        // verify burst parent is emitted and a fresh transfer can begin.
        final changes = <String, List<(int, String)>>{
          'hclk': [
            (5, '1'),
            (10, '0'),
            (15, '1'),
            (20, '0'),
            (25, '1'),
            (30, '0'),
            (35, '1'),
            (40, '0'),
            (45, '1'),
            (50, '0'),
          ],
          'hresetn': [(0, '1'), (22, '0'), (32, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [
            (0, bv(0, 2)),
            (2, bv(2, 2)),
            (12, bv(3, 2)),
            (32, bv(0, 2)),
            (32, bv(2, 2)),
            (42, bv(0, 2)),
          ],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(3, 3)), (32, bv(0, 3))], // INCR4 then SINGLE
          'haddr': [
            (0, bv(0, 32)),
            (2, bv(0x100, 32)),
            (12, bv(0x104, 32)),
            (32, bv(0x500, 32)),
            (42, bv(0, 32)),
          ],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0x10, 32)), (42, bv(0x55, 32))],
        };

        final txs = makeDecoder().decode(
          0,
          50,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        // Should contain a burst-parent record from the aborted burst.
        expect(
          txs.any((t) => t.fields['type'] == 'Burst'),
          isTrue,
          reason: 'reset mid-burst should still flush the parent record',
        );

        // And a SINGLE transfer at 0x500 after reset.
        expect(
          txs.any((t) => t.fields['address'] == '0x00000500'),
          isTrue,
          reason: 'a fresh transfer after reset should decode normally',
        );
      });
    });

    // ── label and field shape ─────────────────────────────────────────────────

    group('label and field shape', () {
      test('SINGLE OKAY read label matches "R 0xADDR → 0xDATA"', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [(0, bv(0, 32)), (2, bv(0x40, 32)), (12, bv(0, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0xC0FFEE, 32))],
        };
        final txs = makeDecoder().decode(
          0,
          25,
          makeQuery(changes),
          makeChangesQuery(changes),
        );
        expect(txs.length, 1);
        expect(txs.first.label, 'R 0x00000040 → 0x00C0FFEE');
        expect(txs.first.fields['type'], 'Read');
        expect(txs.first.fields['response'], 'OKAY');
      });
    });

    // ── inline behavioral coverage (drives decoder directly) ──────────────────
    // The fixture-loading tests above verify JSON structure; this group drives
    // the decoder inline so the coverage tool sees the actual decode paths.

    group('wait-state warning (violation 8)', () {
      test('fires when HREADY held low beyond threshold', () {
        // Use threshold=2; drive 3 consecutive HREADY-low cycles so the
        // warning fires on the third cycle.
        final changes = <String, List<(int, String)>>{
          'hclk': [
            (5, '1'),
            (10, '0'),
            (15, '1'),
            (20, '0'),
            (25, '1'),
            (30, '0'),
            (35, '1'),
            (40, '0'),
          ],
          'hresetn': [(0, '1')],
          // HREADY=0 for cycles at edges 5, 15, 25 then =1 at 35.
          'hready': [(0, '0'), (32, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (38, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [(0, bv(0, 32)), (2, bv(0x100, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (35, bv(0xABCD, 32))],
        };

        final txs = makeDecoder(
          parameters: {..._defaultParams, 'wait_state_threshold': 2},
        ).decode(0, 40, makeQuery(changes), makeChangesQuery(changes));

        expect(
          txs.any(
            (t) =>
                t.label == 'AHB-Lite Warning' &&
                (t.errorMessage?.contains('HREADY held low') ?? false),
          ),
          isTrue,
          reason: 'violation 8 warning must appear when threshold exceeded',
        );
      });
    });

    group('WRAP8 and INCR8 burst types', () {
      // These tests drive the decoder with large burst types to cover the
      // _burstName switch cases, _burstBeatCount, and _expectedNextAddr
      // wrap-address path that existing fixture-loading tests do not reach.

      test('WRAP8 burst: beat label contains WRAP8, wrap address correct', () {
        // Two beats of a WRAP8 burst starting at 0x200.
        // Second beat drives SEQ with the correct wrap-next address (0x204)
        // so _expectedNextAddr is exercised without triggering violation 4.
        final changes = <String, List<(int, String)>>{
          'hclk': [
            (5, '1'),
            (10, '0'),
            (15, '1'),
            (20, '0'),
            (25, '1'),
            (30, '0'),
          ],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          // NONSEQ at edge 5, SEQ at edge 15, IDLE at edge 25.
          'htrans': [
            (0, bv(0, 2)),
            (2, bv(2, 2)),
            (12, bv(3, 2)),
            (22, bv(0, 2)),
          ],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))], // 32-bit, stride = 4
          'hburst': [(0, bv(4, 3))], // WRAP8 = 0x4
          'haddr': [
            (0, bv(0, 32)),
            (2, bv(0x200, 32)), // beat 1 address (NONSEQ)
            (12, bv(0x204, 32)), // beat 2 address (SEQ, correct wrap-next)
          ],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [
            (0, bv(0, 32)),
            (12, bv(0xAA, 32)),
            (22, bv(0xBB, 32)),
          ],
        };

        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        // At least one beat label must reference WRAP8.
        expect(
          txs.any((t) => t.label.contains('WRAP8')),
          isTrue,
          reason: 'beat or burst parent label must contain WRAP8',
        );
        // No spurious violation-4 — the address was correct.
        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains('does not match expected next beat') ??
                false,
          ),
          isFalse,
          reason: 'correct WRAP8 address must not trigger violation 4',
        );
      });

      test('INCR8 burst: beat label contains INCR8', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(5, 3))], // INCR8 = 0x5
          'haddr': [(0, bv(0, 32)), (2, bv(0x300, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0xCC, 32))],
        };

        final txs = makeDecoder().decode(
          0,
          20,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        expect(txs.any((t) => t.label.contains('INCR8')), isTrue);
      });
    });

    group('inline violation paths', () {
      // The fixture-loading tests check JSON structure but do not drive the
      // decoder. These inline tests directly exercise the violation branches.

      test('violation 1 — BUSY without active multi-beat burst', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          // IDLE → BUSY (no active burst).
          'htrans': [(0, bv(0, 2)), (2, bv(1, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [(0, bv(0x100, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32))],
        };

        final txs = makeDecoder().decode(
          0,
          20,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains('HTRANS=BUSY without an active') ??
                false,
          ),
          isTrue,
        );
      });

      test('violation 2 — SEQ without preceding NONSEQ', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          // SEQ with no preceding NONSEQ.
          'htrans': [(0, bv(0, 2)), (2, bv(3, 2)), (12, bv(0, 2))],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(3, 3))], // INCR4 (so SEQ is plausible)
          'haddr': [(0, bv(0x100, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32))],
        };

        final txs = makeDecoder().decode(
          0,
          20,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains('without a preceding NONSEQ') ?? false,
          ),
          isTrue,
        );
      });

      test('violation 3 — HBURST changed mid-burst', () {
        final changes = <String, List<(int, String)>>{
          'hclk': [
            (5, '1'),
            (10, '0'),
            (15, '1'),
            (20, '0'),
            (25, '1'),
            (30, '0'),
          ],
          'hresetn': [(0, '1')],
          'hready': [(0, '1')],
          'hresp': [(0, '0')],
          // NONSEQ then SEQ (burst type changes).
          'htrans': [
            (0, bv(0, 2)),
            (2, bv(2, 2)),
            (12, bv(3, 2)),
            (22, bv(0, 2)),
          ],
          'hwrite': [(0, '0')],
          'hsize': [(0, bv(2, 3))],
          // NONSEQ with INCR4, SEQ with INCR8 (violation: HBURST changed).
          'hburst': [(0, bv(3, 3)), (12, bv(5, 3))],
          'haddr': [(0, bv(0, 32)), (2, bv(0x100, 32)), (12, bv(0x104, 32))],
          'hwdata': [(0, bv(0, 32))],
          'hrdata': [(0, bv(0, 32)), (12, bv(0x11, 32)), (22, bv(0x22, 32))],
        };

        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        expect(
          txs.any(
            (t) =>
                t.errorMessage?.contains('HBURST changed mid-burst') ?? false,
          ),
          isTrue,
        );
      });

      test(
        'violation 4 — HADDR wrong for INCR4 (covers non-wrap _expectedNextAddr)',
        () {
          final changes = <String, List<(int, String)>>{
            'hclk': [
              (5, '1'),
              (10, '0'),
              (15, '1'),
              (20, '0'),
              (25, '1'),
              (30, '0'),
            ],
            'hresetn': [(0, '1')],
            'hready': [(0, '1')],
            'hresp': [(0, '0')],
            'htrans': [
              (0, bv(0, 2)),
              (2, bv(2, 2)),
              (12, bv(3, 2)),
              (22, bv(0, 2)),
            ],
            'hwrite': [(0, '0')],
            'hsize': [(0, bv(2, 3))], // 32-bit, stride = 4
            'hburst': [(0, bv(3, 3))], // INCR4
            // Wrong next address: should be 0x104 but is 0x108 (gap of 8 bytes).
            'haddr': [(0, bv(0, 32)), (2, bv(0x100, 32)), (12, bv(0x108, 32))],
            'hwdata': [(0, bv(0, 32))],
            'hrdata': [(0, bv(0, 32)), (12, bv(0x11, 32)), (22, bv(0x22, 32))],
          };

          final txs = makeDecoder().decode(
            0,
            30,
            makeQuery(changes),
            makeChangesQuery(changes),
          );

          expect(
            txs.any(
              (t) =>
                  t.errorMessage?.contains(
                    'does not match expected next beat',
                  ) ??
                  false,
            ),
            isTrue,
          );
        },
      );

      test(
        'violation 7 — single-cycle ERROR response (no two-cycle handshake)',
        () {
          final changes = <String, List<(int, String)>>{
            'hclk': [(5, '1'), (10, '0'), (15, '1'), (20, '0')],
            'hresetn': [(0, '1')],
            // HREADY=1 + HRESP=1 on the FIRST data cycle → violation 7.
            'hready': [(0, '1')],
            'hresp': [(0, '0'), (12, '1')],
            'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (12, bv(0, 2))],
            'hwrite': [(0, '0')],
            'hsize': [(0, bv(2, 3))],
            'hburst': [(0, bv(0, 3))],
            'haddr': [(0, bv(0, 32)), (2, bv(0x100, 32))],
            'hwdata': [(0, bv(0, 32))],
            'hrdata': [(0, bv(0, 32)), (12, bv(0xBAD, 32))],
          };

          final txs = makeDecoder().decode(
            0,
            20,
            makeQuery(changes),
            makeChangesQuery(changes),
          );

          expect(txs.length, 1);
          expect(txs.first.isError, isTrue);
          expect(
            txs.first.errorMessage?.contains('without two-cycle handshake') ??
                false,
            isTrue,
          );
        },
      );

      test('write with two-cycle ERROR: label W addr = data [ERROR], '
          'no violation 7', () {
        // First data cycle: HREADY=0, HRESP=1 (phase-1 of two-cycle).
        // Second data cycle: HREADY=1, HRESP=1 (completes cleanly).
        final changes = <String, List<(int, String)>>{
          'hclk': [
            (5, '1'),
            (10, '0'),
            (15, '1'),
            (20, '0'),
            (25, '1'),
            (30, '0'),
          ],
          'hresetn': [(0, '1')],
          'hready': [(0, '1'), (12, '0'), (22, '1')],
          'hresp': [(0, '0'), (12, '1')],
          'htrans': [(0, bv(0, 2)), (2, bv(2, 2)), (28, bv(0, 2))],
          'hwrite': [(0, '1')], // WRITE
          'hsize': [(0, bv(2, 3))],
          'hburst': [(0, bv(0, 3))],
          'haddr': [(0, bv(0, 32)), (2, bv(0x100, 32))],
          'hwdata': [(0, bv(0, 32)), (15, bv(0xDEAD, 32))],
          'hrdata': [(0, bv(0, 32))],
        };

        final txs = makeDecoder().decode(
          0,
          30,
          makeQuery(changes),
          makeChangesQuery(changes),
        );

        expect(txs.length, 1);
        final tx = txs.first;
        expect(tx.label, contains('W'));
        expect(tx.label, contains('[ERROR]'));
        // Two-cycle handshake satisfied: not violation 7.
        expect(tx.errorMessage, 'Response = ERROR');
      });
    });
  });

  // ── locale-sweep widget test ────────────────────────────────────────────────
  // Decoder strings (displayName, descriptions, parameter labels) are
  // hardcoded English in the DecoderDefinition, matching the precedent
  // set by SPI / I2C / UART / AXI4-Lite / APB / Wishbone. There is no
  // widget surface unique to this decoder, so the locale sweep that
  // CLAUDE.md prescribes for new widgets does not apply here. The
  // open-core decoder picker dialog already has its own locale sweep
  // covering the picker UI; this decoder shows up as just another row
  // in the AMBA category.
}
