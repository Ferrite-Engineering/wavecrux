// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Receives files the OS opens on the app's behalf — an iOS/Android share
/// sheet or "Open With", and a macOS Finder double-click, `open -a` or
/// drag-onto-the-Dock-icon.
///
/// On macOS the native half is `application(_:open:)` in `AppDelegate.swift`.
/// The path arrives directly readable: the desktop build is not sandboxed, so
/// unlike iOS there is no security-scoped URL to hold and no copy to make.
///
/// On iOS, files opened via `UIScene.openURLContexts` (warm start) or via
/// `UIScene.connectionOptions.urlContexts` (cold start) are forwarded here.
/// iOS copies incoming files to the app's `Documents/Inbox/` directory, so
/// the URL is always a local `file://` path accessible without a security scope.
///
/// On Android, `ACTION_VIEW` intents for `file://` and `content://` URIs are
/// handled. `content://` URIs (email attachments, cloud storage, Downloads) are
/// copied to the app's internal `files/incoming/` directory and the local path
/// is returned. This is required because the Rust wellen FFI layer expects a
/// real filesystem path and cannot read Android content URIs directly.
///
/// On Windows, Linux and web this is a transparent no-op: [getInitialFile]
/// always returns `null` and [incomingFiles] is an empty stream. Those
/// platforms receive files through `argv` instead.
///
/// ### Cold-start lifecycle
/// 1. Call [getInitialFile] once in `main()` after
///    `WidgetsFlutterBinding.ensureInitialized()`.
/// 2. If a non-null path is returned, override `initialFilePathProvider` before
///    `runApp` so the router opens directly to the viewer.
///
/// ### Warm-start lifecycle
/// 1. Subscribe to [incomingFiles] early (e.g. in `WaveCruxApp.initState`).
/// 2. When a path arrives, navigate to `/viewer?file=<path>`.
/// Captures mobile "open with" file-receipt failures into the issue-reporter
/// buffer (the share-sheet path is otherwise invisible when it breaks).
final _log = Logger('wavecrux.platform');

class IncomingFileService {
  static const _methodChannel = MethodChannel('com.wavecrux/incoming_file');
  static const _eventChannel = EventChannel(
    'com.wavecrux/incoming_file_stream',
  );

  /// macOS is here because a Finder double-click is a real delivery route, not
  /// because macOS is mobile. Its native half lives in `AppDelegate.swift`
  /// rather than a plugin class, and it hands over a directly readable path —
  /// no sandbox copy, no security scope.
  ///
  /// Windows and Linux stay out: neither has a native handler, and listing a
  /// platform here without one is how this silently did nothing on macOS.
  static bool get _isSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  /// Returns the absolute path of a file that cold-started the app, or `null`.
  ///
  /// Must be called after [WidgetsFlutterBinding.ensureInitialized].
  /// Should be called exactly once at app startup.
  static Future<String?> getInitialFile() async {
    if (!_isSupported) return null;
    try {
      return await _methodChannel.invokeMethod<String>('getInitialFile');
    } on MissingPluginException {
      // No native handler on the other end. `MissingPluginException` is NOT a
      // `PlatformException`, so it escaped the clause below — and this runs in
      // `main()`, which means an unhandled throw here is a failure to start.
      // Reachable wherever the channel is not registered: a widget test, a
      // host build, an embedder that skipped `MainFlutterWindow`. "Nobody
      // double-clicked anything" is the right answer, not a crash.
      return null;
    } on PlatformException catch (e) {
      _log.warning('Failed to read cold-start incoming file: ${e.message}');
      return null;
    }
  }

  /// Broadcast stream of absolute file paths opened while the app is running.
  ///
  /// Each event is a path to a waveform file (`.vcd`, `.fst`, `.ghw`) or a
  /// WaveCrux session file (`.wavecrux`). Only emits on iOS and Android;
  /// on all other platforms the stream never emits.
  static Stream<String> get incomingFiles {
    if (!_isSupported) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event is String && event.isNotEmpty)
        .cast<String>();
  }
}
