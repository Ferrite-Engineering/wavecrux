// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Web implementation of WebDropTarget using package:web + dart:js_interop.
// Exported by web_drop_target.dart when dart.library.js_interop is available.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Carries the bytes and filename of a file dropped onto the browser window.
@immutable
class WebDropFile {
  const WebDropFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Listens for file drag-and-drop events at the document (window) level.
///
/// Call [enable] once to start intercepting drops (typically in `initState`),
/// and [disable] / [dispose] when the owning widget is torn down.
class WebDropTarget {
  final _controller = StreamController<WebDropFile>.broadcast();
  web.EventListener? _overListener;
  web.EventListener? _dropListener;

  /// Stream of files dropped onto the browser window.
  Stream<WebDropFile> get files => _controller.stream;

  /// Attaches document-level `dragover` and `drop` listeners.
  void enable() {
    _overListener = (web.Event e) {
      e.preventDefault();
    }.toJS;
    _dropListener = (web.Event e) {
      e.preventDefault();
      final drop = e as web.DragEvent;
      final fileList = drop.dataTransfer?.files;
      if (fileList == null || fileList.length == 0) return;
      _readFile(fileList.item(0)!);
    }.toJS;

    web.document.addEventListener('dragover', _overListener);
    web.document.addEventListener('drop', _dropListener);
  }

  void _readFile(web.File file) {
    final reader = web.FileReader();
    reader
      ..addEventListener(
        'load',
        (web.Event _) {
          final result = reader.result;
          if (result == null) return;
          final buffer = result as JSArrayBuffer;
          final bytes = buffer.toDart.asUint8List();
          if (!_controller.isClosed) {
            _controller.add(WebDropFile(bytes: bytes, name: file.name));
          }
        }.toJS,
      )
      ..readAsArrayBuffer(file);
  }

  /// Detaches document-level event listeners.
  void disable() {
    if (_overListener != null) {
      web.document.removeEventListener('dragover', _overListener);
      _overListener = null;
    }
    if (_dropListener != null) {
      web.document.removeEventListener('drop', _dropListener);
      _dropListener = null;
    }
  }

  /// Detaches listeners and closes the stream.
  void dispose() {
    disable();
    unawaited(_controller.close());
  }
}
