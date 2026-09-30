// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Conditional re-export shim for loading user-authored ISA encoding tables
/// off the filesystem.
///
/// On `dart:io` hosts this resolves to the real implementation in
/// `user_isa_tables_io.dart`. On Flutter Web it resolves to the stub, which
/// returns nothing: a browser build has no directory to scan, and the honest
/// answer there is an empty result rather than a failure.
///
/// Production code imports this file, never `_io.dart` or `_stub.dart`.
library;

export 'user_isa_tables_stub.dart'
    if (dart.library.io) 'user_isa_tables_io.dart';
