// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform/legacy_conversion_controller.dart';
import 'package:wavecrux/services/waveform/lxt2fst_cache.dart';
import 'package:wavecrux/services/waveform/lxt2fst_converter.dart';
import 'package:wavecrux/services/waveform/lxt2fst_providers.dart';

/// Spy [Lxt2FstConverter] that records every conversion request and emits
/// a deterministic synthetic progress stream. Does not touch the FFI.
class _SpyConverter extends Lxt2FstConverter {
  _SpyConverter() : super(libraryOpener: (_) => throw UnimplementedError());

  final List<({String inPath, String outPath})> calls = [];
  final List<List<ConversionProgress>> emittedProgress = [];

  @override
  Future<void> ensureLoaded() async {
    // No-op: the spy never touches the FFI.
  }

  @override
  Stream<ConversionProgress> convertPath({
    required String inPath,
    required String outPath,
  }) async* {
    calls.add((inPath: inPath, outPath: outPath));
    final ladder = <ConversionProgress>[
      const ConversionProgress(done: 0, total: 4),
      const ConversionProgress(done: 2, total: 4),
      const ConversionProgress(done: 4, total: 4),
    ];
    emittedProgress.add(ladder);
    for (final p in ladder) {
      yield p;
    }
    // Synthesize a non-empty FST so the wellen open later doesn't see an
    // empty file. Real wellen will reject it, but for this test we only
    // care that the converter was invoked, not that the file parses.
    File(outPath).writeAsBytesSync(const [0x00, 0x01, 0x02, 0x03]);
  }
}

ProviderContainer _buildContainer({
  required Lxt2FstConverter converter,
  required Lxt2FstCache cache,
}) {
  return ProviderContainer(
    overrides: [
      lxt2FstConverterProvider.overrideWithValue(converter),
      lxt2FstCacheProvider.overrideWithValue(cache),
    ],
  );
}

void main() {
  // SecurityScopedBookmarkService.resolveAndStartAccessing dispatches
  // through SharedPreferences, which needs the test binding initialised.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory appCache;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('lxt2-routing-test-');
    appCache = Directory(p.join(tempRoot.path, 'app-cache'))..createSync();
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  String writeLxt2(String name) {
    final f = File(p.join(tempRoot.path, name))
      ..writeAsBytesSync(
        Uint8List.fromList(<int>[0x13, 0x80, 0xab, 0xcd, 0xef, 0x12]),
      );
    return f.path;
  }

  String writeNonLegacy(String name) {
    final f = File(p.join(tempRoot.path, name))
      ..writeAsBytesSync(
        Uint8List.fromList(<int>[0x24, 0x64, 0x61, 0x74, 0x65]),
      );
    return f.path;
  }

  group('openFile() magic-byte routing', () {
    test('routes an .lxt2 file through the converter before wellen', () async {
      final converter = _SpyConverter();
      final cache = Lxt2FstCache(appCacheDirResolver: () async => appCache);
      final container = _buildContainer(converter: converter, cache: cache);
      addTearDown(container.dispose);

      final source = writeLxt2('archive.lxt2');
      // Probe the override surface explicitly: the test container must
      // resolve the spy through both providers, not the production
      // implementations.
      expect(container.read(lxt2FstConverterProvider), same(converter));
      expect(container.read(lxt2FstCacheProvider), same(cache));

      await container.read(waveformSourceProvider.notifier).openFile(source);
      final state = container.read(waveformSourceProvider);
      // Surface the error inside the assertion failure so we can see why
      // routing was skipped if the converter list is empty.
      expect(
        converter.calls.length,
        1,
        reason:
            'an .lxt2 source must invoke the converter exactly once; '
            'state after openFile = $state',
      );
      expect(converter.calls.first.inPath, source);
      expect(
        converter.calls.first.outPath,
        endsWith('.fst'),
        reason: 'converter is asked to emit FST',
      );
      expect(
        File(converter.calls.first.outPath).existsSync(),
        isTrue,
        reason: 'spy must have produced the cached FST on disk',
      );
      expect(
        container.read(waveformSourceProvider.notifier).originalFormat,
        WaveformFormat.lxt2,
        reason: 'origin must record LXT2 even after conversion routing',
      );
    });

    test('does NOT invoke the converter for a non-legacy file', () async {
      final converter = _SpyConverter();
      final cache = Lxt2FstCache(appCacheDirResolver: () async => appCache);
      final container = _buildContainer(converter: converter, cache: cache);
      addTearDown(container.dispose);

      final source = writeNonLegacy('regular.vcd');
      // wellen will fail on the 5-byte stub; we only assert the converter
      // was not consulted.
      await container.read(waveformSourceProvider.notifier).openFile(source);

      expect(converter.calls, isEmpty);
    });

    test('cache hit on second open does NOT re-invoke the converter', () async {
      final converter = _SpyConverter();
      final cache = Lxt2FstCache(appCacheDirResolver: () async => appCache);
      final container = _buildContainer(converter: converter, cache: cache);
      addTearDown(container.dispose);

      final source = writeLxt2('archive.lxt2');

      await container.read(waveformSourceProvider.notifier).openFile(source);
      expect(converter.calls.length, 1);

      // Second open: notifier should detect the sibling .fst + sidecar
      // and skip reconversion.
      await container.read(waveformSourceProvider.notifier).openFile(source);
      expect(
        converter.calls.length,
        1,
        reason: 'cached sibling .fst must short-circuit the converter',
      );
    });

    test('fresh open emits a [legacyConversionEventProvider] event '
        'with the cached FST path and the source acronym', () async {
      final converter = _SpyConverter();
      final cache = Lxt2FstCache(appCacheDirResolver: () async => appCache);
      final container = _buildContainer(converter: converter, cache: cache);
      addTearDown(container.dispose);

      final source = writeLxt2('event.lxt2');
      // Sink starts empty.
      expect(container.read(legacyConversionEventProvider), isNull);

      await container.read(waveformSourceProvider.notifier).openFile(source);

      final event = container.read(legacyConversionEventProvider);
      expect(event, isNotNull);
      expect(event!.origin, WaveformFormat.lxt2);
      expect(event.fstPath, converter.calls.single.outPath);
      expect(event.sequence, 1);
    });

    test('cache hit does NOT emit a fresh-conversion event (banner stays '
        'hidden on the second open)', () async {
      final converter = _SpyConverter();
      final cache = Lxt2FstCache(appCacheDirResolver: () async => appCache);
      final container = _buildContainer(converter: converter, cache: cache);
      addTearDown(container.dispose);

      final source = writeLxt2('cache.lxt2');

      // First open: fresh conversion → event present.
      await container.read(waveformSourceProvider.notifier).openFile(source);
      final firstEvent = container.read(legacyConversionEventProvider);
      expect(firstEvent, isNotNull);

      // Clear the sink so we can detect any *new* emit from the cache-hit path.
      container.read(legacyConversionEventProvider.notifier).clear();
      expect(container.read(legacyConversionEventProvider), isNull);

      // Second open hits the cache.
      await container.read(waveformSourceProvider.notifier).openFile(source);
      expect(converter.calls.length, 1);
      expect(
        container.read(legacyConversionEventProvider),
        isNull,
        reason: 'cache-hit re-opens must not emit a new banner event',
      );
    });

    test('touching the source after a cache hit forces reconversion', () async {
      final converter = _SpyConverter();
      final cache = Lxt2FstCache(appCacheDirResolver: () async => appCache);
      final container = _buildContainer(converter: converter, cache: cache);
      addTearDown(container.dispose);

      final source = writeLxt2('archive.lxt2');
      await container.read(waveformSourceProvider.notifier).openFile(source);
      expect(converter.calls.length, 1);

      // Push the source mtime past the cached FST.
      final future = DateTime.now().add(const Duration(minutes: 5));
      File(source).setLastModifiedSync(future);

      await container.read(waveformSourceProvider.notifier).openFile(source);
      expect(
        converter.calls.length,
        2,
        reason: 'stale cache must force reconversion on the next open',
      );
    });
  });

  group('progress events', () {
    test('emit monotonically non-decreasing (done, total) pairs that reach '
        '(N, N) at completion', () async {
      final converter = _SpyConverter();
      var prevDone = -1;
      var lastTotal = 0;
      ConversionProgress? terminal;

      final source = writeLxt2('progress.lxt2');
      final outPath = '${tempRoot.path}/progress.fst';
      await for (final p in converter.convertPath(
        inPath: source,
        outPath: outPath,
      )) {
        expect(
          p.done >= prevDone,
          isTrue,
          reason: 'progress must be monotonically non-decreasing',
        );
        prevDone = p.done;
        lastTotal = p.total;
        terminal = p;
      }
      expect(terminal, isNotNull);
      expect(
        terminal!.done,
        lastTotal,
        reason: 'final progress event must satisfy done == total',
      );
    });
  });
}
