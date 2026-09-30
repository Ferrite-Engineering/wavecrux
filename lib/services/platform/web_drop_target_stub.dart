// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// No-op WebDropTarget for non-web platforms.
// The [files] stream never emits; [enable] and [disable] are no-ops.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Carries the bytes and filename of a file dropped onto the browser window.
@immutable
class WebDropFile {
  const WebDropFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Listens for file drag-and-drop events at the document (window) level.
///
/// On non-web platforms this is a no-op: [files] never emits and [enable] /
/// [disable] do nothing. The same API surface is provided on web by
/// `web_drop_target_impl.dart`.
class WebDropTarget {
  final _controller = StreamController<WebDropFile>.broadcast();

  /// Stream of files dropped onto the browser window.
  ///
  /// On non-web platforms this stream never emits.
  Stream<WebDropFile> get files => _controller.stream;

  /// Starts listening for drag-and-drop events. No-op on non-web.
  void enable() {}

  /// Stops listening for drag-and-drop events. No-op on non-web.
  void disable() {}

  /// Closes the stream. Call once when the owner is disposed.
  void dispose() => _controller.close();
}
