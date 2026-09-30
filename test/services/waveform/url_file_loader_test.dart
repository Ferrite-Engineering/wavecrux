// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/services/waveform/url_file_loader.dart';

class _MockClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('http://example.com'));
  });

  // ── isUrl ──────────────────────────────────────────────────────────────────

  group('UrlFileLoader.isUrl', () {
    test('returns true for https URL', () {
      expect(UrlFileLoader.isUrl('https://example.com/dump.vcd'), isTrue);
    });

    test('returns true for http URL', () {
      expect(
        UrlFileLoader.isUrl('http://ci.example.com/artifacts/out.vcd'),
        isTrue,
      );
    });

    test('returns false for filesystem path', () {
      expect(UrlFileLoader.isUrl('/home/user/dump.vcd'), isFalse);
    });

    test('returns false for Windows path', () {
      expect(UrlFileLoader.isUrl(r'C:\users\user\dump.vcd'), isFalse);
    });

    test('returns false for empty string', () {
      expect(UrlFileLoader.isUrl(''), isFalse);
    });
  });

  // ── filenameFromUrl ────────────────────────────────────────────────────────

  group('UrlFileLoader.filenameFromUrl', () {
    test('extracts last path segment', () {
      expect(
        UrlFileLoader.filenameFromUrl('https://example.com/artifacts/dump.vcd'),
        'dump.vcd',
      );
    });

    test('handles URL with query parameters', () {
      expect(
        UrlFileLoader.filenameFromUrl(
          'https://ci.example.com/output.vcd?token=abc',
        ),
        'output.vcd',
      );
    });

    test('falls back when URL has no path segment', () {
      expect(
        UrlFileLoader.filenameFromUrl('https://example.com'),
        'waveform.vcd',
      );
    });

    test('falls back for URI that triggers FormatException', () {
      // ":::" is one of the few inputs that causes Uri.parse to throw.
      expect(
        UrlFileLoader.filenameFromUrl(':::'),
        'waveform.vcd',
      );
    });

    test('uses last non-empty segment for trailing slash', () {
      expect(
        UrlFileLoader.filenameFromUrl('https://example.com/files/dump.fst/'),
        'dump.fst',
      );
    });
  });

  // ── fetchFile ──────────────────────────────────────────────────────────────

  group('UrlFileLoader.fetchFile', () {
    late _MockClient mockClient;
    late UrlFileLoader loader;

    setUp(() {
      mockClient = _MockClient();
      loader = UrlFileLoader(clientFactory: () => mockClient);
    });

    test('returns bytes and filename on 200 response', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response.bytes(bytes, 200),
      );
      when(() => mockClient.close()).thenReturn(null);

      final result = await loader.fetchFile(
        'https://example.com/artifacts/dump.vcd',
      );

      expect(result.bytes, bytes);
      expect(result.filename, 'dump.vcd');
      verify(() => mockClient.close()).called(1);
    });

    test('throws UrlFetchException on non-200 status', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Not Found', 404),
      );
      when(() => mockClient.close()).thenReturn(null);

      expect(
        () => loader.fetchFile('https://example.com/missing.vcd'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            contains('404'),
          ),
        ),
      );
    });

    test('closes client even on error', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Server Error', 500),
      );
      when(() => mockClient.close()).thenReturn(null);

      await expectLater(
        loader.fetchFile('https://example.com/file.vcd'),
        throwsA(isA<UrlFetchException>()),
      );

      verify(() => mockClient.close()).called(1);
    });

    test('wraps network exception in UrlFetchException', () async {
      when(
        () => mockClient.get(any()),
      ).thenThrow(Exception('Connection refused'));
      when(() => mockClient.close()).thenReturn(null);

      await expectLater(
        loader.fetchFile('https://example.com/file.vcd'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            contains('Connection refused'),
          ),
        ),
      );

      verify(() => mockClient.close()).called(1);
    });

    test('UrlFetchException.toString includes reason', () {
      const e = UrlFetchException('HTTP 403: Forbidden');
      expect(e.toString(), contains('HTTP 403: Forbidden'));
    });
  });
}
