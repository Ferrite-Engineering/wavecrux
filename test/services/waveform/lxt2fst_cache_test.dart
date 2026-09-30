// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/waveform/lxt2fst_cache.dart';

void main() {
  late Directory tempRoot;
  late Directory appCache;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('lxt2-cache-test-');
    appCache = Directory(p.join(tempRoot.path, 'app-cache'))..createSync();
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  Lxt2FstCache buildCache() => Lxt2FstCache(
    appCacheDirResolver: () async => appCache,
  );

  /// Create an LXT2 source file in [tempRoot] and return its path.
  String writeSource({String name = 'sample.lxt2', int sizeBytes = 16}) {
    final file = File(p.join(tempRoot.path, name))
      ..writeAsBytesSync(List<int>.generate(sizeBytes, (i) => i & 0xff));
    return file.path;
  }

  group('resolve()', () {
    test('reports no cache when the sibling .fst is missing', () async {
      final cache = buildCache();
      final source = writeSource();

      final decision = await cache.resolve(source);
      expect(decision.fromCache, isFalse);
      expect(decision.isSibling, isTrue);
      expect(decision.fstPath, endsWith('.fst'));
      expect(p.dirname(decision.fstPath), p.dirname(source));
    });

    test(
      'reports cache hit when sibling .fst is fresh and sidecar matches',
      () async {
        final cache = buildCache();
        final source = writeSource();
        final decision = await cache.resolve(source);

        // Pretend the converter ran and wrote the FST.
        File(decision.fstPath).writeAsBytesSync(const [0x00, 0x01, 0x02]);
        await cache.recordSuccess(
          sourcePath: source,
          fstPath: decision.fstPath,
        );

        // Second open: cache hit.
        final second = await cache.resolve(source);
        expect(second.fromCache, isTrue);
        expect(second.fstPath, decision.fstPath);
      },
    );

    test(
      'reports stale cache when the source file is touched after caching',
      () async {
        final cache = buildCache();
        final source = writeSource();
        final decision = await cache.resolve(source);
        File(decision.fstPath).writeAsBytesSync(const [0x00]);
        await cache.recordSuccess(
          sourcePath: source,
          fstPath: decision.fstPath,
        );

        // Touch the source so its mtime moves past the FST's. Real wall-clock
        // skews are unreliable in tests, so set the mtime explicitly.
        final later = DateTime.now().add(const Duration(seconds: 30));
        File(source).setLastModifiedSync(later);

        final third = await cache.resolve(source);
        expect(third.fromCache, isFalse);
        expect(third.fstPath, decision.fstPath);
      },
    );

    test('reports stale cache when the source file grows', () async {
      final cache = buildCache();
      final source = writeSource();
      final decision = await cache.resolve(source);
      File(decision.fstPath).writeAsBytesSync(const [0x00]);
      await cache.recordSuccess(
        sourcePath: source,
        fstPath: decision.fstPath,
      );

      // Replace the source with a different-sized buffer but the same
      // mtime — the size-attribute check has to catch this.
      final sourceFile = File(source);
      final oldMTime = sourceFile.lastModifiedSync();
      sourceFile
        ..writeAsBytesSync(List<int>.generate(64, (i) => i & 0xff))
        ..setLastModifiedSync(oldMTime);

      final fresh = await cache.resolve(source);
      expect(fresh.fromCache, isFalse);
    });

    test(
      'falls back to app cache when the source directory is read-only',
      () async {
        // NTFS ignores Unix mode bits, and Git-for-Windows ships a `chmod` that
        // exits 0 without making the directory read-only — so the write-probe
        // still succeeds and this scenario can't be reproduced on Windows.
        if (Platform.isWindows) {
          markTestSkipped(
            'read-only directory via chmod is not reproducible on NTFS',
          );
          return;
        }
        // Create a read-only subdirectory; the write-probe should fail.
        final roDir = Directory(p.join(tempRoot.path, 'readonly'))
          ..createSync();
        final source = File(p.join(roDir.path, 'archive.lxt2'))
          ..writeAsBytesSync([1, 2, 3]);
        try {
          Process.runSync('chmod', ['a-w', roDir.path]);
        } on Object {
          markTestSkipped('chmod not available on this platform');
          return;
        }

        try {
          final cache = buildCache();
          final decision = await cache.resolve(source.path);
          expect(
            decision.isSibling,
            isFalse,
            reason:
                'expected the sibling-write probe to fail and route to '
                'the app-cache fallback',
          );
          expect(
            p.isWithin(appCache.path, decision.fstPath),
            isTrue,
            reason:
                'fallback FST must live under the resolved appCacheDir; got '
                '${decision.fstPath}',
          );
          expect(decision.fromCache, isFalse);
        } finally {
          // Restore writability so the tearDown cleanup can delete the dir.
          Process.runSync('chmod', ['u+w', roDir.path]);
        }
      },
    );

    test('the app-cache filename is deterministic per source path', () async {
      final cache = buildCache();
      final a = await cache.appCacheFstPathForTest('/some/where/a.lxt2');
      final aAgain = await cache.appCacheFstPathForTest('/some/where/a.lxt2');
      final b = await cache.appCacheFstPathForTest('/some/where/b.lxt2');
      expect(a, aAgain);
      expect(a, isNot(b));
      expect(p.extension(a), '.fst');
    });
  });
}
