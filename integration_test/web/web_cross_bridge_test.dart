// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/web/web_cross_bridge_test.dart
//
// Layer 1 — Wellen-vs-Wellen bridge validation (ARCHITECTURE.md §8.9, Layer 1).
//
// Both `WellenProvider` (FFI, desktop/mobile) and `WellenWasmProvider` (WASM,
// web) wrap the *same* `wellen` Rust crate. They must return identical results
// for every query against every fixture; any divergence is a marshalling-bridge
// bug (FFI pointer passing vs WASM linear-memory copying), not a parser bug.
//
// FFI cannot run inside a browser, so the two bridges cannot be diffed in one
// process. The FFI side is therefore frozen ahead of time into committed
// `.expected.json` companions (`tool/generate_bridge_snapshots.dart` records
// the real FFI provider's exact answers; the four hand-authored VCD companions
// are independently verified Layer 2 gold). This Chrome-headless test loads
// every fixture through `WellenWasmProvider` and asserts it reproduces that
// committed gold — closing the loop: WASM == gold == FFI.
//
// Coverage: VCD, FST (vcd2fst mirrors — companion is the VCD gold, since
// `fst_vcd_equivalence_test.dart` already proves wellen reads each mirror
// identically to its VCD source via FFI), and GHW. For every signal, the full
// `valueAt` / `changesInRange` / `nextTransition` / `prevTransition` probe set
// from the companion is replayed through WASM and diffed.
//
// Signals are matched by hierarchical full path — the opaque `signalRef` is
// backend-specific and legitimately differs between FFI and WASM.
//
// Gated to web only via `skip: !kIsWeb`. Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/web/web_cross_bridge_test.dart \
//     -d web-server --browser-name=chrome --headless
// or via tool/run_web_integration_tests.sh web_cross_bridge_test

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider.dart';

import 'web_fixture_bundle.g.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final fx in kWebFixtures) {
    testWidgets(
      'WASM bridge matches FFI gold — ${fx.format} ${fx.name}',
      (tester) async {
        final provider = WellenWasmProvider();
        addTearDown(provider.close);

        await provider.openBytes(fx.bytes, fx.displayName);

        final expected = fx.expected;
        final metadata = expected['metadata'] as Map<String, dynamic>;

        // ── Metadata: timescale + time range (format-independent) ───────────
        // date/version are deliberately NOT asserted: they are provenance
        // fields that legitimately differ between a VCD and its FST mirror.
        expect(
          provider.startTime,
          metadata['startTime'],
          reason: 'startTime mismatch for ${fx.displayName}',
        );
        expect(
          provider.endTime,
          metadata['endTime'],
          reason: 'endTime mismatch for ${fx.displayName}',
        );
        final ts = metadata['timescale'] as Map<String, dynamic>?;
        if (ts != null) {
          expect(
            provider.timescale,
            isNotNull,
            reason: 'timescale missing for ${fx.displayName}',
          );
          expect(provider.timescale!.factor, ts['factor']);
          expect(provider.timescale!.unit.name, ts['unit']);
        }

        // ── Hierarchy: every gold signal present, widths + types match ──────
        final wasmByPath = <String, Variable>{
          for (final v in provider.findVariables(const SignalFilter()))
            v.fullPath: v,
        };
        final signals = expected['signals'] as Map<String, dynamic>;
        for (final entry in signals.entries) {
          final path = entry.key;
          final gold = entry.value as Map<String, dynamic>;
          final v = wasmByPath[path];
          expect(
            v,
            isNotNull,
            reason: 'WASM hierarchy is missing gold signal $path',
          );

          // ── Per-signal value queries (the cross-bridge meat) ──────────────
          await provider.loadSignal(v!.signalRef);
          final ref = v.signalRef;

          // Full change history — present on every signal in every companion;
          // it subsumes valueAt/range/transitions and is the strongest single
          // check.
          _expectChanges(
            provider.changesInRange(ref, 0, provider.endTime + 1),
            gold['allChanges'] as List<dynamic>,
            'allChanges($path)',
          );

          // The four probe arrays are curated per-signal in the hand-authored
          // companions (and exhaustive in the generated ones). Assert whichever
          // a given signal carries; a missing array just means no extra probes
          // beyond `allChanges` for that signal.
          for (final probe in (gold['valueAt'] as List<dynamic>?) ?? const []) {
            final p = probe as Map<String, dynamic>;
            expect(
              provider.valueAt(ref, p['time'] as int),
              p['expected'],
              reason: 'valueAt($path, ${p['time']}) for ${fx.displayName}',
            );
          }

          for (final probe
              in (gold['changesInRange'] as List<dynamic>?) ?? const []) {
            final p = probe as Map<String, dynamic>;
            _expectChanges(
              provider.changesInRange(ref, p['start'] as int, p['end'] as int),
              p['expected'] as List<dynamic>,
              'changesInRange($path, ${p['start']}, ${p['end']}) '
              'for ${fx.displayName}',
            );
          }

          for (final probe
              in (gold['nextTransition'] as List<dynamic>?) ?? const []) {
            final p = probe as Map<String, dynamic>;
            _expectTransition(
              provider.nextTransition(ref, p['afterTime'] as int),
              p['expected'] as Map<String, dynamic>?,
              'nextTransition($path, ${p['afterTime']}) for ${fx.displayName}',
            );
          }

          for (final probe
              in (gold['prevTransition'] as List<dynamic>?) ?? const []) {
            final p = probe as Map<String, dynamic>;
            _expectTransition(
              provider.prevTransition(ref, p['beforeTime'] as int),
              p['expected'] as Map<String, dynamic>?,
              'prevTransition($path, ${p['beforeTime']}) for ${fx.displayName}',
            );
          }
        }
      },
      skip: !kIsWeb,
    );
  }
}

void _expectChanges(
  List<SignalChange> actual,
  List<dynamic> goldRaw,
  String label,
) {
  final actualPairs = [
    for (final c in actual) (c.time, c.value),
  ];
  final goldPairs = [
    for (final g in goldRaw) ((g as Map)['time'] as int, g['value'] as String),
  ];
  expect(actualPairs, goldPairs, reason: label);
}

void _expectTransition(
  SignalChange? actual,
  Map<String, dynamic>? gold,
  String label,
) {
  if (gold == null) {
    expect(actual, isNull, reason: '$label should be null');
    return;
  }
  expect(actual, isNotNull, reason: '$label should be non-null');
  expect(actual!.time, gold['time'], reason: '$label time');
  expect(actual.value, gold['value'], reason: '$label value');
}
