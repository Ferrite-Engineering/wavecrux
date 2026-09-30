// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Captured-fixture sweep for [SpiFlashDecoder], which is a stacked decoder
// on top of [SpiDecoder]. The shared `_captured_sweep.dart` harness drives
// single-pass decoders; stacked decoders need to run their parent first,
// so this test file inlines the two-pass plumbing while keeping the rest of
// the discovery / snapshot-compare contract identical.
//
// Every `<name>.fst` in `test/fixtures/protocol/spi_flash/captured/` is
// discovered and decoded against the WellenProvider FFI backend, with
// per-fixture configuration read from a sibling `<name>.fixture.json`.
// The `fixture.json` carries the SPI parent config under a `"parent"`
// block (the parent reuses the same signal bindings). Decoded
// SPI-Flash transactions are snapshot-matched against
// `<name>.expected_transactions.json`.
//
// Adding a captured fixture is purely additive — drop in the three sibling
// files and regenerate the snapshot:
//
//   REGENERATE=1 flutter test test/services/decoders/spi_flash_captured_fixtures_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

void main() {
  final regenerate = Platform.environment['REGENERATE'] == '1';
  const fixturesDir = 'test/fixtures/protocol/spi_flash/captured';
  final fixtures = _discoverFixtures(fixturesDir);

  group('SpiFlashDecoder — captured fixtures', () {
    test('at least one captured fixture is present', () {
      expect(
        fixtures,
        isNotEmpty,
        reason:
            'expected at least one .fst/.vcd/.vcd.zst under '
            '$fixturesDir/',
      );
    });

    // Each fixture case below parses its trace through the real provider.
    if (!requireWellenFfiLibrary('SpiFlashDecoder captured fixtures')) return;

    for (final fixture in fixtures) {
      test(fixture.name, () async {
        if (!regenerate) {
          expect(
            fixture.expectedJson.existsSync(),
            isTrue,
            reason:
                'missing sibling '
                '${p.basename(fixture.expectedJson.path)} — run with '
                'REGENERATE=1 to (re)create it',
          );
        }

        final spec =
            jsonDecode(fixture.fixtureJson.readAsStringSync())
                as Map<String, dynamic>;
        expect(
          spec['decoder'],
          'spi_flash',
          reason: 'fixture.json decoder field must be "spi_flash"',
        );
        final bindings = (spec['signal_bindings'] as Map<String, dynamic>)
            .cast<String, String>();
        final parameters = Map<String, Object?>.from(spec['parameters'] as Map);
        final parentSpec = (spec['parent'] as Map<String, dynamic>?) ?? {};
        expect(
          parentSpec['decoder'],
          'spi',
          reason: 'fixture.json parent.decoder must be "spi"',
        );
        final parentParams = Map<String, Object?>.from(
          parentSpec['parameters'] as Map,
        );

        final provider = WellenProvider();
        await provider.openFile(fixture.fst.path);
        try {
          final variables = provider.findVariables(const SignalFilter());
          final byPath = {for (final v in variables) v.fullPath: v};
          final changes = <String, List<(int, String)>>{};
          for (final entry in bindings.entries) {
            final variable = byPath[entry.value];
            expect(
              variable,
              isNotNull,
              reason:
                  'fixture ${fixture.name}: binding ${entry.key} → '
                  '${entry.value} does not match any signal in the trace',
            );
            await provider.loadSignal(variable!.signalRef);
            changes[entry.key] = provider
                .changesInRange(variable.signalRef, 0, provider.endTime + 1)
                .map((c) => (c.time, c.value))
                .toList();
          }

          final query = _makeQuery(changes);
          final changesQuery = _makeChangesQuery(changes);

          // Run parent (SPI) first.
          final parent = SpiDecoder(
            DecoderConfig(
              signalBindings: bindings,
              parameters: parentParams,
            ),
          );
          final parentTxs = parent.decode(
            0,
            provider.endTime + 1,
            query,
            changesQuery,
          );

          // Stack SPI-Flash on top of the parent transactions.
          final flash = SpiFlashDecoder(
            DecoderConfig(
              signalBindings: bindings,
              parameters: parameters,
            ),
          );
          final txs = flash.decodeStacked(
            parentTxs,
            0,
            provider.endTime + 1,
            query,
            changesQuery,
          );
          final actual = txs.map(_serialize).toList();

          if (regenerate) {
            const encoder = JsonEncoder.withIndent('  ');
            fixture.expectedJson.writeAsStringSync(
              '${encoder.convert(actual)}\n',
            );
            // REGENERATE mode is a developer escape hatch — surface the
            // regenerated snapshot path to stdout so the operator can see
            // what was overwritten before committing.
            // ignore: avoid_print
            print(
              'REGENERATE: wrote ${actual.length} transactions to '
              '${p.relative(fixture.expectedJson.path)}',
            );
            return;
          }

          final expected =
              (jsonDecode(fixture.expectedJson.readAsStringSync())
                      as List<dynamic>)
                  .cast<Map<String, dynamic>>();
          expect(
            actual.length,
            expected.length,
            reason: 'transaction count differs from snapshot',
          );
          for (var i = 0; i < expected.length; i++) {
            final e = expected[i];
            final a = actual[i];
            expect(a['startTime'], e['startTime'], reason: 'tx[$i] startTime');
            expect(a['endTime'], e['endTime'], reason: 'tx[$i] endTime');
            expect(a['label'], e['label'], reason: 'tx[$i] label');
            expect(a['isError'], e['isError'], reason: 'tx[$i] isError');
            expect(
              a['errorMessage'],
              e['errorMessage'],
              reason: 'tx[$i] errorMessage',
            );
            expect(a['fields'], e['fields'], reason: 'tx[$i] fields');
          }
        } finally {
          provider.close();
        }
      });
    }
  });
}

// ── internals ──────────────────────────────────────────────────────────────

class _Fixture {
  _Fixture({
    required this.name,
    required this.fst,
    required this.fixtureJson,
    required this.expectedJson,
  });

  final String name;
  final File fst;
  final File fixtureJson;
  final File expectedJson;
}

List<_Fixture> _discoverFixtures(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) return const [];
  final out = <_Fixture>[];
  for (final entity in root.listSync()) {
    if (entity is! File) continue;
    final path = entity.path;
    if (!(path.endsWith('.fst') ||
        path.endsWith('.vcd') ||
        path.endsWith('.vcd.zst'))) {
      continue;
    }
    final base = path
        .replaceFirst(RegExp(r'\.vcd\.zst$'), '')
        .replaceFirst(RegExp(r'\.(vcd|fst)$'), '');
    out.add(
      _Fixture(
        name: p.basename(base),
        fst: entity,
        fixtureJson: File('$base.fixture.json'),
        expectedJson: File('$base.expected_transactions.json'),
      ),
    );
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

Map<String, dynamic> _serialize(DecodedTransaction tx) => {
  'startTime': tx.startTime,
  'endTime': tx.endTime,
  'label': tx.label,
  'fields': tx.fields,
  'isError': tx.isError,
  'errorMessage': tx.errorMessage,
};

SignalValueQuery _makeQuery(Map<String, List<(int, String)>> changes) {
  return (signal, time) {
    final list = changes[signal] ?? const [];
    String? held;
    for (final (t, v) in list) {
      if (t > time) break;
      held = v;
    }
    return held;
  };
}

SignalChangesQuery _makeChangesQuery(
  Map<String, List<(int, String)>> changes,
) {
  return (signal, start, end) {
    final list = changes[signal] ?? const [];
    return [
      for (final e in list)
        if (e.$1 >= start && e.$1 < end) e,
    ];
  };
}
