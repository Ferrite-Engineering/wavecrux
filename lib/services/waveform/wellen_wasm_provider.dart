// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Conditional re-export shim for [WellenWasmProvider].
///
/// On Flutter Web (`dart.library.js_interop` present and `kIsWeb == true`)
/// this resolves to the real WebAssembly-backed implementation in
/// [wellen_wasm_provider_web.dart]. On every other host it resolves to the
/// no-op stub in [wellen_wasm_provider_stub.dart].
///
/// Production code never imports `_web.dart` or `_stub.dart` directly — it
/// imports this file and gets the right implementation for the active build
/// target. Non-web consumers gate their actual *use* of [WellenWasmProvider]
/// behind a `kIsWeb` runtime check (the architecture mandates [WellenProvider]
/// on desktop/mobile), so the stub's `UnsupportedError` throws should never
/// fire in practice.
///
/// Mirrors the pattern in [wellen_provider.dart].
library;

export 'wellen_wasm_provider_stub.dart'
    if (dart.library.js_interop) 'wellen_wasm_provider_web.dart';
