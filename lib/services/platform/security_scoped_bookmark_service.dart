// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures macOS security-scoped bookmark failures into the issue-reporter
/// buffer — these explain "recent file won't reopen without re-picking" reports.
final _log = Logger('wavecrux.platform');

/// Manages macOS security-scoped bookmarks so a sandboxed app can reopen
/// previously user-selected files across launches without showing the file
/// picker again.
///
/// On all non-macOS platforms this is a transparent no-op: every method
/// returns immediately without making any platform channel calls.
///
/// ### Lifecycle
/// 1. User picks a file (picker grants access for this session).
/// 2. Call [saveBookmark] to persist the access right as a bookmark.
/// 3. On next launch, call [resolveAndStartAccessing] before reading the file.
/// 4. Call [stopAccessing] when the file is closed or the app exits.
///
/// Stale bookmarks (file moved/renamed) are handled gracefully: [resolveAndStartAccessing]
/// returns `false`, and the caller should fall back to showing the file picker.
class SecurityScopedBookmarkService {
  static const _channel = MethodChannel('com.wavecrux/security_bookmarks');
  static const _prefsPrefix = 'security_bookmark_';

  static bool get _isSupported => Platform.isMacOS;

  /// Persists a security-scoped bookmark for [path].
  ///
  /// Must be called while the app already has access to [path] (e.g., right
  /// after opening via the file picker or after a successful [resolveAndStartAccessing]).
  /// Silently ignores errors so a bookmark failure never surfaces to the user
  /// (worst case: the picker reappears on next launch).
  static Future<void> saveBookmark(String path) async {
    if (!_isSupported) return;
    try {
      final base64 = await _channel.invokeMethod<String>(
        'createBookmark',
        {'path': path},
      );
      if (base64 == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$path', base64);
    } on Exception catch (e) {
      // Non-fatal — worst case the picker reappears next launch.
      _log.warning('Failed to save security-scoped bookmark for "$path": $e');
    }
  }

  /// Resolves the stored bookmark for [path] and starts security-scoped access.
  ///
  /// Returns `true` if access was successfully granted (file can now be read),
  /// `false` if no bookmark exists for this path or the bookmark is invalid/stale.
  /// On non-macOS, always returns `true`.
  static Future<bool> resolveAndStartAccessing(String path) async {
    if (!_isSupported) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final base64 = prefs.getString('$_prefsPrefix$path');
      if (base64 == null) return false;
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'resolveBookmark',
        {'bookmark': base64},
      );
      return result != null;
    } on Exception catch (e) {
      // A platform error here (vs. a missing/stale bookmark, handled above)
      // means the file can't be reopened without re-picking — worth seeing.
      _log.warning(
        'Failed to resolve security-scoped bookmark for "$path": $e',
      );
      return false;
    }
  }

  /// Stops security-scoped access for [path].
  ///
  /// Must be balanced with each successful [resolveAndStartAccessing] call.
  /// Safe to call even if [resolveAndStartAccessing] was not called (no-op).
  static Future<void> stopAccessing(String path) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('stopAccessing', {'path': path});
    } on Exception catch (_) {
      // No-op.
    }
  }

  /// Removes the stored bookmark for [path] (e.g. when removing from recent files).
  static Future<void> removeBookmark(String path) async {
    if (!_isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefsPrefix$path');
  }
}
