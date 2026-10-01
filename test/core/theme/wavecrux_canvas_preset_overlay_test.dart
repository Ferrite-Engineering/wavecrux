// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guard on WaveCrux's 20 waveform-canvas token values across all six shared
// built-in presets — 120 colors in total.
//
// These values used to live inside `crux_theme`'s `builtinPresets()`, where
// the package's own `preset signature values match WaveCrux
// defaults` test was the ONLY thing pinning them. That test was narrowed to
// chrome when the canvas tokens moved out to
// [waveCruxCanvasPresetOverlay], so the guard has to move with the values —
// otherwise 120 user-visible colors sit in the tree with nothing asserting
// them and drift silently on the next edit.
//
// The table below is the canonical expectation. It is deliberately spelled
// out literally rather than derived from the overlay: a test that reads its
// expectations out of the thing it is testing guards nothing.
//
// The cursor, marker and ruler rows:
// - Crux Dark / Crux Light: the per-brightness cursor palette the app has
//   always painted (dark: primary #FFEE58, secondary #29B6F6, markers
//   #F48FB1; light: #E65100, #0277BD, #C2185B) on the preset's panel surface.
// - Solarized Dark, High Contrast Dark, Oscilloscope, OLED XR: each preset's
//   own designed cursor, marker and ruler palette.
// - `marker.flagText` equals `marker.flag` everywhere: the letter sits on the
//   ruler below its triangle, so a letter colored for the inside of the
//   triangle (the black the branded designs once carried) would vanish.
// A change to any of these rows is a visible change to shipped presets, not
// a refactor.

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_canvas_preset_overlay.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';

/// Every canvas token value, keyed by preset id then token id.
const Map<String, Map<String, Color>> _expected = <String, Map<String, Color>>{
  'crux-dark': <String, Color>{
    'background': Color(0xFF1A1A1A),
    'lane.backgroundOdd': Color(0xFF1A1A1A),
    'lane.backgroundEven': Color(0xFF1F1F1F),
    'lane.divider': Color(0xFF2D2D2D),
    'group.header': Color(0xFF252525),
    'signal.x.fill': Color(0xFFFF2222),
    'signal.x.hatch': Color(0xFFFF4444),
    'signal.z.line': Color(0xFF888888),
    'cursor.primary': Color(0xFFFFEE58),
    'cursor.secondary': Color(0xFF29B6F6),
    'cursor.delta': Color(0x00000000),
    'marker.line': Color(0x00000000),
    'marker.flag': Color(0xFFF48FB1),
    'marker.flagText': Color(0xFFF48FB1),
    'ruler.background': Color(0xFF141418),
    'ruler.tick': Color(0xFF565668),
    'ruler.tickMajor': Color(0xFF999999),
    'ruler.label': Color(0xFF8888A0),
    'ruler.cursorTime': Color(0xFF29B6F6),
    'selection': Color(0x22FFFFFF),
  },
  'crux-light': <String, Color>{
    'background': Color(0xFFF5F5F5),
    'lane.backgroundOdd': Color(0xFFF5F5F5),
    'lane.backgroundEven': Color(0xFFEFEFEF),
    'lane.divider': Color(0xFFCCCCCC),
    'group.header': Color(0xFFE8E8E8),
    'signal.x.fill': Color(0xFFCC1111),
    'signal.x.hatch': Color(0xFF991111),
    'signal.z.line': Color(0xFF888888),
    'cursor.primary': Color(0xFFE65100),
    'cursor.secondary': Color(0xFF0277BD),
    'cursor.delta': Color(0x00000000),
    'marker.line': Color(0x00000000),
    'marker.flag': Color(0xFFC2185B),
    'marker.flagText': Color(0xFFC2185B),
    'ruler.background': Color(0xFFFFFFFF),
    'ruler.tick': Color(0xFF8888A0),
    'ruler.tickMajor': Color(0xFF555555),
    'ruler.label': Color(0xFF565668),
    'ruler.cursorTime': Color(0xFF0277BD),
    'selection': Color(0x220066CC),
  },
  'solarized-dark': <String, Color>{
    'background': Color(0xFF002B36),
    'lane.backgroundOdd': Color(0xFF002B36),
    'lane.backgroundEven': Color(0xFF073642),
    'lane.divider': Color(0xFF0A4652),
    'group.header': Color(0xFF073642),
    'signal.x.fill': Color(0xFFDC322F),
    'signal.x.hatch': Color(0xFFFF4444),
    'signal.z.line': Color(0xFF586E75),
    'cursor.primary': Color(0xFFB58900),
    'cursor.secondary': Color(0xFFCB4B16),
    'cursor.delta': Color(0x00000000),
    'marker.line': Color(0x00000000),
    'marker.flag': Color(0xFF268BD2),
    'marker.flagText': Color(0xFF268BD2),
    'ruler.background': Color(0xFF073642),
    'ruler.tick': Color(0xFF586E75),
    'ruler.tickMajor': Color(0xFF839496),
    'ruler.label': Color(0xFF93A1A1),
    'ruler.cursorTime': Color(0xFFB58900),
    'selection': Color(0x22268BD2),
  },
  'high-contrast-dark': <String, Color>{
    'background': Color(0xFF000000),
    'lane.backgroundOdd': Color(0xFF000000),
    'lane.backgroundEven': Color(0xFF0D0D0D),
    'lane.divider': Color(0xFF444444),
    'group.header': Color(0xFF1A1A1A),
    'signal.x.fill': Color(0xFFFF0000),
    'signal.x.hatch': Color(0xFFFF6666),
    'signal.z.line': Color(0xFFAAAAAA),
    'cursor.primary': Color(0xFFFFFF00),
    'cursor.secondary': Color(0xFF00FFFF),
    'cursor.delta': Color(0x00000000),
    'marker.line': Color(0x00000000),
    'marker.flag': Color(0xFF00FFFF),
    'marker.flagText': Color(0xFF00FFFF),
    'ruler.background': Color(0xFF000000),
    'ruler.tick': Color(0xFF666666),
    'ruler.tickMajor': Color(0xFFAAAAAA),
    'ruler.label': Color(0xFFFFFFFF),
    'ruler.cursorTime': Color(0xFFFFFF00),
    'selection': Color(0x44FFFFFF),
  },
  'oscilloscope': <String, Color>{
    'background': Color(0xFF000000),
    'lane.backgroundOdd': Color(0xFF000000),
    'lane.backgroundEven': Color(0xFF030A03),
    'lane.divider': Color(0xFF0F2A0F),
    'group.header': Color(0xFF071507),
    'signal.x.fill': Color(0xFFFF3300),
    'signal.x.hatch': Color(0xFFFF6644),
    'signal.z.line': Color(0xFF445544),
    'cursor.primary': Color(0xFF00FF41),
    'cursor.secondary': Color(0xFF66FF88),
    'cursor.delta': Color(0x00000000),
    'marker.line': Color(0x00000000),
    'marker.flag': Color(0xFF66FF88),
    'marker.flagText': Color(0xFF66FF88),
    'ruler.background': Color(0xFF000000),
    'ruler.tick': Color(0xFF1A4A1A),
    'ruler.tickMajor': Color(0xFF2A7A2A),
    'ruler.label': Color(0xFF00FF41),
    'ruler.cursorTime': Color(0xFF00FF41),
    'selection': Color(0x2200FF41),
  },
  'oled-xr': <String, Color>{
    'background': Color(0xFF000000),
    'lane.backgroundOdd': Color(0xFF000000),
    'lane.backgroundEven': Color(0xFF0A0A0A),
    'lane.divider': Color(0xFF1C1C1C),
    'group.header': Color(0xFF101010),
    'signal.x.fill': Color(0xFFFF3B3B),
    'signal.x.hatch': Color(0xFFFF7070),
    'signal.z.line': Color(0xFF9AA0A6),
    'cursor.primary': Color(0xFFFFD400),
    'cursor.secondary': Color(0xFF00E5FF),
    'cursor.delta': Color(0x00000000),
    'marker.line': Color(0x00000000),
    'marker.flag': Color(0xFF34FF8A),
    'marker.flagText': Color(0xFF34FF8A),
    'ruler.background': Color(0xFF000000),
    'ruler.tick': Color(0xFF5A5A5A),
    'ruler.tickMajor': Color(0xFF9AA0A6),
    'ruler.label': Color(0xFFE8E8E8),
    'ruler.cursorTime': Color(0xFFFFD400),
    'selection': Color(0x2AFFFFFF),
  },
};

void main() {
  setUpAll(registerWaveCruxThemeTokens);

  group('waveCruxCanvasPresetOverlay', () {
    test('declares the canvas category', () {
      expect(waveCruxCanvasPresetOverlay.categoryId, canvasTokens.id);
    });

    test('covers every shared built-in preset', () {
      expect(
        waveCruxCanvasPresetOverlay.byPresetId.keys.toSet(),
        builtinPresets().keys.toSet(),
        reason:
            'A preset with no canvas overlay entry paints fallback colors on '
            'the waveform canvas.',
      );
    });

    test('declares exactly the tokens the canvas category defines', () {
      final declared = canvasTokens.tokens.map((t) => t.id).toSet();
      for (final entry in waveCruxCanvasPresetOverlay.byPresetId.entries) {
        expect(
          entry.value.keys.toSet(),
          declared,
          reason: 'preset ${entry.key} does not cover the canvas token set',
        );
      }
    });
  });

  group('canvas color values are pinned', () {
    // One test per preset so a failure names the preset that drifted.
    for (final presetEntry in _expected.entries) {
      test('${presetEntry.key} resolves all 20 canvas tokens', () {
        final preset = builtinPresets()[presetEntry.key];
        expect(preset, isNotNull, reason: 'missing preset ${presetEntry.key}');
        for (final token in presetEntry.value.entries) {
          expect(
            preset!.color(canvasTokens.id, token.key)?.toARGB32(),
            token.value.toARGB32(),
            reason: '${presetEntry.key}/${token.key} drifted',
          );
        }
      });
    }

    test('pins 120 values in total', () {
      final count = _expected.values.fold<int>(0, (n, m) => n + m.length);
      expect(count, 120);
    });

    // Alpha is easy to lose in a hand-edit and invisible in a hex diff, so the
    // translucent tokens get an explicit assertion. `oled-xr`'s `selection` in
    // particular is 0x2A, not the 0x22 every other preset uses, and a
    // non-zero `cursor.delta` alpha would switch the delta band on.
    test('translucent tokens keep their exact alpha', () {
      final presets = builtinPresets();
      expect(
        presets['oled-xr']!.color(canvasTokens.id, 'selection')?.toARGB32(),
        0x2AFFFFFF,
      );
      expect(
        presets['crux-dark']!
            .color(canvasTokens.id, 'cursor.delta')
            ?.toARGB32(),
        0x00000000,
      );
      expect(
        presets['high-contrast-dark']!
            .color(canvasTokens.id, 'selection')
            ?.toARGB32(),
        0x44FFFFFF,
      );
    });

    test('the delta band and marker lines are off in every preset', () {
      for (final entry in builtinPresets().entries) {
        for (final token in ['cursor.delta', 'marker.line']) {
          expect(
            entry.value.color(canvasTokens.id, token)?.a,
            0,
            reason: '${entry.key}/$token would draw an overlay by default',
          );
        }
      }
    });

    test('a marker letter takes its triangle color in every preset', () {
      for (final entry in builtinPresets().entries) {
        expect(
          entry.value.color(canvasTokens.id, 'marker.flagText')?.toARGB32(),
          entry.value.color(canvasTokens.id, 'marker.flag')?.toARGB32(),
          reason:
              '${entry.key}: the letter is drawn on the ruler, not on the '
              'triangle',
        );
      }
    });

    test('the two cursors differ in every preset', () {
      for (final entry in builtinPresets().entries) {
        expect(
          entry.value.color(canvasTokens.id, 'cursor.secondary')?.toARGB32(),
          isNot(
            entry.value.color(canvasTokens.id, 'cursor.primary')?.toARGB32(),
          ),
          reason: entry.key,
        );
      }
    });
  });

  // A theme pack may omit any token; it then resolves to the registered
  // default for its brightness. Those defaults must be the Crux Dark / Crux
  // Light values, or an omitted cursor or ruler token would paint a color no
  // preset shows.
  group('registered defaults', () {
    for (final (presetId, brightness) in [
      ('crux-dark', Brightness.dark),
      ('crux-light', Brightness.light),
    ]) {
      test('equal $presetId for every canvas token', () {
        for (final descriptor in canvasTokens.tokens) {
          expect(
            descriptor.defaultFor(brightness).toARGB32(),
            _expected[presetId]![descriptor.id]!.toARGB32(),
            reason: '${descriptor.id} $brightness default',
          );
        }
      });
    }
  });
}
