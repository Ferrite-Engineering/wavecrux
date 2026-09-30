// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/services/host_bridge/editor_host_bridge.dart';
import 'package:wavecrux/services/host_bridge/host_bridge.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';

part 'host_bridge_provider.g.dart';

/// The one [HostBridgeChannel] for this process.
///
/// `keepAlive` and root-scoped: the channel owns a `window` event listener and
/// the outbound seam, and a second one would double every inbound frame. Off
/// the web it resolves to the inert stub, which installs nothing — so this
/// provider is safe to read unconditionally on every platform, and callers
/// never have to ask `kIsWeb` first.
@Riverpod(keepAlive: true)
HostBridgeTransport hostBridgeChannel(Ref ref) {
  final channel = HostBridgeChannel();
  ref.onDispose(channel.dispose);
  return channel;
}

/// The editor-host bridge, started.
///
/// Read once during bootstrap, exactly like `cxpLifecycleBridgeProvider` and
/// `collabViewerBridgeProvider`: a `keepAlive` provider whose value is a
/// long-lived listener set, kept alive by that single read for the app's
/// lifetime.
///
/// [EditorHostBridge.start] is a no-op when there is no editor host, so reading
/// this on desktop, mobile or a plain browser tab costs one allocation and
/// installs nothing.
@Riverpod(keepAlive: true)
EditorHostBridge editorHostBridge(Ref ref) {
  final bridge = EditorHostBridge(
    ref: ref,
    channel: ref.watch(hostBridgeChannelProvider),
  )..start();
  ref.onDispose(bridge.dispose);
  return bridge;
}
