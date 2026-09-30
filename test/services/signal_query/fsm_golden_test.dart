// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// FSM golden sweep (FSM robustness plan — Layer A).
//
// For every generated FSM fixture VCD, this opens the trace through the REAL
// wellen FFI parser, runs `FsmAnalysisService.buildModel` over the sole STATE
// register, and snapshot-compares the resulting `FsmModel` against the
// committed `<machine>.expected_fsm.json`. This is the only FSM test that
// exercises the full parse → analyze path; the rest use synthetic sources.
//
//   REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart
//
// regenerates the goldens against the live analyzer + parser. The VCDs
// themselves are produced by `dart run tool/generate_fsm_fixtures.dart`.
//
// The replay needs the native wellen library: it skips locally when the
// library is not built and fails in CI, which builds it first. The goldens'
// presence is guarded separately by
// `test/static/fsm_fixture_companion_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/signal_query/fsm_analysis_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

/// (expected state count, expected total transition count) per machine —
/// hand-verified anchors asserted in addition to the opaque snapshot diff.
const _anchors = <String, (int, int)>{
  'traffic_light': (3, 9),
  'onehot_8': (8, 8),
  'gray_counter_5bit': (32, 32),
  'glitchy_reset': (4, 3),
  // picorv32 cpu_state one-hot FSM: fetch/ld_rs1/ld_rs2/exec/shift/stmem/ldmem
  // (7 reachable states; trap not hit by the clean program). The boot `x` is
  // skipped, so the first fetch has no incoming transition → 22 entries − 1.
  'picorv32_state': (7, 21),
};

void main() {
  final regenerate = Platform.environment['REGENERATE'] == '1';
  final fixtures = _discover();

  group('FSM golden sweep — FsmModel from real-parser VCDs', () {
    test('generated corpus is non-empty', () {
      expect(
        fixtures,
        isNotEmpty,
        reason: 'run `dart run tool/generate_fsm_fixtures.dart`',
      );
    });

    if (!requireWellenFfiLibrary('FSM golden replay')) return;

    for (final f in fixtures) {
      test(f.name, () async {
        final provider = WellenProvider();
        await provider.openFile(f.vcd.path);
        try {
          final vars = provider.findVariables(const SignalFilter());
          // Pick the FSM register. A `<name>.fsm.json` may name the signal by
          // its full path (needed for multi-signal captured traces); a
          // single-signal generated VCD just uses its sole variable.
          final Variable v;
          if (f.config.existsSync()) {
            final spec =
                jsonDecode(f.config.readAsStringSync()) as Map<String, dynamic>;
            final path = spec['signal'] as String;
            final byPath = {for (final x in vars) x.fullPath: x};
            final match = byPath[path];
            if (match == null) {
              fail('${f.name}: signal "$path" not found in the trace');
            }
            v = match;
          } else {
            expect(
              vars.length,
              1,
              reason:
                  '${f.name}: expected exactly one signal (or a '
                  '<name>.fsm.json naming the FSM register)',
            );
            v = vars.single;
          }
          await provider.loadSignal(v.signalRef);

          final model = const FsmAnalysisService().buildModel(
            signalRef: v.signalRef,
            signalPath: v.fullPath,
            source: provider,
            startTime: provider.startTime,
            endTime: provider.endTime + 1,
          );
          final actual = _serialize(model);

          if (regenerate) {
            final json =
                '${const JsonEncoder.withIndent('  ').convert(actual)}\n';
            // Write the golden next to the VCD in BOTH the test/ corpus and the
            // verification/ release-mirror so the two trees never drift (the
            // generator already mirrored the VCD into both).
            for (final golden in [f.golden, f.mirrorGolden]) {
              golden.writeAsStringSync(json);
              // REGENERATE is a developer escape hatch — surface the
              // overwritten path to stdout so the operator can review it.
              // ignore: avoid_print
              print('REGENERATE: wrote ${p.relative(golden.path)}');
            }
            return;
          }

          expect(
            f.golden.existsSync(),
            isTrue,
            reason:
                'missing ${p.basename(f.golden.path)} — '
                'run with REGENERATE=1 to (re)create it',
          );
          final expected = jsonDecode(f.golden.readAsStringSync());
          // Round-trip the live result through JSON so int/double and
          // List<int>/List<dynamic> normalise the same way the golden did.
          final normalized = jsonDecode(jsonEncode(actual));
          expect(
            normalized,
            expected,
            reason:
                '${f.name}: FsmModel differs from the committed golden '
                '(run REGENERATE=1 if this change is intended)',
          );

          // Hand-verified anchors — a second, human-checked guard so a silent
          // analyzer regression cannot quietly rewrite the snapshot.
          final anchor = _anchors[f.name];
          if (anchor != null) {
            expect(
              model.states.length,
              anchor.$1,
              reason: '${f.name}: state count',
            );
            expect(
              model.totalTransitionCount,
              anchor.$2,
              reason: '${f.name}: total transition count',
            );
          }
        } finally {
          provider.close();
        }
      });
    }
  });
}

// ── internals ────────────────────────────────────────────────────────────────

class _Fixture {
  _Fixture(this.name, this.vcd, this.golden, this.mirrorGolden, this.config);
  final String name;
  final File vcd;

  /// Golden next to the VCD in the `test/` corpus (the compared one).
  final File golden;

  /// Same golden in the `verification/` release mirror; written on REGENERATE
  /// so the two trees stay in lockstep.
  final File mirrorGolden;

  /// Optional `<name>.fsm.json` naming the FSM register's full path. Required
  /// for multi-signal captured traces; absent for single-signal generated VCDs.
  final File config;
}

List<_Fixture> _discover() {
  final root = Directory('test/fixtures/fsm');
  if (!root.existsSync()) return const [];
  final out = <_Fixture>[];
  for (final machine in root.listSync().whereType<Directory>()) {
    for (final tier in const ['generated', 'captured']) {
      final dir = Directory(p.join(machine.path, tier));
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        final base = _traceBase(file.path);
        if (base == null) continue; // not a trace file
        final goldenPath = '$base.expected_fsm.json';
        out.add(
          _Fixture(
            p.basename(base),
            file,
            File(goldenPath),
            File(
              goldenPath.replaceFirst(
                'test/fixtures/fsm',
                'verification/fixtures/fsm',
              ),
            ),
            File('$base.fsm.json'),
          ),
        );
      }
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// Strips a trace extension (`.vcd` / `.fst` / `.vcd.zst`); null if not a trace.
String? _traceBase(String path) {
  for (final ext in const ['.vcd.zst', '.vcd', '.fst']) {
    if (path.endsWith(ext)) {
      return path.substring(0, path.length - ext.length);
    }
  }
  return null;
}

Map<String, Object?> _serialize(FsmModel m) => {
  'signalPath': m.signalPath,
  'startTime': m.timeRange.start,
  'endTime': m.timeRange.end,
  'totalTransitionCount': m.totalTransitionCount,
  'states': [
    for (final s in m.states)
      {
        'id': s.id,
        'label': s.label,
        'entryCount': s.entryCount,
        'firstEntryTime': s.firstEntryTime,
      },
  ],
  'transitions': [
    for (final t in m.transitions)
      {
        'fromId': t.fromId,
        'toId': t.toId,
        'count': t.count,
        'times': t.times,
      },
  ],
};
