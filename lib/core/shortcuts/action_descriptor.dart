// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_requirement.dart';

/// The four action-discovery surfaces an action can appear in.
///
/// See ARCHITECTURE.md §3 "Three-tier action discovery". The toolbar is the
/// one-click tier; the menu bar (desktop) / overflow menu (mobile) is the
/// browsable categorized tier; the command palette is the search tier.
enum ActionSurface {
  /// The viewer toolbar — a hand-curated set of one-click icon buttons.
  toolbar,

  /// The desktop native menu bar (`PlatformMenuBar`).
  menu,

  /// The mobile overflow action menu (phone bottom sheet / tablet popup).
  overflow,

  /// The command palette (Ctrl/Cmd+Shift+P).
  palette,
}

/// Declarative description of where a single [ShortcutAction] appears and when
/// it is visible / enabled. The table of these in `action_descriptors.dart` is
/// the **single source of truth** consumed by every action-discovery surface,
/// replacing the per-surface visibility sets and `_isEnabled` copies that used
/// to drift apart.
///
/// ## Presentation policy (how surfaces interpret a descriptor)
///
/// An action **appears** in surface `s` iff `surfaces.contains(s) &&
/// isVisible(ctx)`. Once it appears:
///
/// - **menu / overflow**: the item is rendered, and is *enabled* iff
///   `isEnabled(ctx)` (a disabled item is greyed out, not hidden).
/// - **palette**: the item is *listed* iff it also satisfies `isEnabled(ctx)` —
///   the palette has no greyed state, so a disabled action is simply omitted.
/// - **toolbar**: the button is rendered, and is enabled iff `isEnabled(ctx)`.
///
/// So [isVisible] models *structural* gating that hides an action everywhere
/// (e.g. device-class restrictions — diagnostics surfaces are hidden on phone),
/// while [isEnabled] models *transient* gating (e.g. file-required actions when
/// no file is loaded; collaboration actions when not in a session).
@immutable
class ActionDescriptor {
  const ActionDescriptor({
    this.surfaces = const {},
    this.requiredTier = LicenseTier.openCore,
    this.isVisible = _alwaysTrue,
    this.requires = const [],
  });

  /// The surfaces this action can appear in. An empty set means the action is
  /// reachable only via keyboard shortcut or a context menu (e.g. the
  /// `setFormat*` family, WASD navigation, tab-jump shortcuts).
  final Set<ActionSurface> surfaces;

  /// Minimum license tier required to *use* the action. The action stays
  /// discoverable in every build regardless of tier (activation is gated at
  /// the opener via `FeatureGate`); this field only drives the tier badge /
  /// label suffix. [LicenseTier.openCore] renders no badge.
  final LicenseTier requiredTier;

  /// Structural visibility predicate. When it returns false the action is
  /// omitted from *all* surfaces. Defaults to always-visible.
  final bool Function(ActionContext) isVisible;

  /// The atomic preconditions that must all hold for the action to be
  /// enabled. An empty list means always-enabled. See the class doc for how
  /// each surface presents a disabled action.
  ///
  /// Declared as a *list* of named [ActionRequirement]s rather than a single
  /// opaque predicate so a disabled action can explain itself: the keyboard
  /// dispatch guard resolves [unmetRequirement] and surfaces the matching
  /// localized hint. See [ActionRequirement] for the full rationale.
  final List<ActionRequirement> requires;

  /// Transient enablement: every requirement in [requires] is satisfied.
  bool isEnabled(ActionContext context) =>
      requires.every((r) => r.isSatisfiedBy(context));

  /// The first requirement in [requires] that [context] does not satisfy, or
  /// `null` when the action is enabled. Requirements are declared
  /// most-fundamental-first (e.g. `fileLoaded` before `cursorPresent`), so the
  /// first unmet one is the most useful thing to tell the user.
  ActionRequirement? unmetRequirement(ActionContext context) {
    for (final requirement in requires) {
      if (!requirement.isSatisfiedBy(context)) return requirement;
    }
    return null;
  }

  static bool _alwaysTrue(ActionContext _) => true;
}
