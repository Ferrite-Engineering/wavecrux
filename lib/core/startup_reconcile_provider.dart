// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'startup_reconcile_provider.g.dart';

/// A one-shot completion signal for the cold-start workspace reconcile.
///
/// On launch, `bootstrap()` hydrates `workspaceProvider` from the persisted
/// `workspace.json` before the first frame (to avoid an empty-canvas flash),
/// which surfaces every saved tab as a chip. `_WaveCruxAppState`'s post-frame
/// `_restoreFromWorkspace` then reconciles those chips to the tabs that should
/// actually show (loading the active tab of each pane, deferring the rest,
/// closing dropped ones). That reconcile is asynchronous.
///
/// When the app is also launched with a file argument (e.g. double-clicking a
/// `.vcd` in Finder), `ViewerScreen` opens that file. It must do so *after* the
/// reconcile so it can de-duplicate against an already-restored copy (focus the
/// existing tab instead of opening a second one) and so its activation of the
/// opened file is the final word on focus. This completer is the barrier the
/// opener awaits: `_restoreFromWorkspace` completes it when the reconcile has
/// settled (including its early-exit paths), and `ViewerScreen` awaits
/// [Completer.future] before opening the CLI file(s).
///
/// `keepAlive` so the single instance is shared between `_WaveCruxAppState`
/// (the completer) and `ViewerScreen` (the awaiter). It completes exactly once
/// per app launch.
@Riverpod(keepAlive: true)
Completer<void> startupReconcile(Ref ref) => Completer<void>();
