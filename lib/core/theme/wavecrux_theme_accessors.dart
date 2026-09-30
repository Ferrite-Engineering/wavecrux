// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Color;
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';

/// Convenience getters that expose WaveCrux's named tokens off
/// [CruxColorTheme] under the legacy field-style names the renderer
/// and Settings widgets already reach for.
///
/// Storage lives in `crux_theme`'s flat `category → token → Color` map;
/// the painters' call sites (`theme.canvasBackground`,
/// `theme.canvasCursorPrimary`, …) keep their shape thanks to this
/// extension. Every getter has a painter that reads it — the waveform
/// render object, `CursorOverlay` or `TimeRulerWidget` — so an edit in
/// Settings ▸ Appearance repaints something. Every getter resolves through
/// [ThemeRegistry] so a token
/// the active theme omits falls back to the WaveCrux-registered
/// brightness-appropriate default. The registry must already carry
/// the WaveCrux catalog — see [registerWaveCruxThemeTokens] (called
/// from `bootstrap()`); use [registerWaveCruxThemeTokens] in tests
/// that build a [CruxColorTheme] directly.
extension WaveCruxThemeAccessors on CruxColorTheme {
  Color _canvas(String tokenId) =>
      ThemeRegistry.instance.resolve(this, canvasTokens.id, tokenId) ??
      colorOr(canvasTokens.id, tokenId, const Color(0x00000000));

  // ── Canvas — background & lane rows ──────────────────────────────────────
  Color get canvasBackground => _canvas('background');
  Color get canvasLaneBackgroundOdd => _canvas('lane.backgroundOdd');
  Color get canvasLaneBackgroundEven => _canvas('lane.backgroundEven');
  Color get canvasLaneDivider => _canvas('lane.divider');
  Color get canvasGroupHeader => _canvas('group.header');

  // ── Canvas — signals ─────────────────────────────────────────────────────
  Color get canvasSignalXFill => _canvas('signal.x.fill');
  Color get canvasSignalXHatch => _canvas('signal.x.hatch');
  Color get canvasSignalZLine => _canvas('signal.z.line');

  // ── Canvas — cursors & markers (CursorOverlay, TimeRulerWidget) ─────────

  /// Primary cursor line, the canvas delta label, and the primary cursor's
  /// filled triangle on the time ruler.
  Color get canvasCursorPrimary => _canvas('cursor.primary');

  /// Secondary cursor's dashed line and outlined ruler triangle, and the
  /// tint behind both delta readouts.
  Color get canvasCursorSecondary => _canvas('cursor.secondary');

  /// Band filled between the two cursors on the canvas. Transparent (off) in
  /// every built-in preset.
  Color get canvasCursorDelta => _canvas('cursor.delta');

  /// Line through the canvas at each named marker. Transparent (off) in every
  /// built-in preset.
  Color get canvasMarkerLine => _canvas('marker.line');

  /// Named marker's triangle on the time ruler.
  Color get canvasMarkerFlag => _canvas('marker.flag');

  /// Named marker's letter on the time ruler.
  Color get canvasMarkerFlagText => _canvas('marker.flagText');

  // ── Canvas — time ruler ──────────────────────────────────────────────────
  Color get canvasRulerBackground => _canvas('ruler.background');
  Color get canvasRulerTick => _canvas('ruler.tick');

  /// Group-header, comment-lane and empty-canvas text. The time ruler's own
  /// major ticks do not read it; see `TimeRulerWidget`.
  Color get canvasRulerTickMajor => _canvas('ruler.tickMajor');
  Color get canvasRulerLabel => _canvas('ruler.label');

  /// The delta-time readout on the time ruler.
  Color get canvasRulerCursorTime => _canvas('ruler.cursorTime');

  // ── Canvas — drag-zoom selection ────────────────────────────────────────
  Color get canvasSelection => _canvas('selection');
}
