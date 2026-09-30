// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';
import 'package:wavecrux/services/rtl_source/stems_generator.dart';
import 'package:wavecrux/services/rtl_source/stems_parser.dart';
import 'package:wavecrux/services/rtl_source/stems_writer.dart';

/// Generator exercised against a real, ISC-licensed third-party design
/// (PicoRV32, pinned commit) with a genuine multi-module instantiation
/// hierarchy and multi-line parameterized instantiations. See
/// `test/fixtures/rtl_source/captured/picorv32/PROVENANCE.md`.
void main() {
  final picorv32 =
      '${Directory.current.path}/test/fixtures/rtl_source/captured/picorv32/picorv32.v';
  final lines = File(picorv32).readAsLinesSync();

  late StemsFile stems;
  late StemsGenerationResult result;

  setUpAll(() async {
    result = await const StemsGenerator().generateFromPaths([
      picorv32,
    ], topModule: 'picorv32_axi');
    stems = result.stems;
  });

  /// The (1-based) line a stems entry maps to must contain [token] in the real
  /// source — robust to reformatting / a future re-vendor, unlike a hardcoded
  /// line number.
  void expectMaps(StemsEntry? entry, String token) {
    expect(entry, isNotNull);
    expect(entry!.sourceFile, endsWith('picorv32.v'));
    expect(
      lines[entry.lineNumber - 1],
      contains(token),
      reason:
          '${entry.path} → line ${entry.lineNumber}: '
          '"${lines[entry.lineNumber - 1]}"',
    );
  }

  test('resolves the requested top and produces a large mapping', () {
    expect(result.resolvedTop, 'picorv32_axi');
    expect(stems.length, greaterThan(200));
  });

  test('top module and its ports map to their source lines', () {
    expectMaps(stems.lookupScope('picorv32_axi'), 'module picorv32_axi');
    expectMaps(stems.lookup('picorv32_axi.trap'), 'trap');
  });

  test('cross-module hierarchy: multi-line #(...) instantiation resolves', () {
    // picorv32_axi instantiates the `picorv32` core as `picorv32_core` via a
    // many-line parameter list — the case the upgraded parser had to handle.
    expectMaps(
      stems.lookupScope('picorv32_axi.picorv32_core'),
      'module picorv32',
    );
    expectMaps(stems.lookup('picorv32_axi.picorv32_core.trap'), 'trap');
  });

  test('plain (no-param) instantiation resolves: the AXI adapter', () {
    expectMaps(
      stems.lookupScope('picorv32_axi.axi_adapter'),
      'module picorv32_axi_adapter',
    );
  });

  test('auto-top detection reports the ambiguous candidates', () {
    final auto = const StemsGenerator().generate(
      sources: {picorv32: File(picorv32).readAsStringSync()},
    );
    expect(auto.resolvedTop, isNull, reason: 'multiple un-instantiated tops');
    expect(
      auto.availableTops,
      containsAll(<String>['picorv32_axi', 'picorv32_wb']),
    );
  });

  test('generated stems round-trip through the on-disk format', () {
    final reparsed = const StemsParser().parse(
      const StemsWriter().write(stems),
    );
    for (final path in [
      'picorv32_axi',
      'picorv32_axi.picorv32_core.trap',
    ]) {
      final a = stems.lookup(path)!;
      final b = reparsed.lookup(path)!;
      expect(b.sourceFile, a.sourceFile);
      expect(b.lineNumber, a.lineNumber);
      expect(b.kind, a.kind);
    }
  });
}
