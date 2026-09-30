// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// tool/cors_fixture_server.dart
//
// Tiny standalone HTTP server that serves a fixture VCD over two routes —
// one with permissive CORS headers, one without — so
// `integration_test/web/web_url_file_load_test.dart` can drive WaveCrux's
// `?file=<url>` loader (`lib/services/waveform/url_file_loader.dart`)
// against a *genuinely cross-origin* fetch in a real browser.
//
// Why a separate process instead of something the test spins up itself: the
// web integration suite runs the target file compiled INTO the browser tab
// via `flutter drive -d web-server` — there is no `dart:io` inside that
// tab, so it cannot start an `HttpServer` itself. This script runs on the
// *host*, exactly like `chromedriver` already does in
// `tool/run_web_integration_tests.sh`, which starts this alongside it and
// stops both on exit.
//
// Routes (any path under a fixture's basename resolves the same fixture —
// only the CORS-vs-not branch matters):
//   GET /cors-ok/<name>       → 200, `Access-Control-Allow-Origin: *`
//   GET /cors-blocked/<name>  → 200, no CORS headers at all
//   anything else             → 404
//
// Usage:
//   dart run tool/cors_fixture_server.dart --port 8199
//   dart run tool/cors_fixture_server.dart --port 8199 --fixture test/fixtures/vcd/scalar_basics.vcd
//
// Prints "CORS fixture server listening on :<port>" once bound, then serves
// until killed (SIGINT/SIGTERM or the parent script's process-group kill).

import 'dart:io';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  final fixtureFile = File(opts.fixturePath);
  if (!fixtureFile.existsSync()) {
    stderr.writeln('Fixture not found: ${opts.fixturePath}');
    exitCode = 1;
    return;
  }
  final bytes = await fixtureFile.readAsBytes();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, opts.port);
  // Operator-facing status, mirrors chromedriver's own "Starting ChromeDriver
  // ... on port" banner that the runner script greps for readiness.
  // ignore: avoid_print
  print('CORS fixture server listening on :${server.port}');

  await for (final request in server) {
    final segments = request.uri.pathSegments;
    final corsMode = segments.isNotEmpty ? segments.first : null;
    final allowCors = corsMode == 'cors-ok';
    final blockCors = corsMode == 'cors-blocked';

    if (!allowCors && !blockCors) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType(
      'text',
      'plain',
      charset: 'utf-8',
    );
    if (allowCors) {
      request.response.headers.set('Access-Control-Allow-Origin', '*');
    }
    request.response.add(bytes);
    await request.response.close();
  }
}

class _Options {
  const _Options({required this.port, required this.fixturePath});
  final int port;
  final String fixturePath;
}

_Options _parseArgs(List<String> args) {
  var port = 8199;
  var fixturePath = 'test/fixtures/vcd/scalar_basics.vcd';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--port':
        port = int.parse(args[++i]);
      case '--fixture':
        fixturePath = args[++i];
    }
  }
  return _Options(port: port, fixturePath: fixturePath);
}
