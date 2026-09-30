// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Callback invoked when the user fires
/// `ShortcutAction.toggleSvaPanel`. Mirrors the
/// `debugAdvisorPanelOpenerProvider` pattern: the open-core
/// `_handleShortcut` simply calls
/// `ref.read(svaPanelTogglerProvider)(context)` and the Pro overlay
/// supplies a concrete implementation that flips the SVA panel's
/// visibility provider (and surfaces an upgrade dialog post-beta when
/// the tier gate denies activation).
///
/// The open-core default is a no-op — Open-Core builds expose the
/// shortcut for discoverability through the menu bar, overflow menu,
/// and command palette, but invoking it without the Pro overlay
/// installed simply does nothing. This avoids forking the viewer to
/// special-case Pro-only actions and keeps tier gating concentrated
/// in the Pro overrides.
typedef SvaPanelToggler = void Function(BuildContext context);

/// Open-core extension point through which the Pro overlay supplies
/// the body of the SVA panel toggle action. See [SvaPanelToggler] for
/// the contract.
final svaPanelTogglerProvider = Provider<SvaPanelToggler>((_) => (_) {});
