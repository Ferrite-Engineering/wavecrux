// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show Platform;

import 'package:window_manager/window_manager.dart';

/// Raises the window on Windows and Linux, where `initWindowChrome` has
/// started `window_manager`; a no-op anywhere else.
Future<void> bringWindowForward() async {
  if (!Platform.isWindows && !Platform.isLinux) return;
  try {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  } on Object {
    // Raising the window is a courtesy; the link opens either way.
  }
}
