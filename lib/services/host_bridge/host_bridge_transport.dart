// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The transport seam between this build and an editor extension host.
//
// Exists so the two halves of the bridge can be tested apart. The concrete
// [HostBridgeChannel] — `window.postMessage` on the web, an inert stub
// everywhere else — is chosen by a conditional export and cannot be
// substituted, which would otherwise make every inbound-dispatch test a browser
// test. `EditorHostBridge` and `HostRelayTelemetryService` therefore depend on
// this interface, and the VM suite drives them through a fake.
//
// Deliberately four members and no more. Anything richer would be a second
// place where "what the host and the app say to each other" is decided; that
// belongs in `host_bridge_messages.dart`, which both implementations and both
// consumers already share.

import 'package:wavecrux/domain/enums/editor_host_kind.dart';

/// What the editor-host bridge needs from a transport.
///
/// Implemented by `HostBridgeChannel` in both `host_bridge_web.dart` and
/// `host_bridge_stub.dart`; obtained through `hostBridgeChannelProvider`, which
/// is typed to this interface precisely so a test can override it.
abstract interface class HostBridgeTransport {
  /// The editor host on the other end, or [EditorHostKind.none].
  ///
  /// Resolved synchronously — the marker it reads is set before the Dart entry
  /// point loads — so nothing that depends on this ever has to defer. See
  /// [EditorHostKind].
  EditorHostKind get hostKind;

  /// Whether outbound frames can reach the host.
  ///
  /// False in a plain browser tab, and false in a webview whose shim has not
  /// published the outbound seam. A `false` here means outbound frames are
  /// dropped — never that a caller should find another way to send them.
  bool get canPost;

  /// Well-formed frames the host posted, in arrival order.
  ///
  /// Frames are untrusted: this stream carries string-keyed maps whose contents
  /// have been shape-checked and nothing more.
  Stream<Map<String, Object?>> get inbound;

  /// Posts [frame] to the host. Never throws, and silently drops the frame when
  /// [canPost] is false.
  void post(Map<String, Object?> frame);

  /// Releases whatever the transport installed.
  void dispose();
}
