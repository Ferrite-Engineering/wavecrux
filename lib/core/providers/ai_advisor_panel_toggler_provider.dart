// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Callback invoked when the user fires
/// `ShortcutAction.aiAdvisorTogglePanel`. Mirrors the
/// `svaPanelTogglerProvider` / `debugAdvisorPanelOpenerProvider` pattern: the
/// open-core `_handleShortcut` simply calls
/// `ref.read(aiAdvisorPanelTogglerProvider)(context)` and the closed-source
/// Pro overlay supplies a concrete implementation that flips the
/// AI Waveform Assistant panel's visibility provider — routing through
/// `FeatureGate.isAvailable(LicenseTier.pro, …)` so a post-beta unlicensed user
/// gets the upgrade dialog instead of an inert toggle.
///
/// The open-core default is a no-op — Open-Core builds expose the action for
/// discoverability through the menu bar, overflow menu, and command palette
/// (badged PRO via the action descriptor), but invoking it without the Pro
/// overlay installed simply does nothing. This keeps tier gating concentrated
/// in the Pro overrides rather than forking the viewer to special-case
/// Pro-only actions. The agentic AI Advisor itself (the `AiModelClient` +
/// `AiToolRegistry` tool-use loop and its panel) lives entirely in the
/// Pro overlay; open-core ships only this seam plus the
/// `AiModelClient`/`AiToolRegistry` extension points it consumes.
typedef AiAdvisorPanelToggler = void Function(BuildContext context);

/// Open-core extension point through which the Pro overlay supplies the body of
/// the AI Waveform Assistant panel toggle action. See [AiAdvisorPanelToggler]
/// for the contract.
final aiAdvisorPanelTogglerProvider = Provider<AiAdvisorPanelToggler>(
  (_) => (_) {},
);
