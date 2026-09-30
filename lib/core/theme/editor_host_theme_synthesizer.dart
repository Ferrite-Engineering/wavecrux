// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Synthesizes a WaveCrux [CruxColorTheme] from the VSCode color tokens the
// webview shim relays over the editor-host bridge.
//
// This is a new SOURCE for WaveCrux's existing JSON-first theme mechanism,
// not a new mechanism. The result is an ordinary [CruxColorTheme]: resolved
// by the same [ThemeRegistry] every built-in preset and `.crux-theme.json`
// pack goes through (`WaveCruxThemeAccessors._canvas` in
// `wavecrux_theme_accessors.dart` for the canvas, `applyChromeTokens` for the
// chrome), and applied through the same `cruxColorThemeProvider` every preset switch uses
// (`WaveCruxCruxColorThemeNotifier.applyEphemeral`, see
// `wavecrux_color_theme_bootstrap.dart`). A token this function does not set
// falls back to the registry's brightness-appropriate default exactly as it
// would for a hand-authored theme pack that omits the same token — that is
// what keeps this function short: it only has to set the tokens it can
// derive with confidence, not the whole catalog.
//
// Hex parsing reuses `ThemePackCodec.tryParseColor` — the established
// `#RRGGBB`/`#RRGGBBAA` convention theme packs and settings overrides
// already use — rather than a second color-string format.
//
// ### Where the read happens, and why this file never touches a webview
//
// VSCode does not hand an extension host process a resolved color palette;
// the extension host is Node.js with no DOM. The only place a real,
// currently-active theme's resolved colors exist is the webview document
// itself, as `--vscode-*` CSS custom properties VSCode injects and keeps
// live-updated. So the *read* happens in crux-vscode's webview shim
// (`packages/wavecrux/src/webview/html.ts`), not in this repo and not in the
// extension host — this function only ever sees the curated, already-decoded
// result, carried by [HostBridgeThemeTokens] the same way every other
// editor-host frame arrives.

import 'dart:math' as math;

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness, Color, HSLColor;
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';

/// Minimum contrast ratio (WCAG 2.1 SC 1.4.3, normal text) required of every
/// canvas token that carries text under an ordinary (non-high-contrast)
/// VSCode theme: `ruler.label`, and the marker letter and delta-time readout
/// colors computed here.
const double kEditorHostTextContrastFloor = 4.5;

/// Minimum contrast ratio (WCAG 2.1 SC 1.4.11, non-text) required of the
/// canvas' graphical tokens — trace fills, cursors, marker flags, and the
/// major ruler tick — against `canvas.background`, under an ordinary VSCode
/// theme. Lower than the text floor on purpose: a 1px cursor line does not
/// need to clear a body-text bar to be legible, but it does need to clear
/// "arguably invisible".
const double kEditorHostGraphicContrastFloor = 3;

/// [kEditorHostTextContrastFloor], but for `highContrast` /
/// `highContrastLight`. Those VSCode theme kinds exist precisely so a
/// low-vision user gets more separation than the ordinary floor promises;
/// answering that intent with the ordinary floor would quietly discard the
/// reason the user picked the theme. WCAG 2.1's own AAA text criterion
/// (1.4.6) is 7:1, so that is the number used rather than an invented one.
const double kEditorHostHighContrastTextFloor = 7;

/// [kEditorHostGraphicContrastFloor], but for `highContrast` /
/// `highContrastLight`.
const double kEditorHostHighContrastGraphicFloor = 4.5;

/// Stable id for the theme this function builds.
///
/// Never a built-in preset id — `builtinPresetById(kEditorHostThemeId)` must
/// return `null` so `WaveCruxCruxColorThemeNotifier._persistDerivedFromTheme`
/// (which only runs for [WaveCruxCruxColorThemeNotifier.activate], not
/// [WaveCruxCruxColorThemeNotifier.applyEphemeral]) can never mistake this
/// for a preset selection if the two code paths are ever unified.
const String kEditorHostThemeId = 'editor-host.vscode';

/// Maps `vscode.ColorThemeKind` (as relayed in [appearance]) to the
/// [Brightness] `CruxColorTheme.brightness` and every registry fallback
/// resolves against.
///
/// Both high-contrast kinds map to their non-high-contrast brightness
/// (`highContrast` → dark, `highContrastLight` → light) rather than being
/// folded together: `highContrastLight` is visually a light theme with wider
/// margins, and resolving it to [Brightness.dark] would hand every omitted
/// token the wrong half of its registered descriptor's fallback pair. What
/// *does* change for a high-contrast kind is the contrast floor this
/// synthesizer enforces on the tokens it does set — see
/// [kEditorHostHighContrastTextFloor].
Brightness _brightnessOf(String appearance) =>
    (appearance == 'light' || appearance == 'highContrastLight')
    ? Brightness.light
    : Brightness.dark;

bool _isHighContrast(String appearance) =>
    appearance == 'highContrast' || appearance == 'highContrastLight';

/// Builds a [CruxColorTheme] from the raw VSCode tokens a
/// `HostBridgeThemeTokens` frame carried.
///
/// [tokens] is keyed by VSCode's dotted color id (`editor.background`, …)
/// with `#RRGGBB`/`#RRGGBBAA` values, exactly as the frame carries them; a
/// value this function cannot parse is treated as absent, same as a missing
/// key. [appearance] must be one of `kHostBridgeThemeAppearances` — the
/// caller (`HostBridgeThemeTokens.tryFromJson`) already validated that, so
/// it is not re-validated here.
CruxColorTheme synthesizeEditorHostTheme({
  required String appearance,
  required Map<String, String> tokens,
}) {
  final brightness = _brightnessOf(appearance);
  final highContrast = _isHighContrast(appearance);
  final textFloor = highContrast
      ? kEditorHostHighContrastTextFloor
      : kEditorHostTextContrastFloor;
  final graphicFloor = highContrast
      ? kEditorHostHighContrastGraphicFloor
      : kEditorHostGraphicContrastFloor;

  Color? raw(String vscodeId) {
    final value = tokens[vscodeId];
    if (value == null) return null;
    return ThemePackCodec.tryParseColor(value);
  }

  const lightDefaultBg = Color(0xFFFFFFFF);
  const darkDefaultBg = Color(0xFF1E1E1E);
  const lightDefaultFg = Color(0xFF000000);
  const darkDefaultFg = Color(0xFFD4D4D4);

  final background =
      raw('editor.background') ??
      (brightness == Brightness.light ? lightDefaultBg : darkDefaultBg);
  final foreground =
      raw('editor.foreground') ??
      (brightness == Brightness.light ? lightDefaultFg : darkDefaultFg);

  // ── Canvas: the waveform surface's own palette ──────────────────────────
  //
  // Deliberately NOT a mechanical derivation from the chrome tokens below —
  // the prompt this file exists for calls that out explicitly. VSCode has no
  // color id for "alternating waveform lane" or "X-state fill", so most of
  // these are blended from editor.background/editor.foreground (an
  // in-context tint, the same move a theme-pack author would make) or read
  // from VSCode's small "accent" palette (`charts.*`), then walked toward
  // legible via [_ensureContrast] when the raw reading falls short of
  // [textFloor] / [graphicFloor].
  final canvas = <String, Color>{
    'background': background,
    'lane.backgroundOdd': background,
    'lane.backgroundEven': _tint(background, foreground, 0.05),
    'lane.divider':
        raw('editorIndentGuide.background') ??
        _tint(background, foreground, 0.14),
    'group.header':
        raw('sideBarSectionHeader.background') ??
        raw('editorWidget.background') ??
        _tint(background, foreground, 0.08),
    'signal.x.fill': _graphic(
      raw('charts.red') ?? raw('errorForeground'),
      background,
      graphicFloor,
      fallback: brightness == Brightness.light
          ? const Color(0xFFCC1111)
          : const Color(0xFFFF2222),
    ),
    'signal.z.line': _graphic(
      raw('descriptionForeground'),
      background,
      graphicFloor,
      fallback: const Color(0xFF888888),
    ),
    'cursor.primary': _graphic(
      raw('charts.yellow') ?? raw('editorCursor.foreground'),
      background,
      graphicFloor,
      fallback: brightness == Brightness.light
          ? const Color(0xFF886600)
          : const Color(0xFFFFFF00),
    ),
    'cursor.secondary': _graphic(
      raw('charts.orange') ?? raw('charts.blue'),
      background,
      graphicFloor,
      fallback: brightness == Brightness.light
          ? const Color(0xFF0066AA)
          : const Color(0xFFFF8000),
    ),
    'marker.flag': _graphic(
      raw('charts.blue') ?? raw('textLink.foreground'),
      background,
      graphicFloor,
      fallback: brightness == Brightness.light
          ? const Color(0xFF0066CC)
          : const Color(0xFF44AAFF),
    ),
    'ruler.background': _tint(background, foreground, 0.03),
    'ruler.tickMajor': _graphic(
      foreground,
      background,
      graphicFloor,
      fallback: foreground,
    ),
    'ruler.label': _ensureContrast(foreground, background, textFloor),
    'selection': (raw('editor.selectionBackground') ?? foreground).withValues(
      alpha: brightness == Brightness.light ? 0.13 : 0.20,
    ),
  };
  // The remaining canvas tokens are deliberately *not* independently sourced
  // — each repeats or lightly transforms a token set above, because VSCode's
  // token set gives this function one accent color to spend on "the
  // interactive-marker family", not several, and re-deriving each from
  // scratch would just add more ways for the palette to disagree with
  // itself.
  //
  // The two text tokens among them are floored against `ruler.background`,
  // because that is what they are drawn on: the time ruler paints a named
  // marker's letter beside its flag, not on it, and the delta-time readout
  // in the color of the secondary cursor whose tint sits behind it.
  canvas['signal.x.hatch'] = _tint(canvas['signal.x.fill']!, foreground, 0.18);
  canvas['marker.flagText'] = _ensureContrast(
    canvas['marker.flag']!,
    canvas['ruler.background']!,
    textFloor,
  );
  canvas['ruler.cursorTime'] = _ensureContrast(
    canvas['cursor.secondary']!,
    canvas['ruler.background']!,
    textFloor,
  );
  canvas['ruler.tick'] = (raw('descriptionForeground') ?? foreground)
      .withValues(alpha: 0.50);
  // `cursor.delta` and `marker.line` are left unset on purpose. They color
  // optional overlays (a band between the cursors, a line through the canvas
  // at each marker) that every built-in preset leaves off, so the registry's
  // transparent default keeps them off here too: embedding WaveCrux in an
  // editor recolors it, it does not turn features on.

  // ── Chrome: application shell, no per-token contrast floor ──────────────
  //
  // Every chrome token here feeds Material `ColorScheme`/`AppBarTheme`
  // overrides (`applyChromeTokens`), which already carries its own
  // onSurface/foreground pairing logic; re-deriving a floor here would be a
  // second, competing contrast policy for the same pixels.
  final chrome = <String, Color>{
    ChromeTokens.scaffoldBackground: background,
    ChromeTokens.panelBackground: raw('sideBar.background') ?? background,
    ChromeTokens.panelHeaderBackground:
        raw('sideBarSectionHeader.background') ?? background,
    ChromeTokens.panelHeaderForeground:
        raw('sideBarSectionHeader.foreground') ??
        raw('sideBar.foreground') ??
        foreground,
    ChromeTokens.toolbarBackground:
        raw('titleBar.activeBackground') ?? background,
    ChromeTokens.toolbarIcon: raw('titleBar.activeForeground') ?? foreground,
    'toolbar.iconActive': raw('focusBorder') ?? foreground,
    'statusBar.background': raw('statusBar.background') ?? background,
    'statusBar.foreground': raw('statusBar.foreground') ?? foreground,
    'splitter': raw('panel.border') ?? _tint(background, foreground, 0.14),
    'splitter.hover': raw('focusBorder') ?? foreground,
    'tabBar.background': raw('tab.inactiveBackground') ?? background,
    'tabBar.selected': raw('tab.activeBackground') ?? background,
    'tabBar.label': raw('tab.activeForeground') ?? foreground,
  };

  return CruxColorTheme(
    id: kEditorHostThemeId,
    // Never rendered: `applyEphemeral` never persists this theme, and
    // `ColorThemeSection`'s preset grid enumerates `builtinPresets()`, which
    // never contains it (see `kEditorHostThemeId`). If that ever changes,
    // this needs to become an L10N string.
    displayName: 'VSCode',
    brightness: brightness,
    tokens: <String, Map<String, Color>>{
      canvasTokens.id: canvas,
      chromeTokens.id: chrome,
    },
  );
}

/// Blends [foreground] into [background] at [amount] (`0..1`) — the move a
/// theme-pack author makes by hand for "a slightly offset surface" when no
/// dedicated color exists for it (an alternating lane row, a faint divider).
/// A fixed hex would ignore whether the host theme is warm, cool, or near-
/// monochrome; blending against the theme's own two anchor colors tracks it.
Color _tint(Color background, Color foreground, double amount) =>
    Color.lerp(background, foreground, amount.clamp(0.0, 1.0))!;

Color _graphic(
  Color? candidate,
  Color background,
  double minRatio, {
  required Color fallback,
}) => _ensureContrast(candidate ?? fallback, background, minRatio);

/// Returns [candidate] unchanged if it already clears [minRatio] against
/// [background]; otherwise walks its HSL lightness toward whichever of
/// black/white contrasts better with [background], stopping the moment the
/// floor is cleared.
///
/// A fixed walk rather than a binary search: canvas colors are derived a
/// handful of times per session (theme load, and each live toggle), never
/// per frame, so the loop's clarity matters more than the constant-factor
/// speed a search would buy. The direction is chosen once, toward the
/// endpoint the walk is guaranteed to reach — that is what makes
/// termination independent of [candidate]'s starting hue: black and white
/// are the two extremes of lightness, and one of them always clears any
/// floor at most `21.0` (WCAG's maximum possible ratio) demands.
Color _ensureContrast(Color candidate, Color background, double minRatio) {
  if (contrastRatio(candidate, background) >= minRatio) return candidate;
  final towardWhite =
      contrastRatio(const Color(0xFFFFFFFF), background) >=
      contrastRatio(const Color(0xFF000000), background);
  var hsl = HSLColor.fromColor(candidate);
  const step = 0.02;
  for (var i = 0; i < 50; i++) {
    final nextLightness = (hsl.lightness + (towardWhite ? step : -step)).clamp(
      0.0,
      1.0,
    );
    if (nextLightness == hsl.lightness) break;
    hsl = hsl.withLightness(nextLightness);
    final next = hsl.toColor();
    if (contrastRatio(next, background) >= minRatio) return next;
  }
  return towardWhite ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
}

/// WCAG 2.1 relative-luminance contrast ratio between [a] and [b], in
/// `1.0..21.0`. Order-independent — the same formula every floor in this
/// file, and this file's test, uses, so "contrast ratio" means one thing
/// throughout.
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
