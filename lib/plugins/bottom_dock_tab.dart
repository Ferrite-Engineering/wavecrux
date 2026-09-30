// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';

/// Resolves the localized label for a [BottomDockTab]. Receives the
/// host's [BuildContext] so the resolver can look up whichever
/// localizations bundle owns the string — `L10N.of(context)` for
/// open-core tabs, `L10NPro.of(context)` for Pro tabs (whose delegate
/// is registered through `extraLocalizationsDelegatesProvider`).
///
/// Signature history: this originally took the open-core `L10N`
/// instance, which made it *impossible* for an overlay package to
/// resolve its own strings — the Pro tabs shipped hardcoded English
/// labels as a workaround. A `BuildContext` (matching
/// [BottomDockTabBuilder]) is the correct seam currency for any
/// resolver an overlay must implement.
typedef BottomDockTabLabelResolver = String Function(BuildContext context);

/// Builds the panel widget displayed in the bottom dock when this tab is
/// the active one. Called from the open-core viewer's
/// `_buildBottomPanelContent` priority chain.
typedef BottomDockTabBuilder = Widget Function(BuildContext context);

/// Open-core descriptor for a bottom-dock tab contributed through
/// [extraBottomDockTabsProvider].
///
/// The bottom pane is shared between the open-core transaction table,
/// the cocotb log panel, the FSM bubble diagram, the X-trace view, the
/// switching-activity report, and the Stage panel. Each of those
/// surfaces is selected by a per-feature visibility flag in
/// `PanelLayoutState`. Pro contributors that need their own panel —
/// e.g. the SVA assertion summary panel — would otherwise have to fork
/// the open-core viewer to add a new flag and a new branch in the
/// priority chain. [BottomDockTab] avoids that fork: each tab carries
/// its own [visibilityProvider] (a `ProviderListenable<bool>` watched
/// inside the host), its own [builder], and an optional
/// [requiredTier] so the host can route activation through
/// `FeatureGate.isAvailable`.
///
/// The host inserts contributed tabs into the priority chain just
/// after the cocotb log panel — the cocotb panel keeps priority over
/// extras, but extras win over the default transaction table view.
/// Within the contributed list, iteration order matches the order in
/// which the Pro overlay supplied them.
@immutable
class BottomDockTab {
  const BottomDockTab({
    required this.id,
    required this.labelResolver,
    required this.icon,
    required this.builder,
    required this.visibilityProvider,
    this.requiredTier = LicenseTier.openCore,
  });

  /// Stable identifier (e.g. `"sva"`). Must be unique across all
  /// registered tabs.
  final String id;

  /// Resolves the localized human-readable label. Used by the bottom-
  /// dock chrome (and any future tab-strip widget) so the label survives
  /// the locale sweep.
  final BottomDockTabLabelResolver labelResolver;

  /// Icon shown alongside the label in any future tab-strip presentation.
  final IconData icon;

  /// License tier required to instantiate the tab. Open-core defaults
  /// to [LicenseTier.openCore]; Pro contributors pass
  /// [LicenseTier.pro]. The host gates rendering through
  /// `FeatureGate.isAvailable(requiredTier, ref)`. During the public
  /// beta this is a no-op (`kBetaPeriod` short-circuits to allow);
  /// post-beta it routes unlicensed users through the upgrade dialog.
  final LicenseTier requiredTier;

  /// Riverpod provider whose value is `true` when this tab should be
  /// the active bottom-dock content. The host watches this in its
  /// build method, so flipping it from a side notifier (e.g. when
  /// SVA results finish loading) automatically reveals the tab.
  ///
  /// `ProviderListenable<bool>` is the abstract interface accepted by
  /// `WidgetRef.watch`, so any of `Provider<bool>`,
  /// `NotifierProvider<X, bool>`, or a `select()` projection can
  /// satisfy it.
  final ProviderListenable<bool> visibilityProvider;

  /// Builds the panel widget. Called only when [visibilityProvider]
  /// is `true` and [requiredTier] is satisfied.
  final BottomDockTabBuilder builder;

  @override
  bool operator ==(Object other) => other is BottomDockTab && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
