// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// End-to-end GTKWave session import — boots the real app with a real wellen
// (FFI/WASM) parse of fixture.vcd, then imports the synthetic `.gtkw` saves
// against the LIVE variable list and applies the result through the real
// per-tab `signalGroupsProvider` / `markerStateProvider`.
//
// Why this exists on top of the unit/widget suite: the widget-level pipeline
// test (`test/features/viewer/gtkw_import_pipeline_test.dart`) feeds the import
// a *hand-declared* variable set (`fixtureVcdVariables()`). Nothing there proves
// that a genuinely wellen-parsed `fixture.vcd` yields variables whose
// `fullPath` / `signalRef` the `.gtkw` path matcher actually resolves — the
// real cross-the-FFI-boundary integration risk. This test closes that: if
// wellen ever changed how it reports scope paths, the `unmatchedSignalPaths`
// assertions below would fail.
//
// The native file picker and the private `ViewerScreen._importGtkwFromPath`
// are not driven (the picker can't run headlessly under xvfb); this exercises
// the same parse → match-against-live-vars → apply-to-providers wiring those
// thin layers wrap. Runs in the nightly Linux integration sweep
// (`integration_test/session/`).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/gtkw_import_apply.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

import '../helpers/app_driver.dart';

String _gtkwFixture(String name) =>
    '${Directory.current.path}/test/fixtures/gtkw/generated/$name';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('GTKWave import resolves against live wellen variables', (
    tester,
  ) async {
    // 1. Boot the real app with the paired waveform loaded (real FFI parse).
    await loadFixtureVcdAbsolute(tester, _gtkwFixture('fixture.vcd'));

    final tab = activeTabContainer(tester);

    // 2. Extract the variable list exactly as ViewerScreen._importGtkwFromPath
    //    does — from the live, wellen-parsed waveform source.
    final source = tab.read(waveformSourceProvider).value;
    expect(source, isNotNull, reason: 'fixture.vcd did not load');
    final liveVars = source!.findVariables(const SignalFilter());
    expect(liveVars, isNotEmpty);

    const parser = GtkwParser();
    const importer = GtkwImportService();

    Future<GtkwImportResult> importInto(String fixture) async {
      final content = File(_gtkwFixture(fixture)).readAsStringSync();
      final result = importer.importSession(parser.parse(content), liveVars);
      // Apply through the real per-tab providers, as the import command does.
      await applyGtkwImport(tab, result);
      return result;
    }

    // 3. simple_signals.gtkw — the core integration assertion: every path in
    //    the save resolves against a real wellen variable (nothing unmatched).
    final simple = await importInto('simple_signals.gtkw');
    expect(
      simple.unmatchedSignalPaths,
      isEmpty,
      reason:
          'live wellen variable paths did not match the .gtkw paths — '
          'the FFI scope-path contract may have drifted',
    );
    expect(simple.matchedSignalCount, 3);
    expect(tab.read(signalGroupsProvider).signalCount, 3);

    // 4. groups.gtkw — named groups reconstruct over live variables.
    final groups = await importInto('groups.gtkw');
    expect(groups.unmatchedSignalPaths, isEmpty);
    expect(groups.groupCount, 2);
    final groupEntries = tab
        .read(signalGroupsProvider)
        .entries
        .where((e) => e.kind == SignalEntryKind.group)
        .map((e) => e.groupName)
        .toList();
    expect(groupEntries, ['Clocks', 'CPU Bus']);

    // 5. colors_and_markers.gtkw — markers land in the live marker provider.
    final colored = await importInto('colors_and_markers.gtkw');
    expect(colored.unmatchedSignalPaths, isEmpty);
    final liveMarkers = tab.read(markerStateProvider);
    expect(liveMarkers.getMarker('a'), 30);
    expect(liveMarkers.getMarker('b'), 50);
    expect(tab.read(cursorStateProvider).primaryCursorTime, 40);

    await tester.pumpAndSettle();
  });
}
