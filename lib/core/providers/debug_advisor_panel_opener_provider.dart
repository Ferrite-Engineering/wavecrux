// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens (or toggles) the Debug Advisor suggestions panel for the active
/// surface. The panel itself is a Pro-tier feature, so the open-core
/// default is a no-op and the closed-source Pro overlay
/// provides the real implementation.
typedef DebugAdvisorPanelOpener = void Function(BuildContext context);

/// Open-core extension point through which the Pro overlay registers a
/// callback for opening the Debug Advisor panel.
///
/// The open-core viewer dispatches `ShortcutAction.debugAdvisorTogglePanel`
/// to whatever is bound here. The default opener is a no-op so Open Core
/// builds — which include the action in their menu bar / overflow menu /
/// command palette for discoverability — silently absorb the action.
///
/// The Pro overlay overrides this provider with a callback that opens its
/// `DebugAdvisorPanel` (typically as a side sheet on tablet/desktop, modal
/// bottom sheet on phone). The opener receives the active `BuildContext`
/// so it can `showModalBottomSheet` / `showDialog` / push a route as
/// appropriate.
final debugAdvisorPanelOpenerProvider = Provider<DebugAdvisorPanelOpener>(
  (_) => (context) {
    // Open-core no-op. The Pro overlay overrides this with a callback
    // that mounts the Debug Advisor panel.
  },
);
