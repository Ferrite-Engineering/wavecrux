// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: asserts which theme color each cursor-layer and
// time-ruler element is painted with. The text both widgets render is swept
// across en/zh_CN/ja/ko in cursor_overlay_test.dart and
// time_ruler_widget_test.dart.
//
// Every `canvas` token in Settings ▸ Appearance must repaint something. The
// cursor, marker and ruler tokens were once registered, preset, editable and
// set by theme packs while the cursor layer and the ruler painted a fixed
// palette, so an edit silently did nothing. Each test here sets one token to
// a color nothing else uses, through the same `applyOverrides` path the token
// editor calls, and asserts the element that token names is painted with it.
// Geometry is read from the recorded canvas calls; text color, which a
// recorded paragraph does not expose, is read from the rendered pixels.
//
// The default-preset tests pin the other half of the contract: an unedited
// theme paints exactly the colors these elements had before the tokens were
// wired.

import 'dart:ui' as ui;

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/cursor_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

// ── fixture ───────────────────────────────────────────────────────────────────
//
// Fit-all over [0, 1000] at 800 px: ticksPerPixel = 1.25, so
//   primary cursor   t=200 → x=160      marker a  t=100 → x=80
//   secondary cursor t=600 → x=480      marker b  t=400 → x=320

const double _width = 800;
const double _overlayHeight = 160;

class _Mapper extends TimeMapperNotifier {
  @override
  TimeMapper build() =>
      TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: _width);
}

class _Cursors extends CursorStateNotifier {
  @override
  CursorState build() =>
      const CursorState(primaryCursorTime: 200, secondaryCursorTime: 600);
}

class _Markers extends MarkerStateNotifier {
  @override
  MarkerState build() =>
      const MarkerState().setMarker('a', 100).setMarker('b', 400);
}

/// Colors no preset uses, one per token under test.
const _primary = Color(0xFFA0B0C0);
const _secondary = Color(0xFFC0D0E0);
const _delta = Color(0x40FF00FF);
const _markerLine = Color(0xFF00FFAA);
const _markerFlag = Color(0xFF708090);
const _markerFlagText = Color(0xFF3579BD);
const _rulerBackground = Color(0xFF102030);
const _rulerTick = Color(0xFF405060);
const _rulerLabel = Color(0xFF13579B);
const _rulerCursorTime = Color(0xFF2468AC);

Future<ProviderContainer> _pumpHarness(
  WidgetTester tester, {
  CruxColorTheme? preset,
  ThemeData? materialTheme,
  bool loaded = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (loaded) timeMapperProvider.overrideWith(_Mapper.new),
      cursorStateProvider.overrideWith(_Cursors.new),
      markerStateProvider.overrideWith(_Markers.new),
      cruxColorThemeProvider.overrideWith(
        () => CruxColorThemeNotifier(initial: preset ?? defaultBuiltinPreset()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: materialTheme ?? WavecruxTheme.dark,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: _width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TimeRulerWidget(),
                SizedBox(height: _overlayHeight, child: CursorOverlay()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Sets [overrides] (dotted `canvas.<token>` ids) exactly as the Settings
/// token editor does, then lets the change reach the painters.
Future<void> _edit(
  WidgetTester tester,
  ProviderContainer container,
  Map<String, Color> overrides,
) async {
  container.read(cruxColorThemeProvider.notifier).applyOverrides(overrides);
  await tester.pump();
}

/// Runs the pending frame only through layout, records whether the
/// [CustomPaint] under [paint] asked to be repainted, then completes the
/// frame.
///
/// A painter whose `shouldRepaint` ignores a change leaves its layer showing
/// the old picture until something unrelated invalidates it. The frame is
/// completed before the caller asserts, so a failed assertion cannot leave
/// the binding stopping every later test's frames short of paint.
Future<bool> _repaintRequested(WidgetTester tester, Finder paint) async {
  await tester.pump(Duration.zero, EnginePhase.layout);
  final requested = tester
      .renderObject<RenderCustomPaint>(paint)
      .debugNeedsPaint;
  // The partial pump consumed the scheduled frame; request another.
  tester.binding.scheduleFrame();
  await tester.pump();
  return requested;
}

final Finder _rulerPaint = find.descendant(
  of: find.byType(TimeRulerWidget),
  matching: find.byType(CustomPaint),
);

final Finder _overlayPaint = find.descendant(
  of: find.byType(CursorOverlay),
  matching: find.byType(CustomPaint),
);

typedef _Call = ({Symbol method, List<dynamic> args});

/// Every canvas call [finder]'s painter makes, in order.
List<_Call> _record(Finder finder) {
  final calls = <_Call>[];
  expect(
    finder,
    paints..everything((method, args) {
      calls.add((method: method, args: args));
      return true;
    }),
  );
  return calls;
}

Iterable<({List<dynamic> args, Paint paint})> _drawn(
  List<_Call> calls,
  Symbol method,
) => calls
    .where((c) => c.method == method)
    .map((c) => (args: c.args, paint: c.args.last as Paint));

Iterable<({List<dynamic> args, Paint paint})> _inColor(
  List<_Call> calls,
  Symbol method,
  Color color,
) => _drawn(
  calls,
  method,
).where((d) => d.paint.color.toARGB32() == color.toARGB32());

/// The distinct ARGB values in [widget]'s rendered layer.
Future<Set<int>> _renderedColors(WidgetTester tester, Finder widget) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.descendant(of: widget, matching: find.byType(RepaintBoundary)).first,
  );
  final colors = <int>{};
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      colors.add(
        (bytes[i + 3] << 24) |
            (bytes[i] << 16) |
            (bytes[i + 1] << 8) |
            bytes[i + 2],
      );
    }
  });
  return colors;
}

void main() {
  setUpAll(registerWaveCruxThemeTokens);

  group('CursorOverlay paints the canvas theme', () {
    testWidgets('cursor.primary colors the primary cursor line', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {'canvas.cursor.primary': _primary});

      final lines = _inColor(_record(_overlayPaint), #drawLine, _primary);
      expect(lines, hasLength(1));
      final (from, to) = (lines.single.args[0], lines.single.args[1]);
      expect((from as Offset).dx, 160);
      expect((to as Offset).dy, _overlayHeight);
    });

    testWidgets('cursor.secondary colors the dashed secondary line', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {'canvas.cursor.secondary': _secondary});

      final dashes = _inColor(_record(_overlayPaint), #drawLine, _secondary);
      expect(dashes.length, greaterThan(1), reason: 'a dashed line');
      expect(dashes.every((d) => (d.args[0] as Offset).dx == 480), isTrue);
    });

    testWidgets('cursor.delta fills the band between the two cursors', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {'canvas.cursor.delta': _delta});

      final bands = _inColor(_record(_overlayPaint), #drawRect, _delta);
      expect(bands, hasLength(1));
      expect(
        bands.single.args[0],
        const Rect.fromLTRB(160, 0, 480, _overlayHeight),
      );
    });

    testWidgets('marker.line draws a line at each named marker', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {'canvas.marker.line': _markerLine});

      final lines = _inColor(_record(_overlayPaint), #drawLine, _markerLine);
      expect(
        lines.map((d) => (d.args[0] as Offset).dx).toSet(),
        {80.0, 320.0},
      );
    });

    testWidgets(
      'crux-dark paints the cursor colors it always has, and no band or '
      'marker line',
      (tester) async {
        await _pumpHarness(tester);
        final calls = _record(_overlayPaint);

        expect(
          _inColor(calls, #drawLine, const Color(0xFFFFEE58)),
          hasLength(1),
        );
        expect(
          _inColor(calls, #drawLine, const Color(0xFF29B6F6)).length,
          greaterThan(1),
        );
        // Transparent `cursor.delta` / `marker.line` make no canvas call at
        // all, so the default picture is the pre-token picture.
        expect(_drawn(calls, #drawRect), isEmpty);
        expect(
          _drawn(calls, #drawLine).where(
            (d) => {80.0, 320.0}.contains((d.args[0] as Offset).dx),
          ),
          isEmpty,
        );
      },
    );

    testWidgets('a theme change repaints the overlay', (tester) async {
      final container = await _pumpHarness(tester);
      container.read(cruxColorThemeProvider.notifier).applyOverrides({
        'canvas.cursor.primary': _primary,
      });
      expect(await _repaintRequested(tester, _overlayPaint), isTrue);
      expect(_inColor(_record(_overlayPaint), #drawLine, _primary), isNotEmpty);
    });

    testWidgets('a marker edit repaints only while marker lines are drawn', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      MarkerStateNotifier markers() =>
          container.read(markerStateProvider.notifier);

      markers().setMarker('c', 700);
      expect(
        await _repaintRequested(tester, _overlayPaint),
        isFalse,
        reason: 'lines are off',
      );

      await _edit(tester, container, {'canvas.marker.line': _markerLine});
      markers().setMarker('d', 800);
      expect(
        await _repaintRequested(tester, _overlayPaint),
        isTrue,
        reason: 'lines are on',
      );
      expect(
        _inColor(
          _record(_overlayPaint),
          #drawLine,
          _markerLine,
        ).map((d) => (d.args[0] as Offset).dx).toSet(),
        {80.0, 320.0, 560.0, 640.0},
      );
    });
  });

  group('TimeRulerWidget paints the canvas theme', () {
    testWidgets('ruler.background fills the ruler', (tester) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {
        'canvas.ruler.background': _rulerBackground,
      });

      final first = _drawn(_record(_rulerPaint), #drawRect).first;
      expect(first.paint.color.toARGB32(), _rulerBackground.toARGB32());
      expect(first.args[0], const Rect.fromLTWH(0, 0, _width, timeRulerHeight));
    });

    testWidgets('ruler.tick colors the minor ticks', (tester) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {'canvas.ruler.tick': _rulerTick});

      final ticks = _inColor(_record(_rulerPaint), #drawLine, _rulerTick);
      expect(ticks, isNotEmpty);
      // Minor ticks run from y=31 to the tick baseline at y=35.
      expect(ticks.every((d) => (d.args[0] as Offset).dy == 31), isTrue);
    });

    testWidgets('ruler.label colors the tick labels', (tester) async {
      final container = await _pumpHarness(tester);
      final before = await _renderedColors(
        tester,
        find.byType(TimeRulerWidget),
      );
      expect(before, isNot(contains(_rulerLabel.toARGB32())));

      await _edit(tester, container, {'canvas.ruler.label': _rulerLabel});
      expect(
        await _renderedColors(tester, find.byType(TimeRulerWidget)),
        contains(_rulerLabel.toARGB32()),
      );
    });

    testWidgets('ruler.cursorTime colors the delta-time readout', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {
        'canvas.ruler.cursorTime': _rulerCursorTime,
      });
      expect(
        await _renderedColors(tester, find.byType(TimeRulerWidget)),
        contains(_rulerCursorTime.toARGB32()),
      );
    });

    testWidgets('cursor.primary / cursor.secondary color the ruler triangles', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {
        'canvas.cursor.primary': _primary,
        'canvas.cursor.secondary': _secondary,
      });
      final calls = _record(_rulerPaint);

      final filled = _inColor(calls, #drawPath, _primary);
      expect(filled, hasLength(1));
      expect(filled.single.paint.style, PaintingStyle.fill);
      final outlined = _inColor(calls, #drawPath, _secondary);
      expect(outlined, hasLength(1));
      expect(outlined.single.paint.style, PaintingStyle.stroke);
      // The delta chip behind the readout is tinted with the secondary color.
      expect(
        _drawn(calls, #drawRRect).single.paint.color.toARGB32(),
        _secondary.withValues(alpha: 0.18).toARGB32(),
      );
    });

    testWidgets('marker.flag colors each named marker triangle', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {'canvas.marker.flag': _markerFlag});

      final flags = _inColor(_record(_rulerPaint), #drawPath, _markerFlag);
      expect(flags, hasLength(2));
      expect(flags.every((d) => d.paint.style == PaintingStyle.fill), isTrue);
    });

    testWidgets('marker.flagText colors each named marker letter', (
      tester,
    ) async {
      final container = await _pumpHarness(tester);
      await _edit(tester, container, {
        'canvas.marker.flagText': _markerFlagText,
      });
      expect(
        await _renderedColors(tester, find.byType(TimeRulerWidget)),
        contains(_markerFlagText.toARGB32()),
      );
    });

    testWidgets('a theme change repaints the ruler', (tester) async {
      final container = await _pumpHarness(tester);
      container.read(cruxColorThemeProvider.notifier).applyOverrides({
        'canvas.ruler.background': _rulerBackground,
      });
      expect(await _repaintRequested(tester, _rulerPaint), isTrue);
      expect(
        await _renderedColors(tester, find.byType(TimeRulerWidget)),
        contains(_rulerBackground.toARGB32()),
      );
    });

    // With a file loaded every rebuild computes fresh tick data, which alone
    // repaints the ruler. With none, the tick data is one shared constant, so
    // only the painter's color comparison can ask for the repaint.
    testWidgets('a theme change repaints an empty ruler', (tester) async {
      final container = await _pumpHarness(tester, loaded: false);
      container.read(cruxColorThemeProvider.notifier).applyOverrides({
        'canvas.ruler.background': _rulerBackground,
      });
      expect(await _repaintRequested(tester, _rulerPaint), isTrue);
      expect(
        await _renderedColors(tester, find.byType(TimeRulerWidget)),
        contains(_rulerBackground.toARGB32()),
      );
    });
  });

  // Pixel-for-pixel continuity. Before these tokens were wired, the ruler
  // filled with the Material theme's `colorScheme.surface` — which app.dart
  // derives from the preset's chrome tokens through `applyChromeTokens` — and
  // painted its ticks and labels from `WavecruxColorExtension`, and the
  // cursors and markers from one palette per brightness. Every built-in preset
  // must still paint exactly that.
  group('an unedited preset paints what it always painted', () {
    for (final presetId in builtinPresets().keys) {
      testWidgets(presetId, (tester) async {
        final preset = builtinPresets()[presetId]!;
        final light = preset.brightness == Brightness.light;
        final extension = light
            ? const WavecruxColorExtension.light()
            : const WavecruxColorExtension.dark();
        final chrome = CruxThemeExtension(theme: preset);
        final appTheme = applyChromeTokens(
          (light ? WavecruxTheme.light : WavecruxTheme.dark).copyWith(
            extensions: [extension, chrome],
          ),
          chrome,
        );
        final legacy = light
            ? (primary: 0xFFE65100, secondary: 0xFF0277BD, marker: 0xFFC2185B)
            : (primary: 0xFFFFEE58, secondary: 0xFF29B6F6, marker: 0xFFF48FB1);
        final minorTick = extension.timeRulerTick.toARGB32();
        final majorTick = extension.timeRulerMajorTick.toARGB32();

        await _pumpHarness(tester, preset: preset, materialTheme: appTheme);
        final ruler = _record(_rulerPaint);
        int colorOf(({List<dynamic> args, Paint paint}) d) =>
            d.paint.color.toARGB32();

        expect(
          colorOf(_drawn(ruler, #drawRect).first),
          appTheme.colorScheme.surface.toARGB32(),
        );
        final ticks = _drawn(
          ruler,
          #drawLine,
        ).where((d) => (d.args[1] as Offset).dy == 35);
        expect(
          ticks
              .where((d) => (d.args[0] as Offset).dy == 31)
              .map(colorOf)
              .toSet(),
          {minorTick},
        );
        expect(
          ticks
              .where((d) => (d.args[0] as Offset).dy == 26)
              .map(colorOf)
              .toSet(),
          {majorTick},
        );
        expect(_drawn(ruler, #drawPath).map(colorOf).toList(), [
          legacy.marker,
          legacy.marker,
          legacy.secondary,
          legacy.primary,
        ]);

        // Tick labels were painted in the major-tick color, the marker letters
        // in the marker color, and the delta readout in the secondary color.
        final rendered = await _renderedColors(
          tester,
          find.byType(TimeRulerWidget),
        );
        expect(
          rendered,
          containsAll(<int>[majorTick, legacy.marker, legacy.secondary]),
        );

        final overlay = _record(_overlayPaint);
        expect(
          _inColor(overlay, #drawLine, Color(legacy.primary)),
          hasLength(1),
        );
        expect(
          _inColor(overlay, #drawLine, Color(legacy.secondary)).length,
          greaterThan(1),
        );
        expect(_drawn(overlay, #drawRect), isEmpty);
      });
    }
  });
}
