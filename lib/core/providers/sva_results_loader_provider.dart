// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Callback invoked when the user fires `ShortcutAction.loadSvaResults`.
/// Mirrors the [svaPanelTogglerProvider] / `debugAdvisorPanelOpenerProvider`
/// pattern: the open-core `_handleShortcut` simply calls
/// `ref.read(svaResultsLoaderProvider)(context)` and the Pro overlay supplies
/// a concrete implementation that prompts for a simulator assertion-log file,
/// parses it through the SVA result parser, force-opens the SVA bottom-dock
/// panel, and surfaces a load-error snackbar on failure (plus the post-beta
/// tier-gate upgrade dialog when activation is denied).
///
/// The open-core default is a no-op — Open-Core builds expose the action for
/// discoverability through the menu bar, overflow menu, and command palette,
/// but invoking it without the Pro overlay installed simply does nothing. This
/// keeps the viewer free of Pro-only special-casing and concentrates tier
/// gating in the Pro overrides.
typedef SvaResultsLoader = void Function(BuildContext context);

/// Callback invoked when the user fires `ShortcutAction.clearSvaResults`.
/// Unloads the currently-loaded SVA result file and hides the panel. Same
/// open-core-no-op / Pro-overridden contract as [SvaResultsLoader].
typedef SvaResultsClearer = void Function(BuildContext context);

/// Open-core extension point through which the Pro overlay supplies the body
/// of the "Load SVA Results" action. See [SvaResultsLoader] for the contract.
final svaResultsLoaderProvider = Provider<SvaResultsLoader>((_) => (_) {});

/// Open-core extension point through which the Pro overlay supplies the body
/// of the "Clear SVA Results" action. See [SvaResultsClearer] for the contract.
final svaResultsClearerProvider = Provider<SvaResultsClearer>((_) => (_) {});
