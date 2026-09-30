// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/viewer/providers/waveform_identity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wellen_ffi_library_gate.dart';

/// Exercises the full FFI [WaveformSourceNotifier.openFile] success path
/// against a real fixture VCD. Complements the pure-unit error/cancel/close
/// coverage in `waveform_source_provider_test.dart`, which never reaches the
/// success transition (it only opens nonexistent paths).
void main() {
  if (!requireWellenFfiLibrary('openFile success path')) return;

  // SecurityScopedBookmarkService dispatches through SharedPreferences, which
  // needs the test binding initialised; the real wellen open uses FFI.
  TestWidgetsFlutterBinding.ensureInitialized();

  const fixture = 'test/fixtures/vcd/scalar_basics.vcd';

  // On macOS the security-scoped bookmark service reads SharedPreferences;
  // give it an empty mock store so resolveAndStartAccessing returns cleanly.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // openFile fires an unawaited off-thread content-hash computation that
  // ends with `ref.read(...)`. If the container is disposed before that
  // future settles it throws "Ref after dispose". Poll until the hash lands
  // so the fire-and-forget work finishes while the container is alive.
  Future<void> settleContentHash(ProviderContainer c) async {
    for (var i = 0; i < 100; i++) {
      if (c.read(waveformIdentityProvider) != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group(
    'WaveformSourceNotifier.openFile — success path',
    () {
      test('opens a real VCD and transitions to AsyncData(source)', () async {
        final container = ProviderContainer(
          overrides: [productTelemetryConfig],
        );
        addTearDown(container.dispose);
        final notifier = container.read(waveformSourceProvider.notifier);

        await notifier.openFile(fixture);

        final state = container.read(waveformSourceProvider);
        expect(state, isA<AsyncData<WaveformDataSource?>>());
        expect(state.value, isNotNull);
        expect(container.read(waveformIsLoadedProvider), isTrue);

        // Metadata captured on a successful parse.
        expect(notifier.currentFilePath, fixture);
        expect(notifier.lastAttemptedPath, fixture);
        expect(notifier.lastParseTime, isNotNull);
        expect(notifier.originalFormat, WaveformFormat.vcd);

        await settleContentHash(container);
        await notifier.close();
      });

      test('successful open publishes a content-hash identity', () async {
        final container = ProviderContainer(
          overrides: [productTelemetryConfig],
        );
        addTearDown(container.dispose);
        final notifier = container.read(waveformSourceProvider.notifier);

        await notifier.openFile(fixture);
        // The hash is computed off-thread after the parse; poll briefly for it.
        String? hash;
        for (var i = 0; i < 50; i++) {
          hash = container.read(waveformIdentityProvider);
          if (hash != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(hash, isNotNull, reason: 'content hash should be published');

        await notifier.close();
      });

      test('close after a successful open resets all metadata', () async {
        final container = ProviderContainer(
          overrides: [productTelemetryConfig],
        );
        addTearDown(container.dispose);
        final notifier = container.read(waveformSourceProvider.notifier);

        await notifier.openFile(fixture);
        expect(notifier.currentFilePath, isNotNull);

        await settleContentHash(container);
        await notifier.close();

        expect(notifier.currentFilePath, isNull);
        expect(notifier.lastParseTime, isNull);
        expect(notifier.originalFormat, isNull);
        expect(container.read(waveformSourceProvider).value, isNull);
        expect(container.read(waveformIdentityProvider), isNull);
      });

      test(
        'isSourceFileReplacedOnDisk is false right after a successful open '
        'and true once the on-disk file is rewritten',
        () async {
          final container = ProviderContainer(
            overrides: [productTelemetryConfig],
          );
          addTearDown(container.dispose);
          final notifier = container.read(waveformSourceProvider.notifier);

          // Work on a private copy so the shared fixture is never mutated —
          // this mirrors the mobile share-sheet import, which overwrites
          // Documents/SharedImports/<name> in place for same-named shares.
          final dir = await Directory.systemTemp.createTemp('wavecrux_stat');
          addTearDown(() => dir.delete(recursive: true));
          final copy = File('${dir.path}/dump.vcd')
            ..writeAsBytesSync(File(fixture).readAsBytesSync());

          await notifier.openFile(copy.path);
          expect(container.read(waveformSourceProvider).value, isNotNull);
          expect(notifier.sourceFileModifiedAt, isNotNull);
          expect(notifier.sourceFileSizeBytes, copy.lengthSync());
          expect(notifier.isSourceFileReplacedOnDisk(), isFalse);

          // Rewrite the file with different contents (size changes too).
          copy.writeAsStringSync(
            '${copy.readAsStringSync()}\n// replaced\n',
          );
          expect(notifier.isSourceFileReplacedOnDisk(), isTrue);

          await settleContentHash(container);
          await notifier.close();
        },
      );

      test(
        'isSourceFileReplacedOnDisk is false when nothing is loaded and when '
        'the file is missing from disk',
        () async {
          final container = ProviderContainer(
            overrides: [productTelemetryConfig],
          );
          addTearDown(container.dispose);
          final notifier = container.read(waveformSourceProvider.notifier);

          // Nothing loaded yet.
          expect(notifier.isSourceFileReplacedOnDisk(), isFalse);

          final dir = await Directory.systemTemp.createTemp('wavecrux_stat');
          addTearDown(() => dir.delete(recursive: true));
          final copy = File('${dir.path}/dump.vcd')
            ..writeAsBytesSync(File(fixture).readAsBytesSync());
          await notifier.openFile(copy.path);
          expect(notifier.isSourceFileReplacedOnDisk(), isFalse);

          // Let the fire-and-forget content-hash read finish before deleting:
          // on Windows a file still held open for hashing cannot be deleted
          // (errno 32, sharing violation).
          await settleContentHash(container);

          // Deleted file: the watcher owns that report, not the open path.
          copy.deleteSync();
          expect(notifier.isSourceFileReplacedOnDisk(), isFalse);

          await notifier.close();
        },
      );

      test(
        'content-hash completing after container dispose is a no-op',
        () async {
          final container = ProviderContainer(
            overrides: [productTelemetryConfig],
          );
          final notifier = container.read(waveformSourceProvider.notifier);

          await notifier.openFile(fixture);
          // Dispose without settling the unawaited content-hash future. When
          // it completes it must bail on `ref.mounted` rather than throw
          // "Cannot use the Ref after it has been disposed" (which the test
          // harness would report as a failure after completion). The hash may
          // occasionally win the race and land before dispose — that run
          // simply doesn't exercise the guard; it never falsely fails.
          container.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        },
      );

      test(
        'opening a new file after a successful open replaces the source',
        () async {
          final container = ProviderContainer(
            overrides: [productTelemetryConfig],
          );
          addTearDown(container.dispose);
          final notifier = container.read(waveformSourceProvider.notifier);

          await notifier.openFile(fixture);
          final first = container.read(waveformSourceProvider).value;
          expect(first, isNotNull);

          // Re-open the same path: the previous source is closed and a fresh one
          // installed (exercises the _activeSource?.close() pre-load branch).
          await notifier.openFile(fixture);
          final second = container.read(waveformSourceProvider).value;
          expect(second, isNotNull);
          expect(identical(first, second), isFalse);

          await settleContentHash(container);
          await notifier.close();
        },
      );

      test(
        'attachStreamingSource after a real open releases sandbox access',
        () async {
          final container = ProviderContainer(
            overrides: [productTelemetryConfig],
          );
          addTearDown(container.dispose);
          final notifier = container.read(waveformSourceProvider.notifier);

          // A real FFI open records the security-scoped accessing path on macOS;
          // a subsequent attachStreamingSource must release it (the
          // `_accessingPath != null` branch) and swap in the streaming source.
          await notifier.openFile(fixture);
          await settleContentHash(container);

          final streaming = _MockSource();
          when(streaming.close).thenReturn(null);
          notifier.attachStreamingSource(streaming);

          expect(container.read(waveformSourceProvider).value, same(streaming));
          expect(notifier.currentFilePath, isNull);
        },
      );

      test(
        "a malformed VCD surfaces wellen's reason as WaveformOpenException",
        () async {
          // Scalar value change "0 !" (value SPACE id) is invalid VCD; wellen
          // reports "expected an id for a value change". Before this work the
          // FFI swallowed that and reported a generic "Failed to open file".
          const malformed = 'test/fixtures/vcd/malformed_value_change.vcd';
          final container = ProviderContainer(
            overrides: [productTelemetryConfig],
          );
          addTearDown(container.dispose);
          final notifier = container.read(waveformSourceProvider.notifier);

          await notifier.openFile(malformed);

          final state = container.read(waveformSourceProvider);
          expect(state, isA<AsyncError<WaveformDataSource?>>());
          final error = (state as AsyncError).error;
          expect(error, isA<WaveformOpenException>());
          final reason = (error as WaveformOpenException).reason;
          // wellen's own message, not the generic fallback.
          expect(reason, isNot('Failed to open file'));
          expect(
            reason.toLowerCase(),
            anyOf(contains('id for a value change'), contains('vcd')),
          );
          // Clean toString for the error UI — no "Exception:" prefix.
          expect(error.toString(), reason);
        },
      );
    },
    skip: !File(fixture).existsSync(),
  );
}

/// Minimal in-memory source for the post-open attach path.
class _MockSource extends Mock implements WaveformDataSource {}
