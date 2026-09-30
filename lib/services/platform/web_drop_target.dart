// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Conditional export: on web use the package:web implementation;
// on all other platforms use the no-op stub.
export 'web_drop_target_stub.dart'
    if (dart.library.js_interop) 'web_drop_target_impl.dart';
