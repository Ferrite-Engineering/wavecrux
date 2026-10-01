// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// One test per field `applyGtkwImport` applies, each against the real
// provider the viewer reads. `ViewerScreen._importGtkwFromPath` calls this
// function and nothing else to apply an import, so a field that stops being
// applied fails here.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/gtkw_import_apply.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/services/session/gtkw_parser.dart';

import '../../../services/session/gtkw_golden_codec.dart';

const _service = GtkwImportService();

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// Lays out a 0–100 000 tick dump across 1 000 px, as the canvas does on open.
void _layOut(ProviderContainer c) {
  c
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 100000, viewportWidth: 1000);
}

GtkwImportResult _import(
  String gtkw, {
  String? gtkwFilePath,
  bool Function(String)? fileExists,
}) => _service.importSession(
  const GtkwParser().parse(gtkw),
  fixtureVcdVariables(),
  gtkwFilePath: gtkwFilePath,
  fileExists: fileExists,
);

/// A `*` line with zoom exponent [zoom] and every marker unset.
String _star(double zoom, {int primary = -1, int a = -1, int b = -1}) =>
    '*$zoom $primary $a $b ${List.filled(24, '-1').join(' ')}\n';

void main() {
  group('applyGtkwImport', () {
    test('applies the trace list with formats and colors', () async {
      final c = _container();
      await applyGtkwImport(
        c,
        _import('@24\n[color] 1\ntop.data\n@28\ntop.clk\n'),
      );
      final entries = c.read(signalGroupsProvider).entries;
      expect(entries.map((e) => e.displayName), ['data', 'clk']);
      expect(entries.first.format, DisplayFormat.unsignedDecimal);
      expect(entries.first.argbColor, 0xFFFF5555);
    });

    test('applies named markers and the primary cursor', () async {
      final c = _container();
      await applyGtkwImport(
        c,
        _import('${_star(-10, primary: 40, a: 30, b: 50)}@28\ntop.clk\n'),
      );
      expect(c.read(markerStateProvider).markers, {'a': 30, 'b': 50});
      expect(c.read(cursorStateProvider).primaryCursorTime, 40);
    });

    test('applies the zoom', () async {
      final c = _container();
      _layOut(c);
      // 2^10 / 200 = 5.12 ticks per pixel.
      await applyGtkwImport(c, _import(_star(-10)));
      expect(c.read(timeMapperProvider).ticksPerPixel, closeTo(5.12, 1e-9));
    });

    test('applies the scroll position from [timestart]', () async {
      final c = _container();
      _layOut(c);
      await applyGtkwImport(c, _import('[timestart] 40000\n${_star(-10)}'));
      final mapper = c.read(timeMapperProvider);
      expect(mapper.panOffsetTicks, 40000);
      expect(mapper.visibleStartTime, 40000);
    });

    test('a zoom wider than the dump lands on fit-all', () async {
      final c = _container();
      _layOut(c);
      // 2^20 / 200 ≈ 5243 ticks per pixel: far wider than 100 000 ticks.
      await applyGtkwImport(c, _import('[timestart] 0\n${_star(-20)}'));
      final mapper = c.read(timeMapperProvider);
      expect(mapper.ticksPerPixel, mapper.maxTicksPerPixel);
      expect(mapper.visibleStartTime, 0);
    });

    test('with no viewport yet, zoom and scroll are staged for it', () async {
      final c = _container();
      await applyGtkwImport(c, _import('[timestart] 40000\n${_star(-10)}'));
      _layOut(c);
      final mapper = c.read(timeMapperProvider);
      expect(mapper.ticksPerPixel, closeTo(5.12, 1e-9));
      expect(mapper.panOffsetTicks, 40000);
    });

    test('a file with no zoom leaves the view alone', () async {
      final c = _container();
      _layOut(c);
      final before = c.read(timeMapperProvider);
      await applyGtkwImport(c, _import('@28\ntop.clk\n'));
      expect(c.read(timeMapperProvider).ticksPerPixel, before.ticksPerPixel);
      expect(c.read(timeMapperProvider).panOffsetTicks, before.panOffsetTicks);
    });

    test('applies expanded scopes, keeping ones already open', () async {
      final c = _container();
      c.read(expandedScopesProvider.notifier).applyExpanded({'other'});
      await applyGtkwImport(
        c,
        _import('[treeopen] top.\n[treeopen] top.cpu.\n'),
      );
      expect(c.read(expandedScopesProvider), {'other', 'top', 'top.cpu'});
    });

    test('applies the translate filter file to the matched trace', () async {
      final dir = await Directory.systemTemp.createTemp('gtkw_apply_test');
      addTearDown(() => dir.delete(recursive: true));
      final filter = File('${dir.path}/states.txt')
        ..writeAsStringSync('0 IDLE\n1 BUSY\n');
      final save = File('${dir.path}/view.gtkw');

      final c = _container();
      final result = _import(
        '@2022\n^1 ${filter.path}\ntop.data[7:0]\n',
        gtkwFilePath: save.path,
        fileExists: (path) => File(path).existsSync(),
      );
      await applyGtkwImport(c, result);

      final applied = c.read(translateFilterProvider)['top.data'];
      expect(applied, isNotNull);
      expect(applied!.translate('1'), 'BUSY');
      expect(
        c.read(translateFilterProvider.notifier).filterPaths.keys,
        ['top.data'],
      );
    });

    test('a missing filter file applies nothing and is reported', () async {
      final c = _container();
      final result = _import(
        '@2022\n^1 /nowhere/states.txt\ntop.data[7:0]\n',
        gtkwFilePath: '/nowhere/view.gtkw',
        fileExists: (_) => false,
      );
      await applyGtkwImport(c, result);
      expect(c.read(translateFilterProvider), isEmpty);
      expect(result.filterIssues.single.kind, GtkwFilterIssueKind.missingFile);
    });
  });
}
