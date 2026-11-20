// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/license/wavecrux_license_badge_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// WaveCrux-flavored wrapper around the cross-suite
/// `package:crux_license/crux_license.dart` [EditionBadge].
///
/// Reads [L10N] from the current [BuildContext] and supplies a
/// [WaveCruxLicenseBadgeStrings] adapter so the package widget renders the
/// localized label and semantic phrase without each call site having to
/// construct the adapter itself.
///
/// States the edition in force — EDU, PRO or ENT — and renders nothing at
/// open core. It takes no tier: the package widget reads
/// `licenseTierProvider` itself, because a statement about what the user owns
/// has exactly one correct source. Rendering nothing at open core is what
/// makes it safe to mount unconditionally in shared chrome.
class WaveCruxEditionBadge extends ConsumerWidget {
  /// Creates an edition badge for the licence currently in force.
  const WaveCruxEditionBadge({super.key}) : _inStatusBar = false;

  /// The status-bar variant: PRO or ENT, and nothing at EDU or open core.
  ///
  /// Under an educational licence the status bar's `CruxEduStatusChip` makes
  /// the one EDU statement there (the EDU chip, "Non-commercial use" and the
  /// holder's address); a second EDU chip beside it would say the same thing
  /// twice. The About dialog and the licence panel keep their EDU badge.
  const WaveCruxEditionBadge.statusBar({super.key}) : _inStatusBar = true;

  final bool _inStatusBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_inStatusBar && ref.watch(licenseTierProvider) == LicenseTier.edu) {
      return const SizedBox.shrink();
    }
    return EditionBadge(
      strings: WaveCruxLicenseBadgeStrings(L10N.of(context)),
    );
  }
}
