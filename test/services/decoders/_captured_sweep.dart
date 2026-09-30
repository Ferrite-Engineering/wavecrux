// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shared captured-fixture sweep harness.
//
// Drives the standard `<decoder>/captured/` corpus convention against
// the WellenProvider FFI backend:
//
//   1. Discover every `<name>.fst` (or `.vcd` / `.vcd.zst`) in [fixturesDir].
//   2. Read sibling `<name>.fixture.json` for signal bindings + parameters.
//   3. Open the trace via WellenProvider, hand the per-binding change lists
//      to the decoder built by [build], and snapshot-compare the decoded
//      transactions against `<name>.expected_transactions.json`.
//
// `REGENERATE=1` in the environment (re)writes snapshots instead of
// asserting against them.
//
// Per-decoder sweep tests collapse to a ~6-line main(); see e.g.
// `uart_captured_fixtures_test.dart`. The harness preserves the historical
// per-fixture assertion shape so failures still point at startTime / fields
// / errorMessage individually, not a single opaque diff.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

/// Builds a [ProtocolDecoder] for a given [DecoderConfig]. The factory
/// pattern keeps the per-decoder sweep test free of any imports beyond
/// the decoder class itself.
typedef DecoderFactory = ProtocolDecoder Function(DecoderConfig config);

/// Registers the standard captured-fixture sweep for [decoderId].
///
/// [sharedDirectory] controls how a multi-decoder `captured/` directory
/// (e.g. the Pro `ethernet/captured/` corpus that hosts MII / RMII /
/// GMII / RGMII / AXIS side-by-side) is filtered. When `true`, fixtures
/// whose `fixture.json` declares a different decoder are silently
/// skipped at discovery time. When `false` (the default — single-decoder
/// directories like `uart/captured/`), discovery includes every fixture
/// file in the directory and the per-fixture test asserts the decoder
/// field matches, so a fixture dropped into the wrong directory fails
/// loudly instead of silently disappearing.
void registerCapturedSweep({
  required String decoderId,
  required String groupName,
  required String fixturesDir,
  required DecoderFactory build,
  bool sharedDirectory = false,
}) {
  final regenerate = Platform.environment['REGENERATE'] == '1';
  final fixtures = _discoverFixtures(
    fixturesDir,
    decoderId: decoderId,
    filterByDecoderField: sharedDirectory,
  );

  group('$groupName — captured fixtures', () {
    test('at least one captured fixture is present', () {
      expect(
        fixtures,
        isNotEmpty,
        reason: sharedDirectory
            ? 'expected at least one .fst/.vcd/.vcd.zst under $fixturesDir/ '
                  'whose sibling <name>.fixture.json declares '
                  '"decoder": "$decoderId"'
            : 'expected at least one .fst/.vcd/.vcd.zst under $fixturesDir/',
      );
    });

    test('decoderId matches the decoder definition id', () {
      // The sweep builds the decoder directly (bypassing DecoderRegistry), so
      // a fixture.json whose "decoder" field is not the real registered id
      // would pass this unit sweep yet decode to nothing in the integration
      // path (which resolves the decoder by id via the registry — a missing
      // factory is silently skipped). Tie the two together: the sweep's
      // decoderId — and every fixture.json "decoder" field, asserted equal to
      // it below — must equal the decoder definition's own id.
      final definitionId = build(
        const DecoderConfig(signalBindings: {}),
      ).definition.id;
      expect(
        decoderId,
        definitionId,
        reason:
            'sweep decoderId "$decoderId" must equal the decoder '
            'definition id "$definitionId"',
      );
    });

    // Each fixture case below parses its trace through the real provider.
    if (!requireWellenFfiLibrary('$groupName captured fixtures')) return;

    for (final fixture in fixtures) {
      test(fixture.name, () async {
        if (!sharedDirectory) {
          expect(
            fixture.fixtureJson.existsSync(),
            isTrue,
            reason:
                'missing sibling '
                '${p.basename(fixture.fixtureJson.path)}',
          );
        }
        if (!regenerate) {
          expect(
            fixture.expectedJson.existsSync(),
            isTrue,
            reason:
                'missing sibling '
                '${p.basename(fixture.expectedJson.path)} — '
                'run with REGENERATE=1 to (re)create it',
          );
        }

        final spec =
            jsonDecode(fixture.fixtureJson.readAsStringSync())
                as Map<String, dynamic>;
        if (!sharedDirectory) {
          expect(
            spec['decoder'],
            decoderId,
            reason: 'fixture.json decoder field must be "$decoderId"',
          );
        }
        final bindings = (spec['signal_bindings'] as Map<String, dynamic>)
            .cast<String, String>();
        final parameters = Map<String, Object?>.from(spec['parameters'] as Map);

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

          final decoder = build(
            DecoderConfig(
              signalBindings: bindings,
              parameters: parameters,
            ),
          );
          final txs = decoder.decode(
            0,
            provider.endTime + 1,
            _makeQuery(changes),
            _makeChangesQuery(changes),
          );
          final actual = txs.map(_serialize).toList();

          if (regenerate) {
            const encoder = JsonEncoder.withIndent('  ');
            fixture.expectedJson.writeAsStringSync(
              '${encoder.convert(actual)}\n',
            );
            // REGENERATE mode is a developer escape hatch — surface the
            // regenerated snapshot path to stdout so the operator can
            // see what was overwritten before committing.
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

List<_Fixture> _discoverFixtures(
  String dir, {
  required String decoderId,
  required bool filterByDecoderField,
}) {
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
    final fixtureJson = File('$base.fixture.json');
    if (filterByDecoderField) {
      if (!fixtureJson.existsSync()) continue;
      final spec =
          jsonDecode(fixtureJson.readAsStringSync()) as Map<String, dynamic>;
      if (spec['decoder'] != decoderId) continue;
    }
    out.add(
      _Fixture(
        name: p.basename(base),
        fst: entity,
        fixtureJson: fixtureJson,
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

// The per-binding change lists are produced by [WellenProvider.changesInRange]
// and are therefore sorted ascending by time. Both query closures binary-search
// that order rather than linear-scanning it.
//
// This is not a micro-optimization — it is load-bearing. A decoder's decode()
// calls the value query once per clock edge per channel, so a linear scan makes
// the whole pass O(edges × changes). The largest captured fixtures push that to
// tens of billions of steps (e.g. axi4_full/forencich_axi_register: ~816k clock
// edges over ~600k hot-signal transitions ≈ 4×10^10 steps), which completes in
// seconds on a fast machine but blows past the per-test timeout on slower CI /
// WSL hosts — surfacing as a platform-specific "hang" even though the decoded
// result is identical. Binary search makes it O(edges × log changes) and removes
// the host-speed sensitivity. Results are byte-for-byte identical to the linear
// scan, so the snapshots are unaffected.

/// Index of the last change with `time <= [time]`, or -1 if none. Binary search
/// over the ascending-by-time [list].
int _lastAtOrBefore(List<(int, String)> list, int time) {
  var lo = 0;
  var hi = list.length - 1;
  var result = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].$1 <= time) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return result;
}

/// Index of the first change with `time >= [time]` (lower bound), or
/// `list.length` if none. Binary search over the ascending-by-time [list].
int _firstAtOrAfter(List<(int, String)> list, int time) {
  var lo = 0;
  var hi = list.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].$1 < time) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

SignalValueQuery _makeQuery(Map<String, List<(int, String)>> changes) {
  return (signal, time) {
    final list = changes[signal] ?? const [];
    final idx = _lastAtOrBefore(list, time);
    return idx >= 0 ? list[idx].$2 : null;
  };
}

SignalChangesQuery _makeChangesQuery(
  Map<String, List<(int, String)>> changes,
) {
  return (signal, start, end) {
    final list = changes[signal] ?? const [];
    final lo = _firstAtOrAfter(list, start);
    final hi = _firstAtOrAfter(list, end);
    return list.sublist(lo, hi);
  };
}
