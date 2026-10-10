// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Color;
import 'package:wavecrux/core/theme/wavecrux_canvas_preset_overlay.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';

// Re-export the suite-shared chrome catalog so the historical
// `import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';`
// usage at WaveCrux's chrome accessors + tests continues to resolve
// `chromeTokens` without each call site learning the crux_theme path.
export 'package:crux_theme/crux_theme.dart' show chromeTokens;

/// Registers WaveCrux's `canvas` and `chrome` token catalogs with the
/// shared [ThemeRegistry].
///
/// Called once from [bootstrap]. Idempotent: if either category is
/// already registered (e.g. by a test that ran a prior bootstrap in the
/// same isolate), the call is silently skipped so a second bootstrap
/// does not throw.
///
/// Token defaults match the Crux Dark / Crux Light values in
/// [waveCruxCanvasPresetOverlay]. Light defaults are used as the
/// brightness-light fallback; dark defaults as the brightness-dark
/// fallback. The registrations below are the full token catalog.
void registerWaveCruxThemeTokens() {
  final registry = ThemeRegistry.instance;
  if (!registry.hasCategory(canvasTokens.id)) {
    registry.registerCategory(canvasTokens);
  }
  // The waveform-canvas values used to be baked into `crux_theme`'s
  // shared built-in presets, which forced NetCrux / LintCrux / SimCrux to
  // ship (and expose in Settings → Appearance) a waveform palette they can
  // never paint with. They now arrive through the `PresetTokenOverlay` seam,
  // registered here by the one product that owns them. Re-registering the
  // same const overlay is a no-op, so this is safe to call repeatedly.
  registry.registerPresetOverlay(waveCruxCanvasPresetOverlay);
  // Chrome catalog is shared across all four suite products and lives
  // in crux_theme so the suite presents one canonical chrome-token
  // vocabulary to end users and `.crux-theme.json` pack authors.
  registerCruxThemeChromeTokens();
}

/// WaveCrux canvas token catalog — every themable color the waveform
/// canvas, its cursor layer and the time ruler paint.
///
/// Defaults track the Crux Dark / Crux Light presets so a theme pack that
/// omits a token resolves to a sensible WaveCrux value rather than an
/// arbitrary Material 3 derivation.
///
/// Every token here has a painter that reads it through
/// `WaveCruxThemeAccessors`. A trace's high and low levels and a bus's value
/// label take the signal's own color, which the user sets per signal, so
/// the catalog has no token for them.
///
/// `cursor.delta` and `marker.line` draw optional overlays — a band between
/// the two cursors and a line through the canvas at each named marker — and
/// default to fully transparent, which draws nothing. A theme turns them on
/// by giving them a color.
const ThemeTokenCategory canvasTokens = ThemeTokenCategory(
  id: 'canvas',
  displayName: 'Canvas',
  tokens: [
    ThemeTokenDescriptor(
      id: 'background',
      displayName: 'Background',
      lightDefault: Color(0xFFF5F5F5),
      darkDefault: Color(0xFF1A1A1A),
    ),
    ThemeTokenDescriptor(
      id: 'lane.backgroundOdd',
      displayName: 'Lane background (odd)',
      lightDefault: Color(0xFFF5F5F5),
      darkDefault: Color(0xFF1A1A1A),
    ),
    ThemeTokenDescriptor(
      id: 'lane.backgroundEven',
      displayName: 'Lane background (even)',
      lightDefault: Color(0xFFEFEFEF),
      darkDefault: Color(0xFF1F1F1F),
    ),
    ThemeTokenDescriptor(
      id: 'lane.divider',
      displayName: 'Lane divider',
      lightDefault: Color(0xFFCCCCCC),
      darkDefault: Color(0xFF2D2D2D),
    ),
    ThemeTokenDescriptor(
      id: 'group.header',
      displayName: 'Group header background',
      lightDefault: Color(0xFFE8E8E8),
      darkDefault: Color(0xFF252525),
    ),
    ThemeTokenDescriptor(
      id: 'signal.x.fill',
      displayName: 'X-state fill',
      lightDefault: Color(0xFFCC1111),
      darkDefault: Color(0xFFFF2222),
    ),
    ThemeTokenDescriptor(
      id: 'signal.x.hatch',
      displayName: 'X-state hatch',
      lightDefault: Color(0xFF991111),
      darkDefault: Color(0xFFFF4444),
    ),
    ThemeTokenDescriptor(
      id: 'signal.z.line',
      displayName: 'Z-state line',
      lightDefault: Color(0xFF888888),
      darkDefault: Color(0xFF888888),
    ),
    // The cursor, marker and ruler defaults below are the colors the cursor
    // layer and the time ruler painted before these tokens were wired to
    // them, so a theme that omits one looks the way it always has.
    ThemeTokenDescriptor(
      id: 'cursor.primary',
      displayName: 'Primary cursor',
      lightDefault: Color(0xFFE65100),
      darkDefault: WavecruxColors.primaryCursor,
    ),
    ThemeTokenDescriptor(
      id: 'cursor.secondary',
      displayName: 'Secondary cursor',
      lightDefault: Color(0xFF0277BD),
      darkDefault: WavecruxColors.secondaryCursor,
    ),
    ThemeTokenDescriptor(
      id: 'cursor.delta',
      displayName: 'Cursor delta region',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: 'marker.line',
      displayName: 'Marker line',
      lightDefault: Color(0x00000000),
      darkDefault: Color(0x00000000),
    ),
    ThemeTokenDescriptor(
      id: 'marker.flag',
      displayName: 'Marker flag',
      lightDefault: Color(0xFFC2185B),
      darkDefault: WavecruxColors.marker,
    ),
    ThemeTokenDescriptor(
      id: 'marker.flagText',
      displayName: 'Marker flag text',
      lightDefault: Color(0xFFC2185B),
      darkDefault: WavecruxColors.marker,
    ),
    ThemeTokenDescriptor(
      id: 'ruler.background',
      displayName: 'Ruler background',
      lightDefault: WavecruxColors.lightSurface,
      darkDefault: WavecruxColors.darkSurface,
    ),
    ThemeTokenDescriptor(
      id: 'ruler.tick',
      displayName: 'Minor tick',
      lightDefault: Color(0xFF8888A0),
      darkDefault: WavecruxColors.timeRulerTick,
    ),
    // Despite the id, this colors group-header, comment and empty-canvas
    // text, not the ruler's major ticks (those paint from
    // `WavecruxColorExtension.timeRulerMajorTick`). The id stays so existing
    // theme packs keep resolving.
    // Despite the id, this colors group-header, comment and empty-canvas
    // text, not the ruler's major ticks (those paint from
    // `WavecruxColorExtension.timeRulerMajorTick`). The id stays so existing
    // theme packs keep resolving.
    ThemeTokenDescriptor(
      id: 'ruler.tickMajor',
      displayName: 'Group header and comment text',
      lightDefault: Color(0xFF555555),
      darkDefault: Color(0xFF999999),
    ),
    ThemeTokenDescriptor(
      id: 'ruler.label',
      displayName: 'Ruler label',
      lightDefault: Color(0xFF565668),
      darkDefault: WavecruxColors.timeRulerMajorTick,
    ),
    ThemeTokenDescriptor(
      id: 'ruler.cursorTime',
      displayName: 'Ruler cursor time',
      lightDefault: Color(0xFF0277BD),
      darkDefault: WavecruxColors.secondaryCursor,
    ),
    ThemeTokenDescriptor(
      id: 'selection',
      displayName: 'Drag-zoom selection',
      lightDefault: Color(0x220066CC),
      darkDefault: Color(0x22FFFFFF),
    ),
  ],
);

// Chrome token catalog lifted to `crux_theme` as the suite-shared
// [chromeTokens] / [registerCruxThemeChromeTokens] pair (see
// `package:crux_theme/src/chrome_theme_data.dart`). Consumers that
// previously imported `chromeTokens` from this file should switch to
// `import 'package:crux_theme/crux_theme.dart' show chromeTokens;`.
