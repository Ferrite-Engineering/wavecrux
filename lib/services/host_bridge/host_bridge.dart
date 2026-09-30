// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Conditional re-export shim for [HostBridgeChannel].
///
/// On Flutter Web (`dart.library.js_interop` present) this resolves to the real
/// `window.postMessage` transport in [host_bridge_web.dart]. On every other
/// host — desktop, mobile, the analyzer, and the VM test runner — it resolves
/// to the inert stub in [host_bridge_stub.dart], which reports
/// `EditorHostKind.none`, never emits, and drops what it is asked to post.
///
/// Production code never imports `_web.dart` or `_stub.dart` directly; it
/// imports this file and gets the right transport for the build target. Unlike
/// [wellen_wasm_provider.dart], the stub here does **not** throw: a build with
/// no extension host on the other end is the normal case, not a misuse, so the
/// off-web behaviour is "there is no host" rather than `UnsupportedError`.
///
/// Only the transport is split. What crosses the boundary
/// ([host_bridge_messages.dart]) and what is done about it
/// ([editor_host_bridge.dart]) are platform-neutral and written once.
///
/// Mirrors the pattern in [wellen_provider.dart], [wellen_wasm_provider.dart]
/// and [lxt2fst_converter.dart].
library;

export 'host_bridge_stub.dart'
    if (dart.library.js_interop) 'host_bridge_web.dart';
