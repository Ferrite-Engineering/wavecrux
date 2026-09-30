// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/web/web_url_file_load_test.dart
//
// `?file=<url>` loading with CORS (Flutter Web).
//
// `lib/services/waveform/url_file_loader.dart` fetches a waveform over
// HTTP/HTTPS on web — the primary use case is a CI report embedding a link
// like `https://wavecrux.app/?file=https://ci.example.com/run123/dump.vcd`.
// The fetch is a real browser `fetch()`/XHR (via `package:http`'s browser
// client), so it is genuinely subject to the browser's same-origin/CORS
// enforcement — a headless-Chrome `flutter drive` test can exercise that
// for real, unlike the file-picker/drag-drop tests in this directory, which
// stub their OS-level affordances because those genuinely cannot be driven
// without a full WebDriver session.
//
// This test does not type a URL with a `?file=` query into the browser's
// address bar — `flutter drive` boots the target at a fixed base URL, so
// there is no address bar to drive. The bare-root `<app>/?file=<url>`
// deep-link path itself (the `/` → `/viewer` redirect that must preserve the
// `?file=` query string) is covered by `rootRedirect` in
// `test/core/router_test.dart`; that redirect used to drop the query, and the
// fix + its regression tests landed alongside this file. What a unit test
// cannot exercise is the real browser `fetch()` + CORS enforcement + WASM
// parse that follows once the route carries the URL — that is what this file
// covers, injecting at the exact same seam every other "no OS affordance
// available" web test in this directory uses: `bootstrap(args: [...])`,
// mirroring the real desktop CLI contract (`wavecrux <path-or-url>`) that
// `lib/core/router.dart`'s `router` provider turns into `/viewer?file=<url>`
// via `initialFilePathProvider` — the very same route shape a `?file=` deep
// link produces once `rootRedirect` has preserved it. From there:
// `ViewerScreen.initState` → `_openInitialCliFiles` → `_openOrFocusFile` →
// `_openPath` → (`kIsWeb && UrlFileLoader.isUrl(path)`) → `_openFromUrl` →
// a real `UrlFileLoader().fetchFile(url)`.
//
// The URL points at `tool/cors_fixture_server.dart`, a standalone
// `dart:io.HttpServer` process `tool/run_web_integration_tests.sh` starts
// (and stops) alongside chromedriver — this test's own compiled-into-the-
// browser code has no `dart:io` and cannot serve anything itself. The
// server's port is threaded in via `--dart-define=CORS_FIXTURE_PORT=<port>`
// (the only way compile-time-constant configuration reaches code running
// inside the browser tab). It serves the same `test/fixtures/vcd/
// scalar_basics.vcd` every other web test in this directory already embeds,
// under two routes:
//   - `/cors-ok/scalar_basics.vcd`      → `Access-Control-Allow-Origin: *`
//   - `/cors-blocked/scalar_basics.vcd` → no CORS headers at all
// Both routes are on a different port than the Flutter web-server serving
// the app, so every request the app makes to either is genuinely
// cross-origin — real browser CORS enforcement, not a simulation.
//
// Gated to web only via `skip: !kIsWeb`.
//
// Run with (after `dart run tool/cors_fixture_server.dart --port 8199 &`):
//   flutter drive --target=integration_test/web/web_url_file_load_test.dart \
//     -d web-server --browser-name=chrome --headless \
//     --dart-define=CORS_FIXTURE_PORT=8199

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider.dart';
import 'web_app_driver.dart';

/// Port the standalone `tool/cors_fixture_server.dart` process is listening
/// on. Passed at compile time via `--dart-define` because this file is
/// compiled *into* the browser tab — it has no `dart:io`, so it cannot read
/// an environment variable or a config file to discover this at runtime.
/// Defaults to the same port `tool/run_web_integration_tests.sh` starts the
/// server on, so a local `flutter drive` run with no override still works.
const int _corsFixturePort = int.fromEnvironment(
  'CORS_FIXTURE_PORT',
  defaultValue: 8199,
);

String _fixtureUrl(String corsMode) =>
    'http://localhost:$_corsFixturePort/$corsMode/scalar_basics.vcd';

/// Polls up to a few seconds for a [WellenWasmProvider] to land on the
/// active tab's [waveformSourceProvider], returning it or `null` on timeout.
Future<WellenWasmProvider?> _pollForLoadedSource(WidgetTester tester) async {
  final root = rootContainer(tester);
  final tcm = root.read(tabContainerManagerProvider);
  for (var i = 0; i < 60; i++) {
    final activeTabId = root.read(activeTabIdProvider);
    final container = tcm.containerFor(activeTabId);
    final src = container.read(waveformSourceProvider).value;
    if (src is WellenWasmProvider) return src;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    '?file=<url> with permissive CORS fetches and loads the waveform',
    (tester) async {
      await seedFirstLaunchAnswers();
      await bootstrap(args: [_fixtureUrl('cors-ok')]);
      await tester.pump();
      await settleEmptyCanvas(tester);

      final loaded = await _pollForLoadedSource(tester);
      expect(
        loaded,
        isNotNull,
        reason:
            '?file=<url> must fetch the CORS-permissive URL and install a '
            'WellenWasmProvider on the active tab',
      );

      expect(loaded!.rootScopes, isNotEmpty);
      expect(loaded.rootScopes.first.name, equals('top'));
      expect(
        loaded.rootScopes.first.variables.map((v) => v.name).toSet(),
        equals({'clk', 'rst', 'data'}),
        reason: 'all declared signals must surface in the hierarchy tree',
      );

      // Value data, not just hierarchy — proves the fetched bytes were
      // actually parsed, not just a plausible-looking empty source.
      final clk = loaded.rootScopes.first.variables.firstWhere(
        (v) => v.name == 'clk',
      );
      await loaded.loadSignal(clk.signalRef);
      final changes = loaded.changesInRange(clk.signalRef, 0, loaded.endTime);
      expect(
        changes,
        isNotEmpty,
        reason: 'the fetched file must decode to real signal transitions',
      );

      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );

  testWidgets(
    '?file=<url> blocked by CORS surfaces a clear error, no crash',
    (tester) async {
      await seedFirstLaunchAnswers();
      await bootstrap(args: [_fixtureUrl('cors-blocked')]);
      await tester.pump();

      // The app surfaces `urlFileLoadError` via a SnackBar rather than
      // crashing or hanging. The `{reason}` half of the localized string is
      // browser-supplied and not worth pinning exactly, so match on the
      // fixed template prefix.
      //
      // Looked for FIRST, while it is on screen. The browser rejects the
      // fetch within a frame or two and the error snack then shows for its
      // standard six seconds; polling for a source that never arrives before
      // looking (six seconds of its own) meant the snack had always gone.
      final l10n = L10N.of(rootScaffoldMessengerKey.currentContext!);
      final errorPrefix = l10n.urlFileLoadError('').trimRight();
      final foundError = await pumpUntil(tester, () {
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '');
        return texts.any((t) => t.startsWith(errorPrefix));
      });
      expect(
        foundError,
        isTrue,
        reason:
            'a clear "$errorPrefix..." error must be shown for the '
            'CORS-blocked URL',
      );

      // The browser must reject the cross-origin fetch (no
      // Access-Control-Allow-Origin on this route), so no source ever loads.
      final loaded = await _pollForLoadedSource(tester);
      expect(
        loaded,
        isNull,
        reason:
            'a CORS-blocked URL must never install a waveform source '
            '(the fetch should fail, not silently succeed)',
      );

      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );
}
