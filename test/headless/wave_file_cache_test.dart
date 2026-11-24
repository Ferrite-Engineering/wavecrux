// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The server's two-file cache: the two most recently used files, keyed by
// canonical path, size and modification time.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/headless/wave_file_cache.dart';

import 'support/fake_wave_source.dart';

void main() {
  late Directory dir;
  late List<String> opened;
  late List<String> closed;
  late WaveFileCache cache;

  String file(String name, [String body = 'x']) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(body);
    return path;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wave_file_cache_');
    opened = <String>[];
    closed = <String>[];
    cache = WaveFileCache(
      opener: (path) async {
        opened.add(p.basename(path));
        return fakeWaveFile(onClose: () => closed.add(p.basename(path)));
      },
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('a file asked for again is not opened again', () async {
    final a = file('a.vcd');
    final first = await cache.open(a);
    final second = await cache.open(a);
    expect(identical(first, second), isTrue);
    expect(opened, <String>['a.vcd']);
  });

  test('keeps two files and closes the least recently used', () async {
    final a = file('a.vcd');
    final b = file('b.vcd');
    final c = file('c.vcd');
    await cache.open(a);
    await cache.open(b);
    await cache.open(a); // a is now the most recent
    await cache.open(c);
    expect(closed, <String>['b.vcd']);
    expect(cache.keys, hasLength(2));
    await cache.open(a);
    expect(opened, <String>['a.vcd', 'b.vcd', 'c.vcd']);
  });

  test('two spellings of one file share an entry', () async {
    final a = file('a.vcd');
    Link(p.join(dir.path, 'alias.vcd')).createSync(a);
    await cache.open(a);
    await cache.open(p.join(dir.path, 'alias.vcd'));
    await cache.open(p.join(dir.path, '.', 'a.vcd'));
    expect(opened, <String>['a.vcd']);
  });

  test(
    'a file rewritten in place is read again and the old copy closed',
    () async {
      final a = file('a.vcd', 'one');
      await cache.open(a);
      File(a).writeAsStringSync('a longer second run');
      await cache.open(a);
      expect(opened, <String>['a.vcd', 'a.vcd']);
      expect(closed, <String>['a.vcd']);
      expect(cache.keys, hasLength(1));
    },
  );

  test('a file that fails to open is not kept', () async {
    final a = file('a.vcd');
    final failing = WaveFileCache(opener: (_) async => throw StateError('no'));
    await expectLater(failing.open(a), throwsStateError);
    expect(failing.keys, isEmpty);
  });

  test('closeAll closes every file held', () async {
    await cache.open(file('a.vcd'));
    await cache.open(file('b.vcd'));
    await cache.closeAll();
    expect(closed, unorderedEquals(<String>['a.vcd', 'b.vcd']));
    expect(cache.keys, isEmpty);
  });
}
