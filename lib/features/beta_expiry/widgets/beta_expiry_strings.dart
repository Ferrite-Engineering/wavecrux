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

/// Binds WaveCrux's ARB keys to `crux_license`'s [CruxBetaExpiredStrings],
/// the strings of the shared blocking modal shown once a beta build expires.
///
/// The modal was lifted to `crux_license` from four product copies; these are
/// the four ARB keys WaveCrux's own copy already used, so nothing changes in
/// any locale.
class WavecruxBetaExpiredStrings extends CruxBetaExpiredStrings {
  /// Wraps the already-resolved [L10N] for the current locale.
  const WavecruxBetaExpiredStrings(this._l10n);

  final L10N _l10n;

  @override
  String get title => _l10n.betaExpiryExpiredTitle;

  @override
  String get body => _l10n.betaExpiryExpiredBody;

  @override
  String get downloadLabel => _l10n.betaExpiryExpiredAction;

  @override
  String get quitLabel => _l10n.betaExpiryExpiredQuit;
}
