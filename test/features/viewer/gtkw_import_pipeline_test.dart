// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Integration-style test for the GTKWave import *orchestration* — the wiring
// that `ViewerScreen._importGtkwFromPath` performs after the file picker
// returns: read → parse → import → `applyGtkwImport` into the live providers.
//
// It drives the real fixture files through the real parser, the real import
// service, and the REAL providers (a `ProviderContainer`, no mocks), then
// asserts the providers expose the imported structure through their public
// API. This closes the "orchestration is untested end-to-end" gap.
//
// Out of scope here (and individually covered elsewhere): the native file
// picker (`FilePicker.platform`), FFI variable extraction from a loaded
// waveform (substituted with the known `fixtureVcdVariables()` set), and the
// result dialog (`gtkw_import_result_dialog_test.dart`). The remaining sliver
// is exactly the glue this test exercises.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/gtkw_import_apply.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

import '../../services/session/gtkw_golden_codec.dart';

const _generatedDir = 'test/fixtures/gtkw/generated';
const _parser = GtkwParser();
const _importService = GtkwImportService();

/// Runs the full picker-less orchestration: parse [fixture], import it against
/// the fixture-VCD variable set, and apply the result into [container]'s
/// providers through `applyGtkwImport`, the call
/// `ViewerScreen._importGtkwFromPath` makes.
Future<GtkwImportResult> _importInto(
  ProviderContainer container,
  String fixture,
) async {
  final path = '$_generatedDir/$fixture';
  final result = _importService.importSession(
    _parser.parse(File(path).readAsStringSync()),
    fixtureVcdVariables(),
    gtkwFilePath: path,
    fileExists: (candidate) => File(candidate).existsSync(),
  );
  await applyGtkwImport(container, result);
  return result;
}

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('GTKWave import orchestration → live providers', () {
    test('simple_signals.gtkw lands 3 signals in the signal panel', () async {
      final c = _container();
      final result = await _importInto(c, 'simple_signals.gtkw');

      final group = c.read(signalGroupsProvider);
      expect(group.signalCount, 3);
      expect(result.matchedSignalCount, 3);
      // top.data carried `@8` → default hex; top.clk/top.rst under `@28`.
      final names = group.entries.map((e) => e.displayName).toList();
      expect(names, containsAll(<String>['clk', 'rst', 'data']));
      expect(c.read(markerStateProvider).markers, isEmpty);
    });

    test(
      'groups.gtkw reconstructs both named groups + trailing signal',
      () async {
        final c = _container();
        await _importInto(c, 'groups.gtkw');

        final entries = c.read(signalGroupsProvider).entries;
        final groups = entries
            .where((e) => e.kind == SignalEntryKind.group)
            .map((e) => e.groupName)
            .toList();
        expect(groups, ['Clocks', 'CPU Bus']);
        // "CPU Bus" wraps top.cpu.addr + top.cpu.dout.
        final cpuBus = entries.firstWhere((e) => e.groupName == 'CPU Bus');
        expect(cpuBus.children.length, 2);
        // The ungrouped top.rst trails the two groups.
        expect(entries.last.kind, SignalEntryKind.signal);
        expect(entries.last.displayName, 'rst');
      },
    );

    test('format_flags.gtkw applies per-signal display formats', () async {
      final c = _container();
      await _importInto(c, 'format_flags.gtkw');

      final byName = {
        for (final e in c.read(signalGroupsProvider).entries) e.displayName: e,
      };
      expect(byName['clk']!.format, DisplayFormat.hexadecimal); // @28
      expect(byName['rst']!.format, DisplayFormat.binary); // @20
      expect(byName['data']!.format, DisplayFormat.unsignedDecimal); // @24
      expect(byName['addr']!.format, DisplayFormat.signedDecimal); // @26
      expect(byName['dout']!.format, DisplayFormat.octal); // @22
    });

    test(
      'colors_and_markers.gtkw applies colors, markers a/b and cursor',
      () async {
        final c = _container();
        await _importInto(c, 'colors_and_markers.gtkw');

        final byName = {
          for (final e in c.read(signalGroupsProvider).entries)
            e.displayName: e,
        };
        expect(byName['clk']!.argbColor, 0xFFFF5555); // [color] 1 red
        expect(byName['rst']!.argbColor, 0xFF00FF00); // [color] 4 green
        expect(byName['addr']!.argbColor, isNull); // [color] 0 auto

        final markers = c.read(markerStateProvider);
        expect(markers.getMarker('a'), 30);
        expect(markers.getMarker('b'), 50);
        // The field before the named markers is GTKWave's primary marker.
        expect(markers.getMarker('c'), isNull);
        expect(c.read(cursorStateProvider).primaryCursorTime, 40);
      },
    );

    test(
      're-importing replaces (not appends to) the prior signal panel',
      () async {
        final c = _container();
        await _importInto(c, 'groups.gtkw'); // 4 signals across 2 groups + rst
        await _importInto(c, 'simple_signals.gtkw'); // 3 flat signals

        // restoreFromSession replaces wholesale — the groups must be gone.
        final entries = c.read(signalGroupsProvider).entries;
        expect(entries.every((e) => e.kind == SignalEntryKind.signal), isTrue);
        expect(c.read(signalGroupsProvider).signalCount, 3);
      },
    );

    test(
      'translate_refs.gtkw lands its filter file on the data trace',
      () async {
        final c = _container();
        final result = await _importInto(c, 'translate_refs.gtkw');

        final filter = c.read(translateFilterProvider)['top.data'];
        expect(filter, isNotNull);
        expect(filter!.translate('00000001'), 'RUNNING');
        expect(c.read(translateFilterProvider).keys, ['top.data']);
        // The missing file and both filter processes are reported.
        expect(result.filterIssues, hasLength(3));
        expect(result.hasUnmatchedSignals, isFalse);
      },
    );

    test(
      'unmatched signals are reported and excluded from the panel',
      () async {
        final c = _container();
        // fixtureVcdVariables has no `top.missing` — synthesize a tiny .gtkw
        // inline rather than reading a fixture.
        const gtkw = GtkwParser();
        final parsed = gtkw.parse('@28\ntop.clk\ntop.missing\n');
        final result = _importService.importSession(
          parsed,
          fixtureVcdVariables(),
        );
        await applyGtkwImport(c, result);

        expect(result.unmatchedSignalPaths, ['top.missing']);
        expect(c.read(signalGroupsProvider).signalCount, 1);
      },
    );
  });
}
