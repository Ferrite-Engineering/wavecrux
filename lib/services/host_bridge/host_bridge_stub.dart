// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Non-web stub for [HostBridgeChannel].
//
// An editor host can only exist on the web build — the extension pack hosts
// WaveCrux in a VSCode webview, which is Flutter Web — so on desktop, mobile
// and the VM test runner there is nothing on the other end of the bridge by
// construction. This stub says so: no host, no inbound frames, nothing posted.
//
// It deliberately does NOT throw, unlike [wellen_wasm_provider_stub.dart].
// A `UnsupportedError` there marks a call that should never happen (the
// architecture mandates the FFI provider off the web); here the off-web case is
// the overwhelmingly common one and "there is no editor host" is the honest,
// useful answer. Every caller is written against that answer, which is why the
// bridge needs no `kIsWeb` guards of its own.
//
// Mirrors the pattern in [lxt2fst_converter_stub.dart].

import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';

/// Inert [HostBridgeChannel] for hosts with no `window.postMessage`.
class HostBridgeChannel implements HostBridgeTransport {
  /// Creates the inert channel. Installs nothing and allocates nothing.
  HostBridgeChannel();

  /// Reads the editor-host marker. Always [EditorHostKind.none] off the web —
  /// there is no `window` to have set one.
  ///
  /// Static, synchronous and side-effect free so `bootstrap` can ask before it
  /// builds the root container, which is the contract `editor_host_provider`'s
  /// doc comment relies on.
  static EditorHostKind detectHostKind() => EditorHostKind.none;

  /// Always [EditorHostKind.none]. See [detectHostKind].
  @override
  EditorHostKind get hostKind => EditorHostKind.none;

  /// Always `false` — there is no host to post to.
  @override
  bool get canPost => false;

  /// Never emits. Closed streams and empty streams behave identically for
  /// every consumer here, and an empty one costs no subscription bookkeeping.
  @override
  Stream<Map<String, Object?>> get inbound =>
      const Stream<Map<String, Object?>>.empty();

  /// Drops [message]. Silently: a build with no host has nothing to report and
  /// nothing to report it to.
  @override
  void post(Map<String, Object?> message) {}

  /// No-op — nothing was installed.
  @override
  void dispose() {}
}
