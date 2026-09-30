// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/license/tier_badge_impression_provider.dart';
import 'package:wavecrux/core/license/wavecrux_license_badge_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// WaveCrux-flavored wrapper around the cross-suite
/// `package:crux_license/crux_license.dart` [FeatureTierBadge].
///
/// Reads [L10N] from the current [BuildContext] and supplies a
/// [WaveCruxLicenseBadgeStrings] adapter so the package widget renders
/// localized PRO / ENT labels and semantic phrases without each call site
/// having to construct the adapter itself. All visual behavior is the
/// package widget's — `SizedBox.shrink` for `openCore` / `edu`, PRO chip
/// in `colorScheme.primary`, ENT chip in `colorScheme.tertiary`.
///
/// ### The badge is also the funnel's impression point
///
/// Every surface that renders a gated action badged rather than hidden goes
/// through this widget, which makes it the one honest place to answer "did
/// anyone actually see that Pro exists". The record happens in [initState] —
/// once per mount, never in `build` — and
/// [TierBadgeImpressionNotifier.recordImpression] then collapses it to once
/// per tier per session. See that provider for why the session, and not the
/// widget, is the unit.
///
/// The badge itself is unchanged by this: it is still an
/// intrinsically-sized chip with no fixed width, so it wraps and shrinks with
/// whatever row it is in. That matters under a VSCode editor panel, which a
/// user can drag to a few hundred logical pixels — the rule is that
/// a gated feature stays **visible and badged** at every width, never hidden
/// to save space.
class WaveCruxFeatureTierBadge extends ConsumerStatefulWidget {
  /// Creates a tier badge labeling a feature that requires [requiredTier].
  const WaveCruxFeatureTierBadge({
    required this.requiredTier,
    super.key,
  });

  /// The minimum tier required to use the feature this badge labels.
  final LicenseTier requiredTier;

  @override
  ConsumerState<WaveCruxFeatureTierBadge> createState() =>
      _WaveCruxTierBadgeState();
}

class _WaveCruxTierBadgeState extends ConsumerState<WaveCruxFeatureTierBadge> {
  @override
  void initState() {
    super.initState();
    // Deferred past the current frame: `initState` runs during a build, and
    // `recordImpression` mutates a provider. Recording synchronously would
    // modify a provider while the tree that reads it is building, which
    // Riverpod asserts against in debug and which would make this widget
    // unmountable inside any surface that watches the same notifier.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(tierBadgeImpressionProvider.notifier)
          .recordImpression(widget.requiredTier);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FeatureTierBadge(
      requiredTier: widget.requiredTier,
      strings: WaveCruxLicenseBadgeStrings(L10N.of(context)),
    );
  }
}
