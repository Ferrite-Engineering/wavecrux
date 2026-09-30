// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// Writes [content] to a temp file and returns the path.
Future<String> _tempFilter(String content) async {
  final dir = await Directory.systemTemp.createTemp('translate_filter_test');
  final file = File('${dir.path}/filter.txt');
  await file.writeAsString(content);
  return file.path;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('TranslateFilterNotifier', () {
    test('initial state is empty', () {
      final c = _container();
      expect(c.read(translateFilterProvider), isEmpty);
    });

    test('filterPaths is empty initially', () {
      final c = _container();
      expect(c.read(translateFilterProvider.notifier).filterPaths, isEmpty);
    });

    test('assignFilter parses file and adds to state', () async {
      final path = await _tempFilter('0 IDLE\n1 RUNNING\n2 ERROR\n');
      final c = _container();
      await c
          .read(translateFilterProvider.notifier)
          .assignFilter('top.state', path);

      final filters = c.read(translateFilterProvider);
      expect(filters, contains('top.state'));

      final filter = filters['top.state']!;
      expect(filter.translate('0'), 'IDLE');
      expect(filter.translate('1'), 'RUNNING');
      expect(filter.translate('10'), 'ERROR');
    });

    test('assignFilter records path in filterPaths', () async {
      final path = await _tempFilter('0 IDLE\n');
      final c = _container();
      await c
          .read(translateFilterProvider.notifier)
          .assignFilter('top.state', path);

      expect(
        c.read(translateFilterProvider.notifier).filterPaths,
        {'top.state': path},
      );
    });

    test('assignFilter is a no-op for nonexistent file', () async {
      final c = _container();
      await c
          .read(translateFilterProvider.notifier)
          .assignFilter('top.state', '/nonexistent/path/filter.txt');

      expect(c.read(translateFilterProvider), isEmpty);
      expect(
        c.read(translateFilterProvider.notifier).filterPaths,
        isEmpty,
      );
    });

    test('assignFilter failure is logged to package:logging (captured by the '
        'issue-reporter ring buffer)', () async {
      final records = <LogRecord>[];
      final originalLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await sub.cancel();
        Logger.root.level = originalLevel;
      });

      final c = _container();
      await c
          .read(translateFilterProvider.notifier)
          .assignFilter('top.state', '/nonexistent/path/filter.txt');

      final warnings = records.where((r) => r.level >= Level.WARNING).toList();
      expect(warnings, isNotEmpty);
      expect(warnings.last.loggerName, 'wavecrux.translate');
      expect(
        warnings.last.message,
        contains('Failed to load translate filter'),
      );
    });

    test('assignFilter overwrites previous assignment for same ref', () async {
      final path1 = await _tempFilter('0 OLD\n');
      final path2 = await _tempFilter('0 NEW\n');
      final c = _container();
      final notifier = c.read(translateFilterProvider.notifier);

      await notifier.assignFilter('top.s', path1);
      await notifier.assignFilter('top.s', path2);

      expect(c.read(translateFilterProvider)['top.s']!.translate('0'), 'NEW');
      expect(notifier.filterPaths['top.s'], path2);
    });

    test('removeFilter removes entry from state and paths', () async {
      final path = await _tempFilter('0 IDLE\n');
      final c = _container();
      final notifier = c.read(translateFilterProvider.notifier);

      await notifier.assignFilter('top.state', path);
      expect(c.read(translateFilterProvider), contains('top.state'));

      notifier.removeFilter('top.state');
      expect(c.read(translateFilterProvider), isEmpty);
      expect(notifier.filterPaths, isEmpty);
    });

    test('removeFilter is a no-op when signal has no filter', () {
      final c = _container();
      // Should not throw.
      c.read(translateFilterProvider.notifier).removeFilter('top.x');
      expect(c.read(translateFilterProvider), isEmpty);
    });

    test('getFilter returns null when not assigned', () {
      final c = _container();
      expect(
        c.read(translateFilterProvider.notifier).getFilter('top.x'),
        isNull,
      );
    });

    test('getFilter returns assigned filter', () async {
      final path = await _tempFilter('1 ON\n');
      final c = _container();
      await c
          .read(translateFilterProvider.notifier)
          .assignFilter('top.led', path);

      final filter = c
          .read(translateFilterProvider.notifier)
          .getFilter('top.led');
      expect(filter, isNotNull);
      expect(filter!.translate('1'), 'ON');
    });

    test('restoreFromSession loads all provided paths', () async {
      final path1 = await _tempFilter('0 IDLE\n1 RUN\n');
      final path2 = await _tempFilter('0 LOW\n1 HIGH\n');
      final c = _container();

      await c.read(translateFilterProvider.notifier).restoreFromSession({
        'top.fsm': path1,
        'top.en': path2,
      });

      final filters = c.read(translateFilterProvider);
      expect(filters, contains('top.fsm'));
      expect(filters, contains('top.en'));
      expect(filters['top.fsm']!.translate('0'), 'IDLE');
      expect(filters['top.en']!.translate('1'), 'HIGH');
    });

    test('restoreFromSession clears previous state first', () async {
      final path1 = await _tempFilter('0 OLD\n');
      final path2 = await _tempFilter('0 NEW\n');
      final c = _container();
      final notifier = c.read(translateFilterProvider.notifier);

      await notifier.assignFilter('top.a', path1);
      expect(c.read(translateFilterProvider), contains('top.a'));

      await notifier.restoreFromSession({'top.b': path2});

      final filters = c.read(translateFilterProvider);
      expect(filters, isNot(contains('top.a')));
      expect(filters, contains('top.b'));
    });

    test('restoreFromSession skips missing files without throwing', () async {
      final goodPath = await _tempFilter('0 OK\n');
      final c = _container();

      await c.read(translateFilterProvider.notifier).restoreFromSession({
        'top.a': goodPath,
        'top.b': '/nonexistent/filter.txt',
      });

      final filters = c.read(translateFilterProvider);
      expect(filters, contains('top.a'));
      expect(filters, isNot(contains('top.b')));
    });

    test('filterPaths mirrors all active assignments after restore', () async {
      final path = await _tempFilter('0 X\n');
      final c = _container();
      await c.read(translateFilterProvider.notifier).restoreFromSession({
        'top.s': path,
      });

      expect(
        c.read(translateFilterProvider.notifier).filterPaths,
        {'top.s': path},
      );
    });

    // ── clearAll ──────────────────────────────────────────────────────────────

    test('clearAll resets state to empty', () async {
      final path = await _tempFilter('0 ZERO\n1 ONE\n');
      final c = _container();
      final notifier = c.read(translateFilterProvider.notifier);

      await notifier.assignFilter('top.a', path);
      await notifier.assignFilter('top.b', path);
      expect(c.read(translateFilterProvider).length, 2);

      notifier.clearAll();

      expect(c.read(translateFilterProvider), isEmpty);
    });

    test('clearAll clears filterPaths', () async {
      final path = await _tempFilter('0 ZERO\n');
      final c = _container();
      final notifier = c.read(translateFilterProvider.notifier);

      await notifier.assignFilter('top.sig', path);
      expect(notifier.filterPaths, isNotEmpty);

      notifier.clearAll();

      expect(notifier.filterPaths, isEmpty);
    });

    test('clearAll is safe when already empty', () {
      final c = _container();
      expect(
        () => c.read(translateFilterProvider.notifier).clearAll(),
        returnsNormally,
      );
      expect(c.read(translateFilterProvider), isEmpty);
    });
  });

  group('TranslateFilter.translate (edge cases used by provider)', () {
    const service = TranslateFilterService();

    test('returns null for x-containing value', () {
      final f = service.parse('0 ZERO\n1 ONE\n');
      expect(f.translate('x'), isNull);
      expect(f.translate('0x1'), isNull);
    });

    test('returns null for z-containing value', () {
      final f = service.parse('0 ZERO\n');
      expect(f.translate('z'), isNull);
    });

    test('returns null when no entry matches', () {
      final f = service.parse('0 ZERO\n');
      expect(f.translate('1'), isNull);
    });

    test('matches multi-bit binary value correctly', () {
      // decimal 5 == binary 101
      final f = service.parse('5 FIVE\n');
      expect(f.translate('101'), 'FIVE');
    });
  });
}
