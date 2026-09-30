// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The theme bridge's actual deliverable is legibility, not plumbing — see the
// module docs on `editor_host_theme_synthesizer.dart`. So most of what this
// file pins is a measured contrast ratio, not a specific hex value: the
// exact color a VSCode theme yields is allowed to vary (VSCode theme authors
// vary it constantly), but the floor this synthesizer promises is not.

import 'package:crux_theme/crux_theme.dart' show ChromeTokens, chromeTokens;
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/editor_host_theme_synthesizer.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';

void main() {
  // Approximates VSCode's own built-in "Dark+ (default dark)" theme. Not
  // sourced from a live VSCode instance (the point of the shim's own tests,
  // in crux-vscode, is that it reads the real thing) — this is a realistic
  // *shape* of what the shim relays, close enough to the published theme's
  // documented colors to be a meaningful fixture rather than an arbitrary
  // one.
  const darkPlusTokens = <String, String>{
    'editor.background': '#1E1E1E',
    'editor.foreground': '#D4D4D4',
    'editorCursor.foreground': '#AEAFAD',
    'editor.selectionBackground': '#264F78',
    'editorIndentGuide.background': '#404040',
    'editorWidget.background': '#252526',
    'sideBar.background': '#252526',
    'sideBar.foreground': '#CCCCCC',
    'sideBarSectionHeader.background': '#2D2D30',
    'sideBarSectionHeader.foreground': '#CCCCCC',
    'panel.border': '#80808059', // 8-digit #RRGGBBAA on purpose — see below.
    'statusBar.background': '#007ACC',
    'statusBar.foreground': '#FFFFFF',
    'titleBar.activeBackground': '#3C3C3C',
    'titleBar.activeForeground': '#CCCCCC',
    'tab.activeBackground': '#1E1E1E',
    'tab.inactiveBackground': '#2D2D2D',
    'tab.activeForeground': '#FFFFFF',
    'focusBorder': '#007FD4',
    'textLink.foreground': '#3794FF',
    'descriptionForeground': '#CCCCCCB3',
    'errorForeground': '#F48771',
    'charts.red': '#F14C4C',
    'charts.orange': '#D18616',
    'charts.yellow': '#CCA700',
    'charts.blue': '#3794FF',
  };

  // Approximates VSCode's built-in "Light+ (default light)" theme.
  const lightPlusTokens = <String, String>{
    'editor.background': '#FFFFFF',
    'editor.foreground': '#000000',
    'editorCursor.foreground': '#000000',
    'editor.selectionBackground': '#ADD6FF',
    'editorIndentGuide.background': '#D3D3D3',
    'editorWidget.background': '#F3F3F3',
    'sideBar.background': '#F3F3F3',
    'sideBar.foreground': '#616161',
    'sideBarSectionHeader.background': '#E7E7E7',
    'sideBarSectionHeader.foreground': '#616161',
    'panel.border': '#80808059',
    'statusBar.background': '#007ACC',
    'statusBar.foreground': '#FFFFFF',
    'titleBar.activeBackground': '#DDDDDD',
    'titleBar.activeForeground': '#333333',
    'tab.activeBackground': '#FFFFFF',
    'tab.inactiveBackground': '#ECECEC',
    'tab.activeForeground': '#333333',
    'focusBorder': '#0090F1',
    'textLink.foreground': '#006AB1',
    'descriptionForeground': '#717171B3',
    'errorForeground': '#A1260D',
    'charts.red': '#CD3131',
    'charts.orange': '#D18616',
    'charts.yellow': '#825E00',
    'charts.blue': '#006AB1',
  };

  group('appearance -> brightness (WCAG-2.1-relevant, not just cosmetic)', () {
    test('light and dark map straightforwardly', () {
      expect(
        synthesizeEditorHostTheme(
          appearance: 'light',
          tokens: lightPlusTokens,
        ).brightness,
        Brightness.light,
      );
      expect(
        synthesizeEditorHostTheme(
          appearance: 'dark',
          tokens: darkPlusTokens,
        ).brightness,
        Brightness.dark,
      );
    });

    test(
      'the two high-contrast kinds are NOT folded into dark — each keeps '
      "its own brightness so an omitted token's registry fallback is the "
      'right half of the pair',
      () {
        expect(
          synthesizeEditorHostTheme(
            appearance: 'highContrast',
            tokens: darkPlusTokens,
          ).brightness,
          Brightness.dark,
        );
        expect(
          synthesizeEditorHostTheme(
            appearance: 'highContrastLight',
            tokens: lightPlusTokens,
          ).brightness,
          Brightness.light,
        );
      },
    );
  });

  group('contrastRatio', () {
    test('black on white (and the reverse) is the WCAG maximum, 21:1', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
      expect(
        contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        closeTo(21.0, 0.01),
      );
    });

    test('a color against itself is the WCAG minimum, 1:1', () {
      const c = Color(0xFF3794FF);
      expect(contrastRatio(c, c), closeTo(1.0, 0.001));
    });
  });

  group('legibility floor — ordinary dark theme', () {
    late final theme = synthesizeEditorHostTheme(
      appearance: 'dark',
      tokens: darkPlusTokens,
    );
    late final background = theme.color(canvasTokens.id, 'background')!;

    test('ruler.label clears the 4.5:1 text floor', () {
      final ratio = contrastRatio(
        theme.color(canvasTokens.id, 'ruler.label')!,
        background,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(kEditorHostTextContrastFloor),
        reason: 'canvas.ruler.label only reaches ${ratio.toStringAsFixed(2)}:1',
      );
    });

    test('graphical tokens clear the 3:1 non-text floor', () {
      for (final tokenId in [
        'signal.x.fill',
        'signal.z.line',
        'cursor.primary',
        'cursor.secondary',
        'marker.flag',
        'ruler.tickMajor',
      ]) {
        final ratio = contrastRatio(
          theme.color(canvasTokens.id, tokenId)!,
          background,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(kEditorHostGraphicContrastFloor),
          reason: 'canvas.$tokenId only reaches ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    // The time ruler draws a marker's letter beside its flag and the
    // delta-time readout over its own tint, both on the ruler background —
    // so that is the pair each must clear, not the flag or canvas color.
    test('ruler text tokens clear the text floor against the ruler', () {
      final ruler = theme.color(canvasTokens.id, 'ruler.background')!;
      for (final tokenId in ['marker.flagText', 'ruler.cursorTime']) {
        final ratio = contrastRatio(
          theme.color(canvasTokens.id, tokenId)!,
          ruler,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(kEditorHostTextContrastFloor),
          reason: 'canvas.$tokenId only reaches ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('legibility floor — ordinary light theme', () {
    late final theme = synthesizeEditorHostTheme(
      appearance: 'light',
      tokens: lightPlusTokens,
    );
    late final background = theme.color(canvasTokens.id, 'background')!;

    test('text and graphical tokens both clear their floors', () {
      expect(
        contrastRatio(
          theme.color(canvasTokens.id, 'ruler.label')!,
          background,
        ),
        greaterThanOrEqualTo(kEditorHostTextContrastFloor),
      );
      for (final tokenId in [
        'signal.x.fill',
        'signal.z.line',
        'cursor.primary',
        'marker.flag',
      ]) {
        expect(
          contrastRatio(theme.color(canvasTokens.id, tokenId)!, background),
          greaterThanOrEqualTo(kEditorHostGraphicContrastFloor),
        );
      }
    });
  });

  group('legibility floor — high contrast kinds get a stricter floor', () {
    test('highContrast (dark) clears 7:1 text / 4.5:1 graphic', () {
      final theme = synthesizeEditorHostTheme(
        appearance: 'highContrast',
        tokens: darkPlusTokens,
      );
      final background = theme.color(canvasTokens.id, 'background')!;
      expect(
        contrastRatio(
          theme.color(canvasTokens.id, 'ruler.label')!,
          background,
        ),
        greaterThanOrEqualTo(kEditorHostHighContrastTextFloor),
      );
      expect(
        contrastRatio(
          theme.color(canvasTokens.id, 'signal.x.fill')!,
          background,
        ),
        greaterThanOrEqualTo(kEditorHostHighContrastGraphicFloor),
      );
    });

    test('highContrastLight (light) clears the same stricter floors', () {
      final theme = synthesizeEditorHostTheme(
        appearance: 'highContrastLight',
        tokens: lightPlusTokens,
      );
      final background = theme.color(canvasTokens.id, 'background')!;
      expect(
        contrastRatio(
          theme.color(canvasTokens.id, 'ruler.label')!,
          background,
        ),
        greaterThanOrEqualTo(kEditorHostHighContrastTextFloor),
      );
    });
  });

  group('adjustment, not luck', () {
    test(
      'a raw accent color matching the background is walked to legible '
      'rather than left invisible',
      () {
        // The adversarial case: a hypothetical VSCode theme whose "red" is
        // indistinguishable from its editor background. A synthesizer that
        // merely copied the raw token would render an invisible X-state
        // fill; this one must walk it to the floor.
        const adversarial = <String, String>{
          'editor.background': '#202020',
          'editor.foreground': '#E0E0E0',
          'charts.red': '#202020', // == editor.background, exactly
        };
        final theme = synthesizeEditorHostTheme(
          appearance: 'dark',
          tokens: adversarial,
        );
        final background = theme.color(canvasTokens.id, 'background')!;
        final fill = theme.color(canvasTokens.id, 'signal.x.fill')!;
        expect(fill, isNot(background));
        expect(
          contrastRatio(fill, background),
          greaterThanOrEqualTo(kEditorHostGraphicContrastFloor),
        );
      },
    );

    test(
      'a near-invisible text token is walked to the stricter high-contrast '
      'floor, not merely the ordinary one',
      () {
        const adversarial = <String, String>{
          'editor.background': '#101010',
          'editor.foreground': '#151515', // barely off the background
        };
        final ordinary = synthesizeEditorHostTheme(
          appearance: 'dark',
          tokens: adversarial,
        );
        final highContrast = synthesizeEditorHostTheme(
          appearance: 'highContrast',
          tokens: adversarial,
        );
        final bg = ordinary.color(canvasTokens.id, 'background')!;
        expect(
          contrastRatio(
            ordinary.color(canvasTokens.id, 'ruler.label')!,
            bg,
          ),
          greaterThanOrEqualTo(kEditorHostTextContrastFloor),
        );
        expect(
          contrastRatio(
            highContrast.color(canvasTokens.id, 'ruler.label')!,
            bg,
          ),
          greaterThanOrEqualTo(kEditorHostHighContrastTextFloor),
        );
      },
    );
  });

  group('canvas is its own palette, not a chrome derivation', () {
    test(
      'canvas.background tracks the editor surface, not the sidebar/tab '
      'surfaces chrome tokens read',
      () {
        final theme = synthesizeEditorHostTheme(
          appearance: 'dark',
          tokens: darkPlusTokens,
        );
        // Fixture deliberately gives sideBar/tab/titleBar different hex
        // values from editor.background so this is a real assertion, not a
        // coincidence of the fixture.
        expect(
          theme.color(canvasTokens.id, 'background'),
          const Color(0xFF1E1E1E), // editor.background
        );
        expect(
          theme.color(chromeTokens.id, ChromeTokens.panelBackground),
          const Color(0xFF252526), // sideBar.background — different token
        );
        expect(
          theme.color(chromeTokens.id, ChromeTokens.toolbarBackground),
          const Color(0xFF3C3C3C), // titleBar.activeBackground
        );
      },
    );

    test(
      'lane.backgroundEven is a distinguishable tint, not identical to '
      'lane.backgroundOdd (which equals canvas.background exactly)',
      () {
        final theme = synthesizeEditorHostTheme(
          appearance: 'dark',
          tokens: darkPlusTokens,
        );
        final odd = theme.color(canvasTokens.id, 'lane.backgroundOdd')!;
        final even = theme.color(canvasTokens.id, 'lane.backgroundEven')!;
        expect(odd, theme.color(canvasTokens.id, 'background'));
        expect(even, isNot(odd));
      },
    );
  });

  group('missing tokens fall back to brightness-appropriate built-ins', () {
    test('an empty token map still yields a usable dark theme', () {
      final theme = synthesizeEditorHostTheme(appearance: 'dark', tokens: {});
      expect(theme.brightness, Brightness.dark);
      final background = theme.color(canvasTokens.id, 'background')!;
      expect(
        contrastRatio(
          theme.color(canvasTokens.id, 'ruler.label')!,
          background,
        ),
        greaterThanOrEqualTo(kEditorHostTextContrastFloor),
      );
    });

    test('an empty token map still yields a usable light theme', () {
      final theme = synthesizeEditorHostTheme(
        appearance: 'light',
        tokens: {},
      );
      expect(theme.brightness, Brightness.light);
    });
  });

  test('leaves the optional canvas overlays off, as every preset does', () {
    // `cursor.delta` and `marker.line` turn on a band between the cursors
    // and a line at each named marker. Left unset, they resolve to the
    // registry's transparent default and nothing is drawn.
    for (final appearance in ['dark', 'light', 'highContrast']) {
      final theme = synthesizeEditorHostTheme(
        appearance: appearance,
        tokens: appearance == 'light' ? lightPlusTokens : darkPlusTokens,
      );
      expect(theme.color(canvasTokens.id, 'cursor.delta'), isNull);
      expect(theme.color(canvasTokens.id, 'marker.line'), isNull);
    }
  });

  test('the synthesized theme id is never a built-in preset id', () {
    // `WaveCruxCruxColorThemeNotifier.applyEphemeral` relies on this: see
    // its doc comment in wavecrux_color_theme_bootstrap.dart.
    expect(kEditorHostThemeId, isNot('crux-dark'));
    expect(kEditorHostThemeId, isNot('crux-light'));
    expect(kEditorHostThemeId, contains('.'));
  });
}
