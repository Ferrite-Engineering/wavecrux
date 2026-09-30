// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tier_badge_impression_provider.g.dart';

/// Records `badge.impression` at most once per tier per session.
///
/// ### Why the de-duplication is the whole design
///
/// A tier badge is rendered by a `build()` method. Recording from there
/// directly would produce an event on every rebuild — a scroll, a hover, a
/// theme change — and the resulting counter would measure Flutter's repaint
/// behaviour rather than anyone seeing anything. Recording once per *mount*
/// is better but still wrong in the direction that matters: the decoder
/// picker lists every Pro decoder at once, so opening it would emit dozens of
/// impressions for one person learning, once, that Pro decoders exist.
///
/// So the unit is **(tier, session)**. That is also what makes the number
/// usable: `badge.click` shares the `tier` dimension, and
/// `clicks / impressions` is then "of the sessions that saw a Pro badge, how
/// many acted on one" — the ratio the funnel exists to produce. Coalescing
/// would fold repeats into a `count` anyway; this keeps the *distinct-session*
/// reading honest rather than merely keeping the payload small.
///
/// `keepAlive` and root-scoped: a per-tab notifier would re-arm per tab,
/// which is to say per file, and turn a session count into a file count.
@Riverpod(keepAlive: true)
class TierBadgeImpressionNotifier extends _$TierBadgeImpressionNotifier {
  @override
  Set<LicenseTier> build() => const <LicenseTier>{};

  /// Record that a badge naming [tier] became visible.
  ///
  /// Returns whether an event was recorded — false for a repeat, and false
  /// for a tier that renders no badge at all.
  ///
  /// [LicenseTier.openCore] and [LicenseTier.edu] are refused rather than
  /// silently recorded: `FeatureTierBadge` returns `SizedBox.shrink()` for both, so
  /// an "impression" of one is an impression of nothing. The catalog's closed
  /// `tier` vocabulary (`pro`, `enterprise`) says the same thing, and a value
  /// outside it would be dropped at the ingestion Worker while the event was
  /// kept — leaving the dimension quietly wrong instead of loudly absent.
  bool recordImpression(LicenseTier tier) {
    if (tier != LicenseTier.pro && tier != LicenseTier.enterprise) return false;
    if (state.contains(tier)) return false;
    state = <LicenseTier>{...state, tier};
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'badge.impression',
            properties: <String, Object?>{'tier': tier.name},
          ),
        );
    return true;
  }
}
