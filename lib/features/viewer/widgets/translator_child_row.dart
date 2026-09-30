// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/features/viewer/widgets/value_color_swatch.dart';

/// One subfield child row in the value column, rendered below an expanded
/// translator-bound signal.
///
/// Shows the field name (indented, dimmed) and its formatted value, both in the
/// same monospace family as the parent value. Its [height] comes from the
/// shared lane geometry (`LaneMetrics.childRowHeight`) so the canvas and
/// signal-names list reserve identical space and the child rows never drift
/// from their wave. A `null` [field] renders an empty placeholder of the same
/// height (keeps geometry in sync if the translator produced fewer fields than
/// were reserved).
class TranslatorChildRow extends StatelessWidget {
  const TranslatorChildRow({
    required this.field,
    required this.height,
    this.hasX = false,
    this.hasZ = false,
    super.key,
  });

  /// The subfield to render, or null for a reserved-but-empty row.
  final TranslatedField? field;

  /// Render height (from `LaneMetrics.childRowHeight`).
  final double height;

  /// Whether the parent value carries unknown (`x`) bits.
  final bool hasX;

  /// Whether the parent value carries high-impedance (`z`) bits.
  final bool hasZ;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = field;
    if (f == null) {
      return SizedBox(height: height);
    }

    final Color valueColor;
    if (f.text == 'X' || hasX) {
      valueColor = WavecruxColors.xValue;
    } else if (hasZ) {
      valueColor = theme.extension<WavecruxColorExtension>()!.zValue;
    } else {
      valueColor = theme.colorScheme.onSurface.withValues(alpha: 0.85);
    }
    final nameColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8);

    return SizedBox(
      height: height,
      child: Padding(
        // Indent past the parent value so the child hierarchy reads as nested.
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: Row(
          children: [
            // Per-channel colour swatch when the field carries a colour hint
            // (the packed-pixel pack tints each R/G/B/A row toward its channel).
            if (f.colorArgb != null) ...[
              ValueColorSwatch(colorArgb: f.colorArgb!, size: 9),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                f.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: WavecruxColors.monoFontFamily,
                  fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                  fontSize: 10,
                  color: nameColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              f.text,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontFamily: WavecruxColors.monoFontFamily,
                fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                fontSize: 10,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
