// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A small rounded colour chip rendered beside a translated value (or one of
/// its subfields) whose translator emitted an ARGB colour hint
/// ([TranslationResult.colorArgb] / [TranslatedField.colorArgb]).
///
/// The packed-pixel Pro translator is the canonical producer: it surfaces the
/// decoded pixel colour beside the `#RRGGBB` value and tints each per-channel
/// child row. The chip is purely decorative — it owns no gestures, so it adds
/// no touch target; the surrounding value text / child row keeps its tap and
/// long-press handlers. A thin outline keeps a near-background colour (e.g. a
/// black pixel on a dark theme) visible.
class ValueColorSwatch extends StatelessWidget {
  const ValueColorSwatch({
    required this.colorArgb,
    this.size = 12,
    super.key,
  });

  /// ARGB colour (`0xAARRGGBB`) the chip is filled with.
  final int colorArgb;

  /// Edge length of the square chip in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('value_color_swatch'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(colorArgb),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
    );
  }
}
