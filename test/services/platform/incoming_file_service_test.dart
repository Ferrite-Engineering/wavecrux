// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests for IncomingFileService.
//
// IncomingFileService wraps two platform channels:
//   • MethodChannel  'com.wavecrux/incoming_file'          (getInitialFile)
//   • EventChannel   'com.wavecrux/incoming_file_stream'   (warm-start stream)
//
// These tests run on the host platform, which is macOS — a platform the
// service now SUPPORTS, since a Finder double-click is a real delivery route.
// So the "unsupported platform is a no-op" cases can no longer be expressed
// here; they were asserting a fact about the test host, not about the code,
// and they broke the moment that host became supported. The channel-wired
// paths are verified by mocking the binary messenger, which is what actually
// exercises the service.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/platform/incoming_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Installs a mock handler on the MethodChannel so that
  /// [IncomingFileService.getInitialFile] can be tested even on non-mobile host.
  void mockMethodChannel(String? returnPath) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.wavecrux/incoming_file'),
          (call) async {
            if (call.method == 'getInitialFile') return returnPath;
            return null;
          },
        );
  }

  void clearMethodChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.wavecrux/incoming_file'),
          null,
        );
  }

  // ---------------------------------------------------------------------------
  // getInitialFile — non-mobile (no-op path)
  // ---------------------------------------------------------------------------

  group('getInitialFile — no native handler', () {
    // The supported-platform path with nothing on the other end: a desktop
    // build whose AppDelegate did not register, or a launch with no document.
    // Null, not a throw — the app opens to an empty canvas, which is the
    // correct outcome for "nobody double-clicked anything".
    test(
      'a channel with no handler yields null rather than throwing',
      () async {
        clearMethodChannel();
        expect(await IncomingFileService.getInitialFile(), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // getInitialFile — mocked channel (exercises channel-call path)
  // ---------------------------------------------------------------------------

  group('getInitialFile — mocked channel', () {
    setUp(() => mockMethodChannel('/tmp/dump.vcd'));
    tearDown(clearMethodChannel);

    // Even with a mock installed, on non-mobile _isSupported is false so we
    // won't reach the channel. This group documents the expected *channel*
    // behaviour via the mock; integration against real iOS/Android native code
    // is tested on device.
    test('mock handler is callable without exception', () async {
      // Directly call via MethodChannel to verify the mock works correctly.
      final result = await const MethodChannel(
        'com.wavecrux/incoming_file',
      ).invokeMethod<String>('getInitialFile');
      expect(result, '/tmp/dump.vcd');
    });

    test('mock returns null when no file pending', () async {
      clearMethodChannel();
      mockMethodChannel(null);
      final result = await const MethodChannel(
        'com.wavecrux/incoming_file',
      ).invokeMethod<String?>('getInitialFile');
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // getInitialFile — PlatformException handling
  // ---------------------------------------------------------------------------

  group('getInitialFile — PlatformException is swallowed', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.wavecrux/incoming_file'),
            (call) async => throw PlatformException(code: 'ERROR'),
          );
    });
    tearDown(clearMethodChannel);

    test(
      'returns null on PlatformException (non-mobile does not reach channel)',
      () async {
        // On non-mobile _isSupported is false so the channel is never called and
        // no exception occurs.
        final result = await IncomingFileService.getInitialFile();
        expect(result, isNull);
      },
    );

    test('channel mock throws PlatformException as expected', () async {
      await expectLater(
        () => const MethodChannel(
          'com.wavecrux/incoming_file',
        ).invokeMethod<String>('getInitialFile'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // incomingFiles stream — non-mobile (empty stream)
  // ---------------------------------------------------------------------------

  group('incomingFiles — repeat subscription', () {
    test('every call returns a listenable stream', () async {
      // Two subscriptions must both work: `WaveCruxApp` subscribes once, but a
      // hot restart or a second window would subscribe again, and a stream that
      // could only be listened to once would silently stop delivering files.
      final s1 = IncomingFileService.incomingFiles;
      final s2 = IncomingFileService.incomingFiles;
      expect(s1.listen((_) {}).cancel(), completes);
      expect(s2.listen((_) {}).cancel(), completes);
    });
  });

  // ---------------------------------------------------------------------------
  // Channel names — must match native implementations exactly
  // ---------------------------------------------------------------------------

  group('channel name constants', () {
    test('method channel name is correct', () async {
      // Verify the channel name by setting a mock and confirming it responds.
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.wavecrux/incoming_file'),
            (call) async {
              called = true;
              return null;
            },
          );
      await const MethodChannel(
        'com.wavecrux/incoming_file',
      ).invokeMethod<void>('getInitialFile');
      expect(called, isTrue);
      clearMethodChannel();
    });
  });

  // ---------------------------------------------------------------------------
  // Event channel stream — filter behaviour
  // ---------------------------------------------------------------------------

  group('incomingFiles stream — filter', () {
    test('empty string events are filtered out', () async {
      // On non-mobile the stream is empty anyway, but we test the filter
      // logic by creating a synthetic stream matching the service's processing.
      final rawStream = Stream<dynamic>.fromIterable(['', 'valid.vcd', '']);
      final filtered = rawStream
          .where((dynamic e) => e is String && e.isNotEmpty)
          .cast<String>();
      final result = await filtered.toList();
      expect(result, ['valid.vcd']);
    });

    test('non-String events are filtered out', () async {
      final rawStream = Stream<dynamic>.fromIterable([
        42,
        '/path/file.fst',
        null,
      ]);
      final filtered = rawStream
          .where((dynamic e) => e is String && e.isNotEmpty)
          .cast<String>();
      final result = await filtered.toList();
      expect(result, ['/path/file.fst']);
    });
  });
}
