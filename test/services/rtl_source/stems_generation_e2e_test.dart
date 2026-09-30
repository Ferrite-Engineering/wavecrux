// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/services/rtl_source/stems_generator.dart';
import 'package:wavecrux/services/rtl_source/stems_writer.dart';

/// Full RTL stems round trip a user actually exercises:
/// generate from an HDL source tree → write the .stems file → load it through
/// [RtlSourceNotifier] → navigate a signal to its source line.
void main() {
  final fixtureRoot = '${Directory.current.path}/test/fixtures/rtl_source';
  final cpuDir = '$fixtureRoot/cpu';

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stems_e2e_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 1-based line in [file] (read from disk) → assert it contains [token].
  void expectLineContains(String file, int line, String token) {
    final lines = File(file).readAsLinesSync();
    expect(
      lines[line - 1],
      contains(token),
      reason: '$file:$line = "${lines[line - 1]}"',
    );
  }

  test(
    'Verilog: generate → write → load → showSignal resolves source lines',
    () async {
      // 1. Generate from the multi-file Verilog design.
      const generator = StemsGenerator();
      final result = await generator.generateFromPaths([
        '$cpuDir/top.v',
        '$cpuDir/alu.v',
        '$cpuDir/regfile.v',
      ]);
      expect(result.resolvedTop, 'top');
      expect(result.stems.isNotEmpty, isTrue);

      // 2. Write the on-disk stems file.
      final stemsPath = '${tmp.path}/top.stems';
      File(
        stemsPath,
      ).writeAsStringSync(const StemsWriter().write(result.stems));

      // 3. Load it through the real notifier (real disk reads).
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(rtlSourceProvider.notifier);
      await notifier.loadStemsFile(stemsPath);
      expect(container.read(rtlSourceProvider).status, RtlStemsStatus.ready);

      // 4a. A signal in the deepest child module resolves to alu.v at its decl.
      final okAlu = await notifier.showSignal(
        signalRef: 'sig:alu_y',
        signalPath: 'top.u_alu.y',
      );
      expect(okAlu, isTrue);
      var state = container.read(rtlSourceProvider);
      expect(state.currentSourceFile!.path, endsWith('alu.v'));
      expectLineContains(
        state.currentSourceFile!.path,
        state.currentLine!,
        'y',
      );

      // 4b. A top-level net resolves to top.v.
      final okTop = await notifier.showSignal(
        signalRef: 'sig:op_a',
        signalPath: 'top.op_a',
      );
      expect(okTop, isTrue);
      state = container.read(rtlSourceProvider);
      expect(state.currentSourceFile!.path, endsWith('top.v'));
      expectLineContains(
        state.currentSourceFile!.path,
        state.currentLine!,
        'op_a',
      );

      // 4c. A register-file signal resolves to regfile.v.
      final okRf = await notifier.showSignal(
        signalRef: 'sig:rf_a',
        signalPath: 'top.u_regfile.a',
      );
      expect(okRf, isTrue);
      state = container.read(rtlSourceProvider);
      expect(state.currentSourceFile!.path, endsWith('regfile.v'));
    },
  );

  test(
    'VHDL: generate → write → load → showSignal resolves source lines',
    () async {
      const generator = StemsGenerator();
      final result = await generator.generateFromPaths(
        ['$fixtureRoot/vhdl/counter.vhd'],
      );
      expect(result.resolvedTop, 'counter');

      final stemsPath = '${tmp.path}/counter.stems';
      File(
        stemsPath,
      ).writeAsStringSync(const StemsWriter().write(result.stems));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(rtlSourceProvider.notifier);
      await notifier.loadStemsFile(stemsPath);

      // Architecture signal `cnt` resolves into counter.vhd.
      final ok = await notifier.showSignal(
        signalRef: 'sig:cnt',
        signalPath: 'counter.cnt',
      );
      expect(ok, isTrue);
      final state = container.read(rtlSourceProvider);
      expect(state.currentSourceFile!.path, endsWith('counter.vhd'));
      expectLineContains(
        state.currentSourceFile!.path,
        state.currentLine!,
        'cnt',
      );
    },
  );
}
