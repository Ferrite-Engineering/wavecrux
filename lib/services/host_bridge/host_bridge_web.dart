// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Web [HostBridgeChannel] — the `window.postMessage` transport between this
// build and a VSCode extension host.
//
// Mirrors the shape of `web_drop_target_impl.dart`: a small `package:web` +
// `dart:js_interop` surface and nothing else. Everything about *what* is
// exchanged lives in `host_bridge_messages.dart`, and everything about what is
// done with it lives in `editor_host_bridge.dart`, so this file has exactly
// three jobs: read the marker, receive frames, post frames.
//
// ### Two globals, both set by the extension's shim
//
// `cruxEditorHost` — frozen `{kind, protocol}`, set in an inline `<head>`
// script *before* any tag that can load `main.dart.js`. That ordering is the
// contract `EditorHostKind`'s doc comment depends on: it is what makes the
// answer available synchronously at startup, so telemetry's `form_factor`
// never has to defer on it. Absent marker means no host. The user agent and
// the URL scheme are deliberately not consulted — a webview is free to imitate
// either, and a guessed `form_factor` is accepted by the ingestion Worker and
// reads as measurement forever after.
//
// `cruxHostBridge` — `{postMessage(frame)}`, the outbound seam. It has to be
// the shim's, not ours: `acquireVsCodeApi()` may be called **once** per webview
// and the shim already calls it (it needs the same channel for its diagnostics,
// which run before Dart exists). So this file does not call it at all — a
// second call throws, and the throw would land in app startup. When the seam is
// absent [canPost] is false and outbound traffic is dropped, which is the safe
// direction to fail: a hosted build that cannot reach the host must stay
// silent, never fall back to reporting on its own.

import 'dart:async';
import 'dart:js_interop';

import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';
import 'package:web/web.dart' as web;

// ── JS interop shape ─────────────────────────────────────────────────────────

@JS(kEditorHostMarkerGlobal)
external _EditorHostMarker? get _cruxEditorHost;

@JS('cruxHostBridge')
external _HostPoster? get _cruxHostBridge;

/// The frozen marker object. Both fields are read as `JSAny?` and converted
/// defensively: this is a value another script wrote, so a `String`-typed
/// binding would throw rather than report "not a host" if it were ever
/// something else.
extension type _EditorHostMarker._(JSObject _) implements JSObject {
  external JSAny? get kind;
  external JSAny? get protocol;
}

extension type _HostPoster._(JSObject _) implements JSObject {
  external void postMessage(JSAny? frame);
}

/// Web [HostBridgeChannel] over `window.postMessage`.
class HostBridgeChannel implements HostBridgeTransport {
  /// Creates the channel and, when an editor host is present, installs the
  /// `message` listener.
  ///
  /// Installing nothing in a plain browser tab is the first half of the
  /// security posture: a page that embeds wavecrux.app in an iframe can post
  /// whatever it likes and there is no listener to receive it. The second half
  /// is [isTrustedOrigin], applied to every frame that does arrive.
  HostBridgeChannel({bool Function(String origin)? isTrustedOrigin})
    : _isTrustedOrigin = isTrustedOrigin ?? defaultTrustedOrigin {
    if (hostKind != EditorHostKind.none) _install();
  }

  /// Reads `globalThis.cruxEditorHost.kind`. Synchronous, side-effect free, and
  /// safe to call before the root container exists — which `bootstrap` does.
  ///
  /// An absent marker, a marker whose `kind` is anything but
  /// [kEditorHostMarkerKindVscode], and a marker that is not an object at all
  /// all resolve to [EditorHostKind.none]. There is no error case: "no editor
  /// host" is the answer to every question this can fail to answer.
  static EditorHostKind detectHostKind() {
    try {
      final marker = _cruxEditorHost;
      if (marker == null) return EditorHostKind.none;
      final kind = marker.kind.dartify();
      if (kind != kEditorHostMarkerKindVscode) return EditorHostKind.none;
      return EditorHostKind.vscode;
    } on Object {
      return EditorHostKind.none;
    }
  }

  /// The marker's `protocol` field, or `null` when there is no marker.
  ///
  /// Reported for diagnostics only. A host that advertises a newer protocol is
  /// not refused: the frame decoder validates every field it reads, so an
  /// unknown addition is ignored the same way CXP ignores unknown payload keys.
  static int? detectHostProtocol() {
    try {
      final protocol = _cruxEditorHost?.protocol.dartify();
      return protocol is num ? protocol.toInt() : null;
    } on Object {
      return null;
    }
  }

  /// Whether a frame from [origin] may be acted on.
  ///
  /// Inside a webview the only origins in play are VSCode's own
  /// (`vscode-webview://<id>`) and the document's; an empty origin is what a
  /// same-document `postMessage` reports. Anything else is a page that is not
  /// the host, and is ignored.
  static bool defaultTrustedOrigin(String origin) {
    if (origin.isEmpty) return true;
    if (origin.startsWith('vscode-webview://')) return true;
    return origin == web.window.location.origin;
  }

  final bool Function(String origin) _isTrustedOrigin;
  final StreamController<Map<String, Object?>> _controller =
      StreamController<Map<String, Object?>>.broadcast();
  web.EventListener? _messageListener;

  /// The editor host driving this build. See [detectHostKind].
  @override
  EditorHostKind get hostKind => detectHostKind();

  /// Whether the outbound seam is present. False in a plain browser tab, and
  /// false in a webview whose shim has not published `cruxHostBridge`.
  @override
  bool get canPost =>
      hostKind != EditorHostKind.none && _cruxHostBridge != null;

  /// Well-formed frames the host posted, in arrival order.
  @override
  Stream<Map<String, Object?>> get inbound => _controller.stream;

  void _install() {
    _messageListener = (web.Event event) {
      try {
        // `isA` and not `is`: a JS interop `is` between two interop types is
        // always true and checks nothing.
        if (!event.isA<web.MessageEvent>()) return;
        final message = event as web.MessageEvent;
        if (!_isTrustedOrigin(message.origin)) return;
        final frame = hostBridgeStringMap(message.data.dartify());
        if (frame == null) return;
        if (!_controller.isClosed) _controller.add(frame);
      } on Object {
        // Untrusted input must never throw into the app. A frame we cannot
        // even shape-check is dropped, exactly like one that fails the
        // shape check.
      }
    }.toJS;
    web.window.addEventListener('message', _messageListener);
  }

  /// Posts [frame] to the extension host. Never throws; drops the frame when
  /// there is no seam to post through.
  @override
  void post(Map<String, Object?> frame) {
    if (!canPost) return;
    try {
      _cruxHostBridge?.postMessage(frame.jsify());
    } on Object {
      // A dead webview, a frozen seam, a value that will not clone: none of
      // them may surface in a feature flow.
    }
  }

  /// Removes the listener and closes the stream.
  @override
  void dispose() {
    if (_messageListener != null) {
      web.window.removeEventListener('message', _messageListener);
      _messageListener = null;
    }
    unawaited(_controller.close());
  }
}
