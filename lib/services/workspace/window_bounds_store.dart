// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:path_provider/path_provider.dart';

/// Key under which the auto-managed workspace document stores the top-level
/// application [WindowBounds], inside the workspace `extras` map. Window
/// geometry is window-level (a window spans many tabs), so it lives on the
/// workspace root rather than in a per-tab `.wavecrux` session.
const String kWindowBoundsExtrasKey = 'windowBounds';

/// Default file name of the auto-managed workspace document. Mirrors
/// `WorkspaceService`'s default so [peekPersistedWindowBounds] reads the same
/// file the workspace provider hydrates from.
const String kWorkspaceFileName = 'workspace.json';

/// Extracts [WindowBounds] from a workspace `extras` map, or null when absent
/// or malformed.
WindowBounds? windowBoundsFromExtras(Map<String, Object?> extras) {
  final raw = extras[kWindowBoundsExtrasKey];
  return raw is Map<String, Object?> ? WindowBounds.fromJson(raw) : null;
}

/// Returns a copy of [extras] with [bounds] stored under
/// [kWindowBoundsExtrasKey], leaving every other entry untouched.
Map<String, Object?> extrasWithWindowBounds(
  Map<String, Object?> extras,
  WindowBounds bounds,
) => {...extras, kWindowBoundsExtrasKey: bounds.toJson()};

/// Side-effect-free peek at the persisted window geometry, read directly from
/// `{appSupportDir}/workspace.json` **before** the workspace provider hydrates
/// — so the restorer can size/position the window before its first show (no
/// visible jump).
///
/// Deliberately does **not** go through `WorkspaceService.load()`: that path
/// quarantines a corrupt document and records a recovery notice the provider's
/// own load is responsible for surfacing. This peek only parses JSON and reads
/// one key, never mutating anything on disk, and returns null on every failure
/// (missing file, invalid JSON, no bounds, web/path_provider unavailable).
///
/// [directoryFactory] and [fileName] are injectable for tests.
Future<WindowBounds?> peekPersistedWindowBounds({
  Future<Directory> Function()? directoryFactory,
  String fileName = kWorkspaceFileName,
}) async {
  try {
    final dir =
        await (directoryFactory?.call() ?? getApplicationSupportDirectory());
    final file = File('${dir.path}/$fileName');
    if (!file.existsSync()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) return null;
    final extras = decoded['extras'];
    if (extras is! Map<String, Object?>) return null;
    return windowBoundsFromExtras(extras);
  } on Object {
    return null;
  }
}
