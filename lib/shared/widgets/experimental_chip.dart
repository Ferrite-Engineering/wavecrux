// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// A small "Experimental" chip rendered on AI Waveform Assistant surfaces.
///
/// Distinct from a tier badge (`WaveCruxFeatureTierBadge`): an AI surface renders this
/// chip **alongside**, not instead of, any tier badge — the tier badge
/// communicates the pricing tier, this chip communicates that the feature is
/// unstable and may change or be removed before the open-core flip. See
/// `crux_license`'s `kAiExperimental` / `aiExperimentalEnabledProvider`.
///
/// Self-localizing (reads [L10N] from [context]) so callers can drop it into a
/// row without threading a string through, exactly like `WaveCruxFeatureTierBadge`.
class ExperimentalChip extends StatelessWidget {
  /// Creates an Experimental chip.
  const ExperimentalChip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onTertiaryContainer,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: scheme.onTertiaryContainer.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.science_outlined,
              size: 13,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Text(l10n.experimentalChipLabel, style: labelStyle),
          ],
        ),
      ),
    );
  }
}
