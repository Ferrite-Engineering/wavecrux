// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/services/collaboration/collab_viewer_bridge.dart';

/// Owns the app-lifetime [CollabViewerBridge].
///
/// Read once at startup (see `app.dart`) to install the listeners that mirror
/// local cursor / viewport / marker changes into the active
/// [CollaborationService]. The bridge is inert until a collaborative session
/// is active, and a complete no-op in open-core where the default
/// [NoopCollaborationService] never starts a session — so reading this
/// provider unconditionally is safe on every platform.
///
/// This is a plain (kept-alive) [Provider]; the single `ref.read` at bootstrap
/// keeps it — and its subscriptions — installed for the lifetime of the
/// [ProviderScope]. The pattern mirrors `cxpSelectionEmitterProvider`.
final collabViewerBridgeProvider = Provider<CollabViewerBridge>((ref) {
  final bridge = CollabViewerBridge(ref: ref)..start();
  ref.onDispose(bridge.dispose);
  return bridge;
});
