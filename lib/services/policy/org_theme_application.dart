// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Applying the organization's theme pack — the half `org_theme_and_templates`
/// deliberately left out.
///
/// Reading the document was the easy part and is not the feature. This is:
/// decode it, hand it to the theme notifier, and — when the organization locked
/// it — stop the user picking something else.
///
/// ### Where it runs, and why not later
///
/// At bootstrap, before the first frame. A theme applied after the window is up
/// is a flash of the wrong colours followed by a correction, on every launch,
/// forever. That reads as a bug regardless of how correct the end state is.
///
/// ### Locked means the picker is read-only, not absent
///
/// The same rule the licence panel follows: an engineer has to be able to see
/// what the organization chose, and a missing Appearance section turns "why is
/// my theme different" into a support ticket with nothing to look at.
library;

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/services/policy/org_share_resource.dart';
import 'package:wavecrux/services/policy/org_theme_and_templates.dart';

/// A theme the organization set and the user did not get. `developer.log`
/// emits nothing from a release build, so this goes to the product log.
final _log = Logger('wavecrux.policy');

/// What happened when the organization's theme pack was applied.
@immutable
final class OrgThemeOutcome {
  /// Creates an [OrgThemeOutcome].
  const OrgThemeOutcome({
    required this.applied,
    required this.locked,
    this.problem,
  });

  /// The organization configured nothing.
  static const OrgThemeOutcome none = OrgThemeOutcome(
    applied: false,
    locked: false,
  );

  /// Whether a pack was decoded and activated.
  final bool applied;

  /// Whether the organization locked it — the mandatory-theme case.
  ///
  /// **True even when [applied] is false.** A locked pack that could not be
  /// read still means the organization intends to fix the theme, and the
  /// picker stays read-only: unlocking it because a share was unreachable
  /// would hand an engineer a choice the organization did not give them, at
  /// exactly the moment nobody is watching.
  final bool locked;

  /// Why it did not apply, when it did not. A path, never a value.
  final String? problem;
}

/// Decodes and activates the organization's theme pack.
///
/// Returns [OrgThemeOutcome.none] with no policy file — every default install —
/// so the user's own theme is what loads, untouched.
///
/// Every failure is reported rather than swallowed: an organization that
/// published a pack and finds half the team on the default theme needs the
/// application to have said why.
/// [container] is the root [ProviderContainer], not a `Ref`: this runs during
/// bootstrap, before any provider is building, and a `Ref` does not exist yet.
OrgThemeOutcome applyOrgThemePack(
  ProviderContainer container, {
  ThemePackCodec codec = const ThemePackCodec(),
}) {
  final reference = container.read(orgThemePackProvider);
  if (reference == null) return OrgThemeOutcome.none;

  final load = loadOrgShareResource(reference.resource);
  if (!load.isOk) {
    return OrgThemeOutcome(
      applied: false,
      locked: reference.locked,
      problem: load.detail,
    );
  }

  final ThemePack pack;
  try {
    pack = codec.fromJson(load.contents!);
  } on Object catch (error) {
    return OrgThemeOutcome(
      applied: false,
      locked: reference.locked,
      problem: '${reference.resource.path} is not a usable theme pack: $error',
    );
  }

  container.read(cruxColorThemeProvider.notifier).activate(pack.toTheme());
  return OrgThemeOutcome(applied: true, locked: reference.locked);
}

/// Whether the Appearance picker should be read-only.
///
/// Read by Settings ▸ Appearance. Locked, not hidden.
final orgThemeLockedProvider = Provider<bool>((ref) {
  return ref.watch(orgThemePackProvider)?.locked ?? false;
}, name: 'orgThemeLockedProvider');

/// Applies the organization's theme pack when its reference **appears** after
/// startup.
///
/// [applyOrgThemePack] runs during bootstrap, before the first frame, which
/// is the right moment for a theme — and the wrong moment for a licence. The
/// stored credential resolves asynchronously and is deliberately not awaited
/// at startup, so on a post-beta launch `orgThemePackProvider` is still
/// `null` for want of a tier when bootstrap reads it, and an Enterprise seat
/// would open on the default theme with the organization's pack never
/// applied. This listener closes that gap: when the reference goes from
/// absent to present — the tier resolved, a licence was activated, a policy
/// licence landed — it applies the pack then. `ref.listen` does not fire for
/// the initial value, so a pack bootstrap already applied is not applied
/// twice, and a pack that stays `null` is left alone.
///
/// Realized eagerly by the Pro overlay, whose host holds a real root
/// subscription for the session; in open core the tier is a constant and
/// there is nothing to wait for. Failures are logged the way bootstrap logs
/// them: an unreachable share is usually a laptop off the VPN.
final Provider<void> orgThemePackLateApplyProvider = Provider<void>((ref) {
  ref.listen<OrgResourceRef?>(orgThemePackProvider, (previous, next) {
    if (previous != null || next == null) return;
    final outcome = applyOrgThemePack(ref.container);
    if (outcome.problem case final problem?) {
      _log.warning('organization theme pack not applied: $problem');
    }
  });
}, name: 'orgThemePackLateApplyProvider');
