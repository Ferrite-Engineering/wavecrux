// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/vcd_writer/vcd_writer_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _service = VcdWriterService();
const _fixturePath = 'test/fixtures/vcd/scalar_basics.vcd';

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_vcd_test_');
  final path = '${dir.path}/export.vcd';
  try {
    return await fn(path);
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  // ── generateIdCode ─────────────────────────────────────────────────────────

  group('VcdWriterService.generateIdCode', () {
    test('index 0 → "!"', () {
      expect(VcdWriterService.generateIdCode(0), '!');
    });

    test('index 93 → "~" (last single-char code)', () {
      expect(VcdWriterService.generateIdCode(93), '~');
    });

    test('index 94 → two-char code (base-94 overflow)', () {
      final code = VcdWriterService.generateIdCode(94);
      expect(code.length, 2);
    });

    test('all single-char codes are unique', () {
      final codes = List.generate(94, VcdWriterService.generateIdCode);
      expect(codes.toSet().length, 94);
    });

    test('multi-char codes are unique across a range', () {
      final codes = List.generate(200, VcdWriterService.generateIdCode);
      expect(codes.toSet().length, 200);
    });
  });

  if (requireWellenFfiLibrary('VCD writer over scalar_basics.vcd')) {
    // ── generateVcd — empty config ───────────────────────────────────────────

    group('VcdWriterService.generateVcd', () {
      late WellenProvider source;

      setUp(() async {
        source = WellenProvider();
        await source.openFile(_fixturePath);
        final vars = source.findVariables(const SignalFilter());
        for (final v in vars) {
          await source.loadSignal(v.signalRef);
        }
      });

      tearDown(() => source.close());

      test('returns empty string for empty signal list', () {
        final config = VcdExportConfig(
          signalRefs: const [],
          signalMap: const {},
          startTime: source.startTime,
          endTime: source.endTime,
        );
        expect(_service.generateVcd(source, config), isEmpty);
      });

      test('output contains required VCD keywords', () {
        final vars = source.findVariables(const SignalFilter());
        final config = VcdExportConfig(
          signalRefs: vars.map((v) => v.signalRef).toList(),
          signalMap: {for (final v in vars) v.signalRef: v},
          startTime: source.startTime,
          endTime: source.endTime,
        );
        final vcd = _service.generateVcd(source, config);
        expect(vcd, contains(r'$timescale'));
        expect(vcd, contains(r'$var'));
        expect(vcd, contains(r'$enddefinitions $end'));
        expect(vcd, contains(r'$dumpvars'));
      });

      test('output contains signal names from fixture', () {
        final vars = source.findVariables(const SignalFilter());
        final config = VcdExportConfig(
          signalRefs: vars.map((v) => v.signalRef).toList(),
          signalMap: {for (final v in vars) v.signalRef: v},
          startTime: source.startTime,
          endTime: source.endTime,
        );
        final vcd = _service.generateVcd(source, config);
        expect(vcd, contains('clk'));
        expect(vcd, contains('rst'));
        expect(vcd, contains('data'));
      });

      test('scope block wraps signals in module', () {
        final vars = source.findVariables(const SignalFilter());
        final config = VcdExportConfig(
          signalRefs: vars.map((v) => v.signalRef).toList(),
          signalMap: {for (final v in vars) v.signalRef: v},
          startTime: source.startTime,
          endTime: source.endTime,
        );
        final vcd = _service.generateVcd(source, config);
        expect(vcd, contains(r'$scope module'));
        expect(vcd, contains(r'$upscope $end'));
      });

      test('time markers are present in output', () {
        final vars = source.findVariables(const SignalFilter());
        final config = VcdExportConfig(
          signalRefs: vars.map((v) => v.signalRef).toList(),
          signalMap: {for (final v in vars) v.signalRef: v},
          startTime: source.startTime,
          endTime: source.endTime,
        );
        final vcd = _service.generateVcd(source, config);
        expect(vcd, contains('#0'));
        expect(vcd, contains('#10'));
      });
    });

    // ── round-trip ───────────────────────────────────────────────────────────

    group('VcdWriterService round-trip', () {
      late WellenProvider source;
      late List<Variable> vars;

      setUp(() async {
        source = WellenProvider();
        await source.openFile(_fixturePath);
        vars = source.findVariables(const SignalFilter());
        for (final v in vars) {
          await source.loadSignal(v.signalRef);
        }
      });

      tearDown(() => source.close());

      test(
        'all values at transition times survive parse→export→reparse',
        () async {
          await _withTempFile((path) async {
            final config = VcdExportConfig(
              signalRefs: vars.map((v) => v.signalRef).toList(),
              signalMap: {for (final v in vars) v.signalRef: v},
              startTime: source.startTime,
              endTime: source.endTime,
            );
            await _service.writeVcd(source, config, path);

            // Re-parse the exported VCD.
            final reparsed = WellenProvider();
            await reparsed.openFile(path);
            final reparsedVars = reparsed.findVariables(const SignalFilter());
            for (final v in reparsedVars) {
              await reparsed.loadSignal(v.signalRef);
            }

            // Build a name→ref map for the reparsed file.
            final nameToRef = {
              for (final v in reparsedVars) v.name: v.signalRef,
            };

            // For each original signal, verify values at each transition
            // time match.
            for (final v in vars) {
              final reparsedRef = nameToRef[v.name];
              if (reparsedRef == null) continue;

              final changes = source.changesInRange(
                v.signalRef,
                source.startTime,
                source.endTime + 1,
              );
              for (final change in changes) {
                final original = source.valueAt(v.signalRef, change.time);
                final reparsedVal = reparsed.valueAt(reparsedRef, change.time);
                expect(
                  reparsedVal,
                  original,
                  reason: 'signal ${v.name} at t=${change.time}',
                );
              }
            }

            reparsed.close();
          });
        },
      );

      test('writeVcd creates file at given path', () async {
        await _withTempFile((path) async {
          final config = VcdExportConfig(
            signalRefs: vars.map((v) => v.signalRef).toList(),
            signalMap: {for (final v in vars) v.signalRef: v},
            startTime: source.startTime,
            endTime: source.endTime,
          );
          await _service.writeVcd(source, config, path);
          expect(File(path).existsSync(), isTrue);
          expect(File(path).lengthSync(), greaterThan(0));
        });
      });

      test(
        'writeVcd throws VcdWriteException on bad path',
        () async {
          final config = VcdExportConfig(
            signalRefs: vars.map((v) => v.signalRef).toList(),
            signalMap: {for (final v in vars) v.signalRef: v},
            startTime: source.startTime,
            endTime: source.endTime,
          );
          expect(
            () =>
                _service.writeVcd(source, config, '/no_permission/export.vcd'),
            throwsA(isA<VcdWriteException>()),
          );
        },
        skip: Platform.isWindows,
      );

      test('visible time range exports only the specified window', () async {
        await _withTempFile((path) async {
          const rangeStart = 30;
          const rangeEnd = 60;
          final config = VcdExportConfig(
            signalRefs: vars.map((v) => v.signalRef).toList(),
            signalMap: {for (final v in vars) v.signalRef: v},
            startTime: rangeStart,
            endTime: rangeEnd,
          );
          await _service.writeVcd(source, config, path);
          final content = await File(path).readAsString();
          expect(content, contains('#30'));
          expect(content, isNot(contains('#10')));
          expect(content, isNot(contains('#100')));
        });
      });
    });
  }

  // ── VcdExportConfig.fromSignalGroup ────────────────────────────────────────

  group('VcdExportConfig.fromSignalGroup', () {
    test('collects signal refs from flat group', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: 'top.clk', displayName: 'clk'),
          SignalEntry.signal(signalRef: 'top.rst', displayName: 'rst'),
        ],
      );
      final config = VcdExportConfig.fromSignalGroup(
        signalGroup: group,
        signalMap: const {},
        startTime: 0,
        endTime: 100,
      );
      expect(config.signalRefs, containsAll(['top.clk', 'top.rst']));
    });

    test('collects signal refs from nested group', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.group(
            groupName: 'CPU',
            children: [
              SignalEntry.signal(signalRef: 'cpu.clk', displayName: 'clk'),
            ],
          ),
          SignalEntry.signal(signalRef: 'top.rst', displayName: 'rst'),
        ],
      );
      final config = VcdExportConfig.fromSignalGroup(
        signalGroup: group,
        signalMap: const {},
        startTime: 0,
        endTime: 100,
      );
      expect(config.signalRefs, containsAll(['cpu.clk', 'top.rst']));
    });

    test('skips separators and comments', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: 'top.clk', displayName: 'clk'),
          const SignalEntry.separator(),
          const SignalEntry.comment(text: 'divider'),
        ],
      );
      final config = VcdExportConfig.fromSignalGroup(
        signalGroup: group,
        signalMap: const {},
        startTime: 0,
        endTime: 100,
      );
      expect(config.signalRefs, ['top.clk']);
    });
  });
}
