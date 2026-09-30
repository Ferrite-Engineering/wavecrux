// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';

/// In-memory [HostBridgeTransport] — the reference double for the editor-host
/// bridge, the telemetry relay, and the transport seam's own test.
///
/// The production transport is chosen by a conditional export and cannot be
/// substituted, which is exactly why the seam exists: without this, every
/// inbound-dispatch assertion would need a browser.
class FakeHostBridgeTransport implements HostBridgeTransport {
  /// Pretends to be [hostKind], posting to [posted] when [canPost].
  FakeHostBridgeTransport({
    this.hostKind = EditorHostKind.vscode,
    bool canPost = true,
  }) : _canPost = canPost;

  final _controller = StreamController<Map<String, Object?>>.broadcast();
  final bool _canPost;

  /// Every frame the app posted, in order.
  final List<Map<String, Object?>> posted = <Map<String, Object?>>[];

  @override
  final EditorHostKind hostKind;

  @override
  bool get canPost => _canPost;

  @override
  Stream<Map<String, Object?>> get inbound => _controller.stream;

  @override
  void post(Map<String, Object?> frame) {
    // Mirrors the real channel: a transport that cannot reach the host drops
    // the frame rather than finding another way to send it.
    if (!_canPost) return;
    posted.add(frame);
  }

  /// Simulates the host posting [frame] into the webview.
  void deliver(Map<String, Object?> frame) => _controller.add(frame);

  @override
  void dispose() => unawaited(_controller.close());
}
