// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Semantic color tokens for WaveCrux.
///
/// Groups: signal colors (oscilloscope convention), waveform state values,
/// cursor/marker overlays, and panel chrome for dark and light themes.
abstract final class WavecruxColors {
  // ---------------------------------------------------------------------------
  // Signal colors — oscilloscope/logic-analyzer convention
  // ---------------------------------------------------------------------------

  /// Primary signal color: green.
  static const Color signalGreen = Color(0xFF4CAF50);

  /// Signal color: cyan.
  static const Color signalCyan = Color(0xFF26C6DA);

  /// Signal color: yellow.
  static const Color signalYellow = Color(0xFFFFEE58);

  /// Signal color: magenta.
  static const Color signalMagenta = Color(0xFFEC407A);

  /// Signal color: orange.
  static const Color signalOrange = Color(0xFFFFA726);

  /// Signal color: white/light-gray (for dark backgrounds).
  static const Color signalWhite = Color(0xFFEEEEEE);

  /// Default ordered palette for auto-assigning colors to new signals.
  static const List<Color> signalPalette = [
    signalGreen,
    signalCyan,
    signalYellow,
    signalMagenta,
    signalOrange,
    signalWhite,
  ];

  // ---------------------------------------------------------------------------
  // Waveform state values
  // ---------------------------------------------------------------------------

  /// Unknown (X) state — rendered as red fill or hatching.
  static const Color xValue = Color(0xFFEF5350);

  /// X-state hatch lines — darker red, drawn over [xValue] fill.
  static const Color xValueHatch = Color(0xFFC62828);

  /// High-impedance (Z) state — dark-mode variant (Purple 300).
  /// Vivid enough to read against near-black backgrounds.
  static const Color zValueDark = Color(0xFFBA68C8);

  /// High-impedance (Z) state — light-mode variant (Purple 800).
  /// Deep enough to contrast against white/light-grey backgrounds.
  static const Color zValueLight = Color(0xFF7B1FA2);

  /// High-impedance (Z) state fallback — deprecated; prefer [zValueDark] or [zValueLight].
  static const Color zValue = zValueDark;

  // ---------------------------------------------------------------------------
  // Cursors and markers
  // ---------------------------------------------------------------------------

  /// Primary cursor — yellow, high contrast on dark backgrounds.
  static const Color primaryCursor = Color(0xFFFFEE58);

  /// Secondary cursor — light blue, distinct from the primary cursor.
  static const Color secondaryCursor = Color(0xFF29B6F6);

  /// Named marker color — soft pink.
  static const Color marker = Color(0xFFF48FB1);

  /// Selection highlight overlay — 20% translucent blue.
  static const Color selectionHighlight = Color(0x334FC3F7);

  // ---------------------------------------------------------------------------
  // Panel chrome — dark theme
  // ---------------------------------------------------------------------------

  /// Scaffold/canvas background — near-black.
  static const Color darkBackground = Color(0xFF0D0D0F);

  /// Panel surface color — slightly lighter than the background.
  static const Color darkSurface = Color(0xFF141418);

  /// Elevated surface variant — used for raised panels, list headers.
  static const Color darkSurfaceVariant = Color(0xFF1C1C22);

  /// Standard panel border.
  static const Color darkBorder = Color(0xFF2C2C38);

  /// Subtle panel border — separator lines, inset outlines.
  static const Color darkBorderSubtle = Color(0xFF1E1E28);

  // ---------------------------------------------------------------------------
  // Panel chrome — light theme
  // ---------------------------------------------------------------------------

  /// Scaffold/canvas background — light gray.
  static const Color lightBackground = Color(0xFFF4F4F7);

  /// Panel surface color.
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Elevated surface variant.
  static const Color lightSurfaceVariant = Color(0xFFEEEEF4);

  /// Standard panel border.
  static const Color lightBorder = Color(0xFFCCCCD8);

  /// Subtle panel border.
  static const Color lightBorderSubtle = Color(0xFFE4E4EE);

  // ---------------------------------------------------------------------------
  // Time ruler
  // ---------------------------------------------------------------------------

  /// Minor tick mark color.
  static const Color timeRulerTick = Color(0xFF565668);

  /// Major tick mark color — brighter than minor ticks.
  static const Color timeRulerMajorTick = Color(0xFF8888A0);

  // ---------------------------------------------------------------------------
  // Typography — monospace for signal data, system sans-serif for UI labels
  // ---------------------------------------------------------------------------

  /// Primary monospace font for signal values, names, and time displays.
  static const String monoFontFamily = 'JetBrainsMono';

  /// Fallback fonts used when [monoFontFamily] is not available.
  static const List<String> monoFontFamilyFallback = [
    'FiraCode',
    'Courier New',
    'monospace',
  ];
}
