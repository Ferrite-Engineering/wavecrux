// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Fetches waveform files from HTTP/HTTPS URLs.
//
// The primary use case is CI/CD integration: a test report can embed a link
// to the hosted WaveCrux web app with a `?file=https://...` query parameter
// that causes WaveCrux to fetch and display the waveform automatically.
//
// CORS: the VCD/FST file server must set `Access-Control-Allow-Origin: *` (or
// the specific WaveCrux origin). Without CORS headers the browser will block
// the fetch on web.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The result of a successful URL file fetch.
@immutable
class UrlFetchResult {
  const UrlFetchResult({required this.bytes, required this.filename});

  /// Raw file bytes returned by the server.
  final Uint8List bytes;

  /// Display filename derived from the last URL path segment.
  final String filename;
}

/// Thrown when [UrlFileLoader.fetchFile] fails.
class UrlFetchException implements Exception {
  const UrlFetchException(this.reason);

  final String reason;

  @override
  String toString() => 'UrlFetchException: $reason';
}

/// Factory that produces an [http.Client]. Injected for unit testing.
typedef HttpClientFactory = http.Client Function();

/// Fetches a waveform file from an HTTP/HTTPS URL.
///
/// Instantiate with a custom [clientFactory] in tests to avoid real network
/// calls.
class UrlFileLoader {
  const UrlFileLoader({HttpClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultFactory;

  final HttpClientFactory _clientFactory;

  static http.Client _defaultFactory() => http.Client();

  /// Returns `true` when [value] is an HTTP or HTTPS URL.
  static bool isUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  /// Extracts a display filename from [url] (last non-empty path segment).
  ///
  /// Falls back to `'waveform.vcd'` when the URL has no path segment.
  static String filenameFromUrl(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      final name = segments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (name.isNotEmpty) return name;
    } on FormatException {
      // fall through
    }
    return 'waveform.vcd';
  }

  /// Fetches the file at [url] and returns its raw bytes.
  ///
  /// Throws [UrlFetchException] on HTTP errors (non-200 status) or network
  /// failures. Always closes the underlying client.
  Future<UrlFetchResult> fetchFile(String url) async {
    final client = _clientFactory();
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw UrlFetchException(
          'HTTP ${response.statusCode}: ${response.reasonPhrase ?? 'error'}',
        );
      }
      return UrlFetchResult(
        bytes: response.bodyBytes,
        filename: filenameFromUrl(url),
      );
    } on UrlFetchException {
      rethrow;
    } on Object catch (e) {
      throw UrlFetchException(e.toString());
    } finally {
      client.close();
    }
  }
}
