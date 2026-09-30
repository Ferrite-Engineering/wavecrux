// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Rendering golden tests (ARCHITECTURE.md §8.9 Layer 5).
//
// Renders the waveform canvas for the three hand-crafted fixture VCDs at a
// fixed (fit-all) zoom and a fixed cursor position, then compares the
// rasterised output against committed baseline PNGs. This is the only layer
// that catches *rendering* regressions value-level tests cannot see: wrong
// color for x-values, a dropped transition edge, broken bus-parallelogram
// geometry, analog-trace interpolation, and theme-token drift (the canvas,
// lane and x/z tokens of the `oscilloscope` preset). Traces and bus value
// labels take each signal's own color. The cursor line and the time ruler are
// separate layers this render object does not paint; their token colors are
// asserted in `canvas_theme_tokens_paint_test.dart`.
//
//   flutter test --update-goldens \
//     test/features/viewer/rendering/waveform_canvas_golden_test.dart
//
// regenerates the baselines against the live painters + real parser.
//
// Golden PNGs are platform-sensitive: font hinting and shape anti-aliasing
// differ per OS, so a baseline rendered on one platform will not byte-match
// another. The comparison therefore runs only on **macOS** — the canonical
// baseline platform for this repo — and skips on Linux/Windows; CI's macOS
// `test` job is the one that exercises these goldens. The fixtures parse
// through the real FFI parser, so on macOS the suite also needs the wellen
// native library: it skips locally when the library is not built and fails in
// CI, which builds it first.

import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_canvas_render_object.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../../helpers/wellen_ffi_library_gate.dart';

/// Fixed viewport width so the fit-all [TimeMapper] is deterministic.
const double _viewportWidth = 800;

/// Lane heights — fixed per row kind so the canvas extent is reproducible
/// regardless of [MobileMetrics]/device-class plumbing (which this leaf-level
/// test deliberately does not exercise).
const double _digitalLaneHeight = 32;
const double _analogLaneHeight = 64;

/// A small fixed palette so stacked traces are visually distinguishable in the
/// baseline without depending on the auto-palette provider. Deterministic.
const List<Color> _palette = <Color>[
  Color(0xFF4CAF50), // green
  Color(0xFF42A5F5), // blue
  Color(0xFFFFCA28), // amber
  Color(0xFFEF5350), // red
  Color(0xFFAB47BC), // purple
  Color(0xFF26C6DA), // cyan
];

/// Goldens compare only on the canonical baseline platform (macOS). Everywhere
/// else the comparison is skipped.
final bool _goldensEnabled = Platform.isMacOS;

void main() {
  // The waveform-canvas token values live in WaveCrux's
  // `PresetTokenOverlay`, not in crux_theme's shared presets, so
  // `builtinPresets()` only carries them once the product has registered.
  // Without this the goldens paint fallback colors — which is precisely what
  // these baselines exist to catch.
  setUpAll(registerWaveCruxThemeTokens);

  if (_goldensEnabled && !requireWellenFfiLibrary('waveform canvas goldens')) {
    return;
  }

  group('WaveformCanvas rendering goldens — §8.9 Layer 5', () {
    // (a) scalar signals + an 8-bit bus, default dark theme.
    testWidgets('scalar_basics renders on the dark theme', (tester) async {
      await _expectGolden(
        tester,
        fixture: 'scalar_basics.vcd',
        theme: defaultBuiltinPreset(),
        golden: 'goldens/scalar_basics_dark.png',
      );
    }, skip: !_goldensEnabled);

    // (b) multi-bit vector/bus parallelograms incl. x/z value periods,
    // default dark theme.
    testWidgets('vector_formats renders on the dark theme', (tester) async {
      await _expectGolden(
        tester,
        fixture: 'vector_formats.vcd',
        theme: defaultBuiltinPreset(),
        golden: 'goldens/vector_formats_dark.png',
      );
    }, skip: !_goldensEnabled);

    // (c) analog/real interpolated traces with an inline cursor sample,
    // default dark theme.
    testWidgets('analog_real renders on the dark theme', (tester) async {
      await _expectGolden(
        tester,
        fixture: 'analog_real.vcd',
        theme: defaultBuiltinPreset(),
        cursorAtMidpoint: true,
        golden: 'goldens/analog_real_dark.png',
      );
    }, skip: !_goldensEnabled);

    // (d) oscilloscope preset — canvas background and x/z colors. The vector
    // fixture carries xnib/znib/mixed_xz so the x-state fill/hatch and the
    // z-state line are exercised against the preset's tokens.
    testWidgets('vector_formats renders on the oscilloscope preset', (
      tester,
    ) async {
      await _expectGolden(
        tester,
        fixture: 'vector_formats.vcd',
        theme: builtinPresets()['oscilloscope']!,
        golden: 'goldens/vector_formats_oscilloscope.png',
      );
    }, skip: !_goldensEnabled);

    // (d) oscilloscope preset — analog traces with the inline value dot +
    // label AnalogSignalPainter draws at the primary cursor, on the preset's
    // canvas background. The dot and label take the signal's color; the
    // cursor line itself belongs to the cursor layer, not this render
    // object.
    testWidgets('analog_real renders on the oscilloscope preset', (
      tester,
    ) async {
      await _expectGolden(
        tester,
        fixture: 'analog_real.vcd',
        theme: builtinPresets()['oscilloscope']!,
        cursorAtMidpoint: true,
        golden: 'goldens/analog_real_oscilloscope.png',
      );
    }, skip: !_goldensEnabled);
  });
}

/// Loads [fixture] through the real wellen parser, builds canvas lanes exactly
/// as [WaveformCanvas] does, renders at a fit-all zoom, and compares against
/// the committed [golden] baseline.
Future<void> _expectGolden(
  WidgetTester tester, {
  required String fixture,
  required CruxColorTheme theme,
  required String golden,
  bool cursorAtMidpoint = false,
}) async {
  // The wellen parser runs on a background isolate. Isolate message-passing
  // only completes on the *real* event loop, so the parse / loadSignal /
  // query work must run inside `tester.runAsync` — the fake-async clock that
  // `testWidgets` installs otherwise never pumps the isolate's futures and the
  // awaits hang. `changesInRange` returns materialised `List<SignalChange>`s,
  // so once the lanes are built the provider can be closed and the pump +
  // golden comparison proceed on the fake-async clock as usual.
  late final List<WaveformLaneData> lanes;
  late final TimeMapper mapper;
  late final CursorState cursor;
  await tester.runAsync(() async {
    final provider = WellenProvider();
    await provider.openFile('test/fixtures/vcd/$fixture');
    try {
      lanes = await _buildLanes(provider);
      mapper = TimeMapper.fitAll(
        startTime: provider.startTime,
        endTime: provider.endTime,
        viewportWidth: _viewportWidth,
      );
      cursor = cursorAtMidpoint
          ? CursorState(
              primaryCursorTime: (provider.startTime + provider.endTime) ~/ 2,
            )
          : const CursorState();
    } finally {
      provider.close();
    }
  });

  final totalHeight = lanes.fold<double>(0, (h, l) => h + l.height);

  // 1:1 device-pixel ratio keeps the PNG dimensions equal to the logical
  // canvas size and identical across machines with different default DPRs.
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(Size(_viewportWidth, totalHeight));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SizedBox(
          width: _viewportWidth,
          height: totalHeight,
          child: WaveformCanvasView(
            lanes: lanes,
            timeMapper: mapper,
            cursorState: cursor,
            colorTheme: theme,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byType(WaveformCanvasView),
    matchesGoldenFile(golden),
  );
}

/// Builds one signal lane per variable in the trace, stacked top-to-bottom,
/// deriving `isScalar` / `isAnalog` / `bitWidth` / `changes` the same way
/// [WaveformCanvas] does in `_buildLaneData`. Variables are sorted by full path
/// so the lane order is deterministic across parser runs.
Future<List<WaveformLaneData>> _buildLanes(WellenProvider provider) async {
  final variables = [...provider.findVariables(const SignalFilter())]
    ..sort((a, b) => a.fullPath.compareTo(b.fullPath));
  final visibleStart = provider.startTime;
  final visibleEnd = provider.endTime;

  final lanes = <WaveformLaneData>[];
  var y = 0.0;
  for (var i = 0; i < variables.length; i++) {
    final v = variables[i];
    await provider.loadSignal(v.signalRef);

    final bitWidth = v.bitWidth ?? 1;
    final isAnalog = v.isReal;
    final isScalar = bitWidth == 1 && !isAnalog;
    final height = isAnalog ? _analogLaneHeight : _digitalLaneHeight;

    lanes.add(
      WaveformLaneData(
        kind: WaveformLaneKind.signal,
        y: y,
        height: height,
        signalRef: v.signalRef,
        displayName: v.name,
        signalColor: _palette[i % _palette.length],
        isScalar: isScalar,
        isAnalog: isAnalog,
        bitWidth: bitWidth,
        // Extend end by 1 tick so a transition exactly at endTime is included
        // (mirrors WaveformCanvas._refresh).
        changes: provider.changesInRange(
          v.signalRef,
          visibleStart,
          visibleEnd + 1,
        ),
        valueAtStart: provider.valueAt(v.signalRef, visibleStart),
      ),
    );
    y += height;
  }
  return lanes;
}
