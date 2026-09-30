// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/initial_file_path_provider.dart';
import 'package:wavecrux/core/initial_session_path_provider.dart';
import 'package:wavecrux/core/initial_streaming_provider.dart';
import 'package:wavecrux/features/settings/screens/settings_screen.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';

part 'router.g.dart';

/// Root navigator key. Held outside GoRouter so global shortcut handlers
/// (registered in [WaveCruxApp], above the navigator) can show dialogs against
/// the active route's context — important for Cmd+Shift+P, which is bound at
/// the [ShortcutManagerWidget] level above any screen-specific [Actions]
/// widget and therefore needs a context that reaches the live route.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'wavecrux_root_navigator',
);

/// Root [ScaffoldMessengerState] key. Held outside the widget tree so
/// app-lifecycle callbacks (workspace hydration, missing-file recovery) can
/// surface snackbars without owning a [BuildContext]. Wired into
/// [MaterialApp.router]'s `scaffoldMessengerKey`.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'wavecrux_root_messenger');

/// Deep-link redirect for OS-delivered file URLs.
///
/// On iOS, when a user drags a file onto the app or taps "Open With WaveCrux",
/// `FlutterSceneDelegate` forwards the URL through two paths:
///
///   (a) our explicit [IncomingFilePlugin.handleURL] in `SceneDelegate`, which
///       extracts `url.path` and emits it on the event channel — the path the
///       app processes.
///   (b) Flutter engine's default deep-link mechanism (via the parent
///       `super.scene(_:openURLContexts:)` call), which pushes the raw URL
///       string as a route location to the framework. `go_router` receives
///       `file:///Users/.../vlt_dump.vcd` and would otherwise throw
///       `GoException: no routes for location: file:///…`.
///
/// Path (b) cannot be cleanly suppressed without skipping the parent scene
/// call, which is needed for Flutter engine setup. This redirect catches the
/// `file://` location before route matching so `go_router` doesn't throw
/// `no routes for location: file://…`.
///
/// CRITICAL platform difference in what we do with the caught URL:
///
/// - **Desktop** (macOS/Windows/Linux): the `file://` path is a normal,
///   directly-readable filesystem path, so rewrite to `/viewer?file=<path>`
///   and open it here.
/// - **iOS / Android**: the raw `file://` path the engine hands over is a
///   *security-scoped* / not-yet-materialized location (Mail attachment in
///   `Library/Mail/AttachmentData`, an iCloud placeholder under
///   `com~apple~CloudDocs`, a Files-provider URL) that the app **cannot read
///   directly** — opening it fails with `Operation not permitted` (errno 1) or
///   `No such file` (errno 2). The openable copy comes from path (a):
///   `IncomingFilePlugin` copies the file into the app sandbox (via
///   `NSFileCoordinator`) and delivers *that* path on the event channel. So on
///   mobile we must **absorb the deep-link into the empty `/viewer`** and NOT
///   open the raw path — letting `IncomingFilePlugin` drive the actual open.
///   (The earlier assumption that (a) and (b) "end up at the same destination"
///   was wrong: (b) carried the raw path, (a) the sandbox copy — different
///   files, and (b) errored first.)
///
/// Monotonic counter stamped as the `req` token onto every desktop file-URL
/// rewrite. macOS delivers a Finder double-click / `open -a` / drag-to-Dock of
/// an *already-open* path as the IDENTICAL `file:///…` deep-link, and go_router
/// treats a target location equal to the current one as a no-op — so without a
/// changing token a second "Open With" of the file the viewer already shows
/// never reaches [ViewerScreen]'s `didUpdateWidget` and the open is silently
/// dropped (the macOS open-of-already-seen-path defect). A fresh token per
/// rewrite makes each open a
/// distinct location, mirroring the mobile `_incomingFileRequestCounter` in
/// [WaveCruxApp]. Reset via [debugResetFileUrlOpenSeq] in tests.
int _fileUrlOpenSeq = 0;

/// Resets the desktop file-open request counter. Test-only.
@visibleForTesting
void debugResetFileUrlOpenSeq() => _fileUrlOpenSeq = 0;

/// The router's full `redirect` decision, factored out of the [router] closure
/// so it can be unit-tested directly without spinning up a `GoRouterState`.
///
/// Two cases, in order:
///
///  1. **Legacy `/` root link → `/viewer`, preserving the query string.** Deep
///     links from older sessions, and a bare browser-address-bar
///     `<app>/?file=<url>` / `?session=<path>` on web, arrive with `path == '/'`.
///     They must land on `/viewer` (there is no Welcome route)
///     but **must keep their query parameters** — an unconditional `'/viewer'`
///     return silently dropped `?file=`/`?session=`, so a root-level `?file=`
///     deep link opened the empty canvas instead of the file. When there is no
///     query string, the bare `'/viewer'` rewrite is returned unchanged.
///  2. Otherwise defer to [fileUrlRedirect] for OS-delivered `file://` URLs.
///
/// [platform] is threaded through to [fileUrlRedirect] and is injectable for
/// tests; it defaults to [defaultTargetPlatform] there.
String? rootRedirect(Uri uri, {TargetPlatform? platform}) {
  if (uri.path == '/') {
    if (uri.hasQuery) {
      return Uri(
        path: '/viewer',
        queryParameters: uri.queryParameters,
      ).toString();
    }
    return '/viewer';
  }
  return fileUrlRedirect(uri, platform: platform);
}

/// Exposed as a top-level function (not a closure inside [router]) so the
/// rewrite logic can be unit-tested directly without spinning up a
/// `GoRouterState`. [platform] defaults to [defaultTargetPlatform] and is
/// injectable for tests.
String? fileUrlRedirect(Uri uri, {TargetPlatform? platform}) {
  if (uri.scheme == 'file' && uri.path.isNotEmpty) {
    final resolved = platform ?? defaultTargetPlatform;
    if (resolved == TargetPlatform.iOS || resolved == TargetPlatform.android) {
      // Absorb the deep-link; IncomingFilePlugin opens the sandbox copy.
      return '/viewer';
    }
    // Desktop: the file:// path is directly readable. Stamp a monotonic `req`
    // so repeat opens of the SAME path aren't collapsed to a go_router no-op
    // (see [_fileUrlOpenSeq]).
    _fileUrlOpenSeq++;
    return Uri(
      path: '/viewer',
      queryParameters: {'file': uri.path, 'req': '$_fileUrlOpenSeq'},
    ).toString();
  }
  return null;
}

/// Application router — kept alive for the lifetime of the app.
///
/// Reads [initialFilePathProvider], [initialSessionPathProvider],
/// [initialStdinModeProvider], and [initialPipePathProvider] once to set
/// [GoRouter.initialLocation]:
/// - `wavecrux dump.fst` → opens viewer with `?file=…`
/// - `wavecrux --session x.wavecrux` → opens viewer with `?session=…`
/// - `wavecrux dump.fst --session x.wavecrux` → viewer with `?session=…`
///   (session takes precedence; its `sourceFilePath` field is used)
/// - `wavecrux --stdin` or `wavecrux --interactive` → opens viewer in
///   streaming mode (reads VCD from stdin)
/// - `wavecrux --pipe /path/to/fifo` → opens viewer in streaming mode
///   (reads VCD from the named pipe)
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final initialFile = ref.read(initialFilePathProvider);
  final initialSession = ref.read(initialSessionPathProvider);
  final stdinMode = ref.read(initialStdinModeProvider);
  final pipePath = ref.read(initialPipePathProvider);

  String initialLocation;
  if (initialSession != null) {
    initialLocation = Uri(
      path: '/viewer',
      queryParameters: {'session': initialSession},
    ).toString();
  } else if (initialFile != null) {
    initialLocation = Uri(
      path: '/viewer',
      queryParameters: {'file': initialFile},
    ).toString();
  } else if (stdinMode || pipePath != null) {
    initialLocation = '/viewer';
  } else {
    // There is no Welcome screen — `/viewer` renders the
    // empty-canvas state when the workspace has no tabs.
    initialLocation = '/viewer';
  }

  return GoRouter(
    initialLocation: initialLocation,
    navigatorKey: rootNavigatorKey,
    // Maps legacy `/` links to `/viewer` (preserving any `?file=`/`?session=`
    // query string) and catches OS-delivered `file://` deep links. See
    // [rootRedirect].
    redirect: (context, state) => rootRedirect(state.uri),
    routes: [
      GoRoute(
        path: '/viewer',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['file'];
          final sessionPath = state.uri.queryParameters['session'];
          // `req` is the incoming-file open-request token (see
          // [ViewerScreen.openRequest]): go() is a no-op for an identical
          // location, so re-sharing the same file needs a changing token to
          // reach didUpdateWidget and re-run the open.
          final openRequest = state.uri.queryParameters['req'];
          return ViewerScreen(
            filePath: filePath,
            sessionPath: sessionPath,
            openRequest: openRequest,
          );
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // There is no `/diagnostics` route. The three
      // replacement surfaces (Tab Diagnostics drawer, App Diagnostics
      // dialog, Pane Render Stats popover) are opened over the viewer via
      // their `*.open` static methods rather than via top-level routes.
    ],
  );
}
