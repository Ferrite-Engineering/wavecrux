// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_appearance_strings.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Preset colors arranged in hue-grouped rows for the color picker grid.
const List<Color> _kPresetColors = [
  // Reds
  Color(0xFFFF2222), Color(0xFFFF5555), Color(0xFFCC0000), Color(0xFF880000),
  Color(0xFFFF8888), Color(0xFFFFBBBB),
  // Oranges
  Color(0xFFFF8800), Color(0xFFFFAA33), Color(0xFFCC6600), Color(0xFF994400),
  Color(0xFFFFCC88), Color(0xFFFFEECC),
  // Yellows
  Color(0xFFFFFF00), Color(0xFFFFFF55), Color(0xFFCCCC00), Color(0xFF888800),
  Color(0xFFFFFFAA), Color(0xFFFFFFDD),
  // Greens
  Color(0xFF00FF00), Color(0xFF44FF44), Color(0xFF00CC00), Color(0xFF008800),
  Color(0xFF88FF88), Color(0xFFAAFFAA),
  // Teals / Cyans
  Color(0xFF00FFFF), Color(0xFF44FFFF), Color(0xFF00CCCC), Color(0xFF008888),
  Color(0xFF88FFFF), Color(0xFFAAFFFF),
  // Blues
  Color(0xFF4488FF), Color(0xFF6699FF), Color(0xFF2255CC), Color(0xFF003399),
  Color(0xFF99BBFF), Color(0xFFCCDDFF),
  // Purples / Magentas
  Color(0xFF8844FF), Color(0xFFAA66FF), Color(0xFF6600CC), Color(0xFF440088),
  Color(0xFFCC99FF), Color(0xFFEECCFF),
  // Pinks / Roses
  Color(0xFFFF44AA), Color(0xFFFF88CC), Color(0xFFCC0077), Color(0xFF880044),
  Color(0xFFFFAADD), Color(0xFFFFCCEE),
  // Neutrals
  Color(0xFFFFFFFF), Color(0xFFCCCCCC), Color(0xFFAAAAAA), Color(0xFF777777),
  Color(0xFF444444), Color(0xFF222222),
];

/// Color picker dialog for customizing a signal's waveform color.
///
/// Thin entry point over the shared `crux_theme` picker
/// (`showColorPickerDialog`): the WaveCrux palette renders as a quick-pick
/// swatch row and the hue-grouped preset grid renders below it, above the
/// shared dialog's HSV sliders, hex (+alpha) input, RGB readout, and
/// before/after preview. Returns the selected [Color] on confirm, or null on
/// cancel.
abstract final class SignalColorPickerDialog {
  /// Shows the dialog and returns the chosen color, or null if dismissed.
  static Future<Color?> show(BuildContext context, Color currentColor) {
    final l10n = L10N.of(context);
    return showColorPickerDialog(
      context: context,
      initialColor: currentColor,
      strings: _SignalColorPickerStrings(l10n),
      paletteSections: [
        ColorPickerPaletteSection(
          label: l10n.colorPickerPaletteSection,
          colors: signalColorPalette,
          swatchSize: 32,
        ),
        ColorPickerPaletteSection(
          label: l10n.colorPickerPresetsSection,
          colors: _kPresetColors,
        ),
      ],
    );
  }
}

/// Signal-picker strings: the shared appearance-strings adapter with the
/// dialog title and action labels re-pointed at the signal picker's
/// pre-existing `colorPicker*` ARB keys ("Signal Color" / "Apply" / "Cancel")
/// so the dialog keeps its established title and button copy.
class _SignalColorPickerStrings extends WaveCruxThemeAppearanceStrings {
  const _SignalColorPickerStrings(this._signalL10n) : super(_signalL10n);

  final L10N _signalL10n;

  @override
  String get colorPickerDialogTitle => _signalL10n.colorPickerTitle;

  @override
  String get colorPickerOkLabel => _signalL10n.colorPickerApply;

  @override
  String get colorPickerCancelLabel => _signalL10n.colorPickerCancel;
}
