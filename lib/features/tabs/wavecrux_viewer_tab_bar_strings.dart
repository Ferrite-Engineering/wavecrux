// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:wavecrux/l10n/generated/l10n.dart';

/// WaveCrux-specific [`crux.ViewerTabBarStrings`] implementation that
/// delegates every getter to the appropriate [L10N] string.
///
/// This adapter exists so the [`crux_workspace`] package's `ViewerTabBar`
/// renders WaveCrux's localized strings instead of the English defaults in
/// [`crux.ViewerTabBarStringsEn`]. It is constructed wherever a
/// [`ViewerTabBar`] (or, transitively, a [`PaneHost`]) is instantiated and
/// passed via the widget's `strings:` constructor parameter.
///
/// Construction is cheap (holds a single reference to [L10N]); a fresh
/// instance per build is acceptable and matches the package's
/// `const ViewerTabBarStringsEn()` default.
class WaveCruxViewerTabBarStrings extends crux.ViewerTabBarStrings {
  /// Creates a [WaveCruxViewerTabBarStrings] backed by [l10n].
  const WaveCruxViewerTabBarStrings(this.l10n);

  /// Localization source. Resolved per-build by callers, typically via
  /// `L10N.of(context)`.
  final L10N l10n;

  @override
  String get closeTabTooltip => l10n.viewerTabBarCloseTabTooltip;

  @override
  String closeTabTooltipFor(String name) => l10n.tabChipCloseTooltip(name);

  @override
  String get newTabTooltip => l10n.tabBarNewTabTooltip;

  @override
  String get newTabDefaultDisplayName =>
      l10n.viewerTabBarNewTabDefaultDisplayName;

  @override
  String get unnamedTabFallback => l10n.viewerTabBarUnnamedTabFallback;

  @override
  String get closeTabMenuItem => l10n.tabContextMenuCloseTab;

  @override
  String get closeOtherTabsMenuItem => l10n.tabContextMenuCloseOtherTabs;

  @override
  String get closeTabsToTheRightMenuItem => l10n.tabContextMenuCloseTabsToRight;

  @override
  String get moveToNewWindowMenuItem => l10n.tabContextMenuMoveToNewWindow;

  @override
  String get multiWindowUnavailableTooltip =>
      l10n.viewerTabBarMultiWindowUnavailableTooltip;

  @override
  String get activePaneAccessibilityLabel =>
      l10n.viewerTabBarActivePaneAccessibilityLabel;

  @override
  String get dragToPaneAccessibilityHint =>
      l10n.viewerTabBarDragToPaneAccessibilityHint;

  @override
  String get reorderHandleTooltip => l10n.viewerTabBarReorderHandleTooltip;

  // These two carry English defaults on the base class (they were added after
  // the interface shipped, so they could not be abstract without breaking four
  // subclasses at once). Overriding them is what stops the chevrons speaking
  // English in a Japanese build.
  @override
  String get scrollTabsLeftTooltip => l10n.viewerTabBarScrollTabsLeftTooltip;

  @override
  String get scrollTabsRightTooltip => l10n.viewerTabBarScrollTabsRightTooltip;
}
