// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/plugins/bottom_dock_tab.dart';

/// Open-core extension point through which the Pro overlay contributes
/// additional bottom-dock tabs to the viewer's priority chain.
///
/// The open-core default returns an empty list. The Pro overlay's
/// `proOverrides` replaces this provider with one that returns the
/// Pro-tier tabs (notably the SVA assertion summary panel). Each tab
/// carries its own visibility provider, license-tier gate, and panel
/// builder — see [BottomDockTab] for the full contract.
///
/// The viewer's `_buildBottomPanelContent` consults this provider after
/// checking the cocotb log panel flag; the first contributed tab whose
/// `visibilityProvider` is `true` and whose `requiredTier` is satisfied
/// is rendered. If no contributed tab is active, the viewer falls back
/// to the default transaction table panel.
final extraBottomDockTabsProvider = Provider<List<BottomDockTab>>(
  (_) => const [],
);
