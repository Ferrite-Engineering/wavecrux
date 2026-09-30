// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;

/// Re-export of the cross-suite [`crux_workspace`] multi-window flag.
///
/// When Flutter multi-window reaches the stable channel: flip the upstream
/// constant (in `crux_workspace`) to `true`, add the Riverpod seam providers
/// for the `TabDetachingDelegate` / `PanelPopOutDelegate` interfaces
/// (`lib/core/windowing/`, currently interface-only — the no-op default
/// providers were removed as dead code since nothing watched them), and
/// provide the concrete implementations in the Pro overlay via `proOverrides`.
/// See ARCHITECTURE.md §6.4 and flutter/flutter#177586.
const bool kMultiWindowAvailable = crux.kMultiWindowAvailable;
