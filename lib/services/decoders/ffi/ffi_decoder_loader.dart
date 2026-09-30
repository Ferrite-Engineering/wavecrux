// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Conditional re-export shim for the user-contributed decoder plugin
/// loader.
///
/// On `dart:io` hosts (desktop, iOS, Android — though only desktop is
/// supported) this resolves to the real
/// `dart:ffi`-backed implementation in
/// `ffi_decoder_loader_io.dart`. On Flutter Web (`dart:html`) this
/// resolves to the no-op stub in `ffi_decoder_loader_stub.dart`.
///
/// Production code never imports `_io.dart` or `_stub.dart` directly —
/// it imports this file and gets the right implementation for the
/// active build target. Tests can construct an `FfiDecoderLoader`
/// directly when running on a desktop host.
///
/// The conditional re-export is the standard Flutter pattern for
/// platform-specific implementations.
library;

export 'ffi_decoder_loader_stub.dart'
    if (dart.library.io) 'ffi_decoder_loader_io.dart';
