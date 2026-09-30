// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'diagnostics_providers.g.dart';

/// Whether the diagnostics surfaces (Tab Diagnostics drawer, App Diagnostics
/// dialog, Pane Render Stats popover) are currently accessible.
///
/// The diagnostics surfaces ship in every build (debug, profile, and release)
/// because they are part of the Open Core feature set — engineers reviewing a
/// waveform on a colleague's machine, on mobile, or in a release build all
/// benefit from being able to inspect file stats, signal health, and parser
/// behavior. Toolbar / menu / command-palette / drawer entries gate visibility
/// on this provider rather than checking `kDebugMode` directly so the rule
/// lives in one place.
///
/// Renamed from `diagnosticsAvailableProvider` — the rename
/// reflects that the provider gates the three diagnostics surfaces
/// uniformly (see `docs/ARCHITECTURE.md` §8.8).
@Riverpod(keepAlive: true)
bool diagnosticsEnabled(Ref ref) => true;
