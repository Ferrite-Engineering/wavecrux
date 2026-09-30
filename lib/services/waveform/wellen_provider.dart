// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Conditional re-export shim for [WellenProvider].
///
/// On `dart:io` hosts (desktop, iOS, Android) this resolves to the real
/// `dart:ffi`-backed implementation in [wellen_provider_io.dart]. On
/// Flutter Web (no `dart:io`) it resolves to the no-op stub in
/// [wellen_provider_stub.dart] so the rest of the app can name
/// [WellenProvider] uniformly across all build targets.
///
/// Production code never imports `_io.dart` or `_stub.dart` directly —
/// it imports this file and gets the right implementation for the
/// active build target. Web consumers gate their actual *use* of
/// [WellenProvider] behind a `kIsWeb` runtime check (the architecture
/// mandates [WellenWasmProvider] on web), so the stub's `UnsupportedError`
/// throws should never fire in practice.
///
/// Mirrors the pattern in [ffi_decoder_loader.dart].
library;

export 'wellen_provider_stub.dart'
    if (dart.library.io) 'wellen_provider_io.dart';
