// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/rtl_source/rtl_source_loader.dart';

class _FakeReader extends FileReader {
  _FakeReader();

  final Map<String, String> contents = {};
  final Map<String, DateTime> mtimes = {};

  int statCalls = 0;
  int readCalls = 0;

  @override
  Future<RtlFileStat?> stat(String path) async {
    statCalls++;
    final mtime = mtimes[path];
    if (mtime == null) return null;
    return RtlFileStat(modified: mtime);
  }

  @override
  Future<String> readAsString(String path) async {
    readCalls++;
    final c = contents[path];
    if (c == null) throw const FileSystemMissing();
    return c;
  }
}

class FileSystemMissing implements Exception {
  const FileSystemMissing();
  @override
  String toString() => 'simulated file not found';
}

void main() {
  group('RtlSourceLoader.load', () {
    test('reads and splits lines (LF)', () async {
      final reader = _FakeReader()
        ..contents['/a.v'] = 'one\ntwo\nthree'
        ..mtimes['/a.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: reader);
      final result = await loader.load('/a.v');

      expect(result.path, '/a.v');
      expect(result.lines, ['one', 'two', 'three']);
      expect(result.lineCount, 3);
    });

    test('normalises CRLF and CR to LF', () async {
      final reader = _FakeReader()
        ..contents['/a.v'] = 'a\r\nb\rc\nd'
        ..mtimes['/a.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: reader);
      final result = await loader.load('/a.v');
      expect(result.lines, ['a', 'b', 'c', 'd']);
    });

    test(
      'preserves trailing empty line when content ends with newline',
      () async {
        final reader = _FakeReader()
          ..contents['/a.v'] = 'a\nb\n'
          ..mtimes['/a.v'] = DateTime(2026);
        final loader = RtlSourceLoader(fileReader: reader);
        final result = await loader.load('/a.v');
        expect(result.lines, ['a', 'b', '']);
      },
    );

    test('empty content yields a single empty line', () async {
      final reader = _FakeReader()
        ..contents['/a.v'] = ''
        ..mtimes['/a.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: reader);
      final result = await loader.load('/a.v');
      expect(result.lines, ['']);
    });

    test('throws RtlSourceLoadException when file missing', () async {
      final reader = _FakeReader();
      final loader = RtlSourceLoader(fileReader: reader);
      expect(
        () => loader.load('/nope.v'),
        throwsA(
          isA<RtlSourceLoadException>()
              .having((e) => e.filePath, 'filePath', '/nope.v')
              .having((e) => e.reason, 'reason', contains('not found')),
        ),
      );
    });

    test(
      'rethrows reader IO exceptions wrapped in RtlSourceLoadException',
      () async {
        // stat() succeeds (mtime present) but readAsString throws.
        final reader = _FakeReader()..mtimes['/a.v'] = DateTime(2026);
        final loader = RtlSourceLoader(fileReader: reader);
        expect(
          () => loader.load('/a.v'),
          throwsA(isA<RtlSourceLoadException>()),
        );
      },
    );

    test('cache hit avoids re-reading when mtime unchanged', () async {
      final reader = _FakeReader()
        ..contents['/a.v'] = 'one'
        ..mtimes['/a.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: reader);
      await loader.load('/a.v');
      await loader.load('/a.v');
      expect(reader.statCalls, 2);
      expect(reader.readCalls, 1); // second hit served from cache
    });

    test('cache invalidates when mtime changes', () async {
      final reader = _FakeReader()
        ..contents['/a.v'] = 'one'
        ..mtimes['/a.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: reader);
      await loader.load('/a.v');
      reader.contents['/a.v'] = 'two';
      reader.mtimes['/a.v'] = DateTime(2026, 1, 2);
      final r2 = await loader.load('/a.v');
      expect(r2.lines, ['two']);
      expect(reader.readCalls, 2);
    });

    test('invalidate() drops the cached entry', () async {
      final reader = _FakeReader()
        ..contents['/a.v'] = 'x'
        ..mtimes['/a.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: reader);
      await loader.load('/a.v');
      loader.invalidate('/a.v');
      await loader.load('/a.v');
      expect(reader.readCalls, 2);
    });

    test('clear() drops every cached entry', () async {
      final reader = _FakeReader()
        ..contents['/a.v'] = 'x'
        ..contents['/b.v'] = 'y'
        ..mtimes['/a.v'] = DateTime(2026)
        ..mtimes['/b.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: reader);
      await loader.load('/a.v');
      await loader.load('/b.v');
      loader.clear();
      await loader.load('/a.v');
      await loader.load('/b.v');
      expect(reader.readCalls, 4);
    });
  });

  group('RtlSourceLoader cache bounds', () {
    // The loader is owned by a `keepAlive` notifier and was cleared only
    // when a stems file was loaded or dropped, so walking an SoC's signals
    // retained every visited file's full line list for the session.
    //
    // PRIMARY MUTATION TARGET: raising either bound (e.g. `maxCachedFiles`
    // → 1 << 30) restores that growth and fails these.
    _FakeReader readerWith(int files, int linesEach) {
      final reader = _FakeReader();
      for (var i = 0; i < files; i++) {
        reader
          ..contents['/f$i.v'] = List<String>.generate(
            linesEach,
            (l) => 'line $l',
          ).join('\n')
          ..mtimes['/f$i.v'] = DateTime(2026);
      }
      return reader;
    }

    test('the file count is bounded', () async {
      final reader = readerWith(500, 10);
      final loader = RtlSourceLoader(fileReader: reader, maxCachedFiles: 8);
      for (var i = 0; i < 500; i++) {
        await loader.load('/f$i.v');
      }
      expect(loader.cachedFileCount, 8);
      expect(loader.cachedLineCount, 8 * 10);
    });

    test(
      'the retained line count is bounded, even below the file cap',
      () async {
        final reader = readerWith(100, 1000);
        final loader = RtlSourceLoader(
          fileReader: reader,
          maxCachedFiles: 1000,
          maxCachedLines: 5000,
        );
        for (var i = 0; i < 100; i++) {
          await loader.load('/f$i.v');
        }
        expect(loader.cachedLineCount, lessThanOrEqualTo(5000));
        expect(loader.cachedFileCount, lessThanOrEqualTo(5));
      },
    );

    test('eviction is least-recently-used, and a hit promotes', () async {
      final reader = readerWith(4, 1);
      final loader = RtlSourceLoader(fileReader: reader, maxCachedFiles: 2);
      await loader.load('/f0.v');
      await loader.load('/f1.v');
      // Touch f0 so f1 becomes the oldest.
      await loader.load('/f0.v');
      await loader.load('/f2.v');
      final readsBefore = reader.readCalls;
      // f0 is still cached (no re-read); f1 was evicted (re-read).
      await loader.load('/f0.v');
      expect(reader.readCalls, readsBefore);
      await loader.load('/f1.v');
      expect(reader.readCalls, readsBefore + 1);
    });

    test('a single file larger than the line bound is still served', () async {
      final reader = readerWith(1, 50000);
      final loader = RtlSourceLoader(
        fileReader: reader,
        maxCachedLines: 1000,
      );
      final file = await loader.load('/f0.v');
      expect(file.lineCount, 50000);
      expect(loader.cachedFileCount, 1);
    });
  });

  group('RtlSourceFile equality', () {
    test('equal when path and lines match', () {
      const a = RtlSourceFile(path: 'f.v', lines: ['a', 'b']);
      const b = RtlSourceFile(path: 'f.v', lines: ['a', 'b']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when lines differ', () {
      const a = RtlSourceFile(path: 'f.v', lines: ['a']);
      const b = RtlSourceFile(path: 'f.v', lines: ['b']);
      expect(a, isNot(b));
    });

    test('not equal when path differs', () {
      const a = RtlSourceFile(path: 'a.v', lines: ['a']);
      const b = RtlSourceFile(path: 'b.v', lines: ['a']);
      expect(a, isNot(b));
    });

    test('toString contains path and line count', () {
      const a = RtlSourceFile(path: 'f.v', lines: ['a', 'b', 'c']);
      expect(a.toString(), contains('f.v'));
      expect(a.toString(), contains('3'));
    });
  });
}
