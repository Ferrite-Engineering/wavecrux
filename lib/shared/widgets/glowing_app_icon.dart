// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/shared/widgets/wavecrux_icon_image.dart';

/// The WaveCrux app icon with the suite's animated halo/pulse treatment
/// ([CruxGlowingAppIcon]), colored by the WaveCrux waveform palette rather
/// than a single brand seed — cyan/green outer ring, magenta/gold middle
/// ring, cyan backlight.
///
/// The animation itself (layer structure, breathing periods, light/dark
/// intensity) lives in `crux_workspace` so every Crux app's welcome screen
/// and About dialog shares one implementation.
class GlowingAppIcon extends StatelessWidget {
  /// Creates a glowing WaveCrux app icon.
  const GlowingAppIcon({super.key, this.size = 120});

  /// Pixel size of the icon itself. The widget reserves additional space
  /// around the icon for the halo and background glow.
  final double size;

  // Colors sampled from the WaveCrux waveform palette.
  static const Color _cyan = Color(0xFF00E5FF);
  static const Color _green = Color(0xFF00E676);
  static const Color _gold = Color(0xFFFFD600);
  static const Color _magenta = Color(0xFFE040FB);
  static const Color _cyanWhite = Color(0xFFB0F4FF);

  /// The hand-tuned multicolor palette the original WaveCrux glow used —
  /// passed verbatim instead of a [CruxGlowPalette.fromSeed] derivation.
  static final CruxGlowPalette _palette = CruxGlowPalette(
    background: Color.lerp(_magenta, _cyan, 0.55)!,
    outer: Color.lerp(_cyan, _green, 0.4)!,
    middle: Color.lerp(_magenta, _gold, 0.5)!,
    inner: _cyan,
    innerCore: _cyanWhite,
  );

  @override
  Widget build(BuildContext context) {
    return CruxGlowingAppIcon(
      icon: WaveCruxIconImage(size: size),
      palette: _palette,
      size: size,
    );
  }
}
