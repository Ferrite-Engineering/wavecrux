// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Conditional re-export shim for [Lxt2FstConverter].
//
// Mirrors the [WellenProvider] / [WellenWasmProvider] split — on `dart:io`
// hosts (desktop, iOS, Android) this resolves to the real `dart:ffi`-backed
// implementation in [lxt2fst_converter_io.dart]; on Flutter Web it resolves
// to the `dart:js_interop`-backed implementation in
// [lxt2fst_converter_web.dart]. Off both rails (analyzer with no platform
// specified, unit tests on a host with neither) it resolves to the no-op
// stub in [lxt2fst_converter_stub.dart].
//
// Production code never imports the `_io`, `_web`, or `_stub` files
// directly — it imports this shim and gets the right backend for the
// active build target.

/// Conditional re-export shim — see file-level comment.
library;

export 'lxt2fst_converter_stub.dart'
    if (dart.library.js_interop) 'lxt2fst_converter_web.dart'
    if (dart.library.io) 'lxt2fst_converter_io.dart';
