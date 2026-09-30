// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/platform_utils.dart';

/// Whether this build can actually *execute* PRO/ENT-tier actions.
///
/// ## Why this exists
///
/// Open Core ships the full `ShortcutAction` enum, including the Pro and
/// Enterprise actions, but its handlers for them are empty closures — see the
/// "Open Core builds silently absorb these actions" arms in
/// `viewer_screen_shortcuts.dart` and the no-op opener providers
/// (`debugAdvisorPanelOpenerProvider`, `svaPanelTogglerProvider`,
/// `collaborationCommandHandlerProvider`, …). On desktop that is a deliberate
/// upsell: the item is badged PRO/ENT, and a user who taps it can go buy the
/// tier that makes it work.
///
/// On a mobile app store there is no such path, and an enabled menu item that
/// does nothing when tapped is not an upsell — it is an unfinished feature.
/// Apple rejected WaveCrux 0.1.0 (2) under App Store Review Guideline 2.2
/// ("complete, remove, or fully configure any partially implemented
/// features") for exactly this: a reviewer on an iPhone tapped badged items
/// like "Share Session" and "Convert PCAP to VCD" and nothing happened.
///
/// ## Semantics
///
/// `false` (the Open Core default on a mobile host) hides every action whose
/// `requiredTier` is not `openCore` from all discovery surfaces — overflow
/// menu, command palette, menu bar, toolbar. Not badged-and-disabled: hidden.
/// A disabled row still reads as a broken feature to a reviewer, and there is
/// nothing on mobile for a user to do about it.
///
/// `true` means the build implements those actions for real, so they render
/// normally with their tier badges. Desktop Open Core is `true` — the badge
/// there is honest advertising with a working upgrade path behind it.
///
/// ## Overriding
///
/// The Pro overlay overrides this to `true` when it ships a mobile
/// build, since its `proOverrides` replace all the no-op opener providers with
/// real implementations. That override is the entire reason this is a
/// provider rather than a bare `isMobileHostPlatform` check at the call
/// site — hardcoding the platform test would silently strip working features
/// out of a Pro mobile build.
final tierGatedActionsAvailableProvider = Provider<bool>(
  (ref) => !isMobileHostPlatform,
  name: 'tierGatedActionsAvailableProvider',
);
