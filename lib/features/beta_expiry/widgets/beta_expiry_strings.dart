// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Binds WaveCrux's ARB keys to `crux_license`'s [CruxBetaExpiryStrings].
///
/// The banner itself lives in `crux_license`, lifted there after it was found
/// hand-copied into all four products. WaveCrux keeps only this binding and
/// the three ARB keys it already owned, so the wording and the plural form are
/// unchanged.
class WavecruxBetaExpiryStrings extends CruxBetaExpiryStrings {
  /// Wraps the already-resolved [L10N] for the current locale.
  const WavecruxBetaExpiryStrings(this._l10n);

  final L10N _l10n;

  @override
  String bannerMessage(int days) => _l10n.betaExpiryBannerMessage(days);

  @override
  String get bannerAction => _l10n.betaExpiryBannerAction;

  @override
  String get dismissLabel => _l10n.betaExpiryDismissLabel;
}
