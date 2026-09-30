// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_canvas_render_object.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Result of a render-paint benchmark run.
@immutable
class RenderBenchmarkResult {
  const RenderBenchmarkResult({
    required this.signalCount,
    required this.frames,
    required this.frameTimesUs,
    required this.avgUs,
    required this.p95Us,
    required this.p99Us,
    required this.minUs,
    required this.maxUs,
  });

  /// Number of lanes that were painted per frame.
  final int signalCount;

  /// Total number of paint frames measured.
  final int frames;

  /// Per-frame paint duration in microseconds, in measurement order. Includes
  /// the warmup frames that were excluded from the percentile statistics.
  final List<int> frameTimesUs;

  /// Mean paint time in microseconds across measured (non-warmup) frames.
  final double avgUs;

  /// 95th percentile paint time in microseconds.
  final int p95Us;

  /// 99th percentile paint time in microseconds.
  final int p99Us;

  /// Fastest measured paint frame in microseconds.
  final int minUs;

  /// Slowest measured paint frame in microseconds.
  final int maxUs;

  /// Approximate FPS based on the average paint time.
  ///
  /// Caveat: this counts only the cost of paint(); compositing, layout, and
  /// other pipeline stages are not measured. Treat as an upper bound on the
  /// real frame rate.
  double get avgFps => avgUs <= 0 ? double.infinity : 1e6 / avgUs;

  /// Whether the average paint time fits within a 16.67 ms (60 fps) budget.
  bool get meets60Fps => avgUs <= 16667;

  String summary() {
    final fps = avgFps.isFinite ? avgFps.toStringAsFixed(1) : '∞';
    return 'lanes=$signalCount frames=$frames '
        'avg=${(avgUs / 1000).toStringAsFixed(2)}ms '
        'p95=${(p95Us / 1000).toStringAsFixed(2)}ms '
        'p99=${(p99Us / 1000).toStringAsFixed(2)}ms '
        'min=${(minUs / 1000).toStringAsFixed(2)}ms '
        'max=${(maxUs / 1000).toStringAsFixed(2)}ms '
        'fps≈$fps';
  }
}

/// Builds [WaveformLaneData] fixtures and times [WaveformCanvasRenderObject]
/// paint passes for performance regression detection.
///
/// The benchmark generates a deterministic mix of scalar (1-bit), bus (8-bit
/// hex), and analog (real) lanes with a configurable signal count and number
/// of value transitions per signal. It then drives the render object's
/// [paint] method directly against an in-memory [PictureRecorder] canvas,
/// simulating a horizontal scroll by panning the [TimeMapper] between frames
/// so that segment-build paths re-execute (matches the real cursor-move /
/// zoom workload, which is the hot path users hit in practice).
///
/// A test harness, not app code: the runnable
/// `test/benchmarks/waveform_paint_benchmark.dart` and the render-object scale
/// and harness tests are its only callers, so it lives beside them rather than
/// in `lib/`, where every file is expected to be loaded by the app.
class RenderBenchmarkService {
  const RenderBenchmarkService();

  /// Builds [signalCount] lanes for the benchmark. Distribution: ~50% scalar,
  /// ~40% bus (mix of 4/8/16/32-bit), ~10% analog.
  ///
  /// Each signal gets [transitionsPerSignal] transitions evenly distributed
  /// across [0, simulationDuration].
  List<WaveformLaneData> buildLanes({
    required int signalCount,
    int transitionsPerSignal = 50,
    int simulationDuration = 100000,
    double laneHeight = 24,
    int seed = 42,
  }) {
    final random = math.Random(seed);
    final lanes = <WaveformLaneData>[];
    var y = 0.0;

    const scalarColor = Color(0xFF4CAF50);
    const busColor = Color(0xFF42A5F5);
    const analogColor = Color(0xFFFFA726);

    for (var i = 0; i < signalCount; i++) {
      final roll = random.nextDouble();
      final List<SignalChange> changes;
      final bool isScalar;
      final bool isAnalog;
      final int bitWidth;
      final Color color;

      if (roll < 0.10) {
        // Analog signal.
        isScalar = false;
        isAnalog = true;
        bitWidth = 0;
        color = analogColor;
        changes = _buildAnalogChanges(
          random,
          transitionsPerSignal,
          simulationDuration,
        );
      } else if (roll < 0.50) {
        // Scalar signal.
        isScalar = true;
        isAnalog = false;
        bitWidth = 1;
        color = scalarColor;
        changes = _buildScalarChanges(
          random,
          transitionsPerSignal,
          simulationDuration,
        );
      } else {
        // Bus signal.
        const widths = [4, 8, 16, 32];
        isScalar = false;
        isAnalog = false;
        bitWidth = widths[random.nextInt(widths.length)];
        color = busColor;
        changes = _buildBusChanges(
          random,
          transitionsPerSignal,
          simulationDuration,
          bitWidth,
        );
      }

      lanes.add(
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: y,
          height: laneHeight,
          signalRef: 'sig$i',
          displayName: 'sig$i',
          signalColor: color,
          isScalar: isScalar,
          isAnalog: isAnalog,
          bitWidth: bitWidth,
          changes: changes,
          valueAtStart: changes.isNotEmpty ? changes.first.value : null,
        ),
      );
      y += laneHeight;
    }

    return lanes;
  }

  /// Runs [framesPerRun] paint passes and returns aggregated timings.
  ///
  /// [warmupFrames] are run first and discarded — JIT warmup, paint cache
  /// priming, and first-frame allocation noise are ignored. Set to 0 to
  /// include every frame in the percentile statistics.
  ///
  /// [viewportTop] / [viewportBottom] enable the render object's lane-culling
  /// optimization. Pass null to paint every lane (matches the legacy
  /// non-culled behavior).
  RenderBenchmarkResult run({
    required List<WaveformLaneData> lanes,
    int framesPerRun = 30,
    int warmupFrames = 5,
    double canvasWidth = 1920,
    double canvasHeight = 800,
    int simulationStart = 0,
    int simulationEnd = 100000,
    double? viewportTop,
    double? viewportBottom,
  }) {
    final mapper = TimeMapper(
      startTime: simulationStart,
      endTime: simulationEnd,
      viewportWidth: canvasWidth,
      ticksPerPixel: (simulationEnd - simulationStart) / canvasWidth,
      panOffsetTicks: simulationStart.toDouble(),
    );

    final ro =
        WaveformCanvasRenderObject(
            lanes: lanes,
            timeMapper: mapper,
            cursorState: const CursorState(),
            // Benchmarks always paint against the default dark preset so
            // results are comparable regardless of the user's active theme.
            colorTheme: defaultBuiltinPreset(),
            valueTextStyle: const TextStyle(fontSize: 11),
            groupLabelStyle: const TextStyle(fontSize: 11),
          )
          ..viewportTop = viewportTop
          ..viewportBottom = viewportBottom
          // Lay the render object out at the requested canvas size so paint()
          // operates on realistic bounds.
          ..layout(
            BoxConstraints.tightFor(width: canvasWidth, height: canvasHeight),
          );

    final totalFrames = warmupFrames + framesPerRun;
    final frameTimesUs = <int>[];
    final stopwatch = Stopwatch();
    final panStep =
        (simulationEnd - simulationStart) ~/ math.max(1, totalFrames * 4);

    for (var i = 0; i < totalFrames; i++) {
      // Mutate the time mapper between frames so the painters re-execute the
      // segment-build path — the real-world hot path for cursor scrubbing.
      ro.timeMapper = mapper.panByTime(panStep * i);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final context = _BenchmarkPaintingContext(canvas);

      stopwatch
        ..reset()
        ..start();
      ro.paint(context, Offset.zero);
      stopwatch.stop();
      frameTimesUs.add(stopwatch.elapsedMicroseconds);

      // Discard the picture immediately to release GPU resources.
      recorder.endRecording().dispose();
    }

    final measured = frameTimesUs.sublist(warmupFrames);
    final sorted = List<int>.of(measured)..sort();
    final n = sorted.length;
    final avg = n == 0 ? 0.0 : measured.reduce((a, b) => a + b) / n;
    final p95 = n == 0 ? 0 : sorted[math.min(n - 1, (n * 0.95).floor())];
    final p99 = n == 0 ? 0 : sorted[math.min(n - 1, (n * 0.99).floor())];
    final minVal = n == 0 ? 0 : sorted.first;
    final maxVal = n == 0 ? 0 : sorted.last;

    return RenderBenchmarkResult(
      signalCount: lanes.length,
      frames: n,
      frameTimesUs: List.unmodifiable(frameTimesUs),
      avgUs: avg,
      p95Us: p95,
      p99Us: p99,
      minUs: minVal,
      maxUs: maxVal,
    );
  }

  // ── synthetic change generators ────────────────────────────────────────────

  static List<SignalChange> _buildScalarChanges(
    math.Random r,
    int count,
    int duration,
  ) {
    if (count <= 0) return const [];
    final step = duration / count;
    final out = <SignalChange>[];
    var bit = 0;
    for (var i = 0; i < count; i++) {
      bit ^= 1;
      out.add(SignalChange(time: (i * step).round(), value: bit.toString()));
    }
    return out;
  }

  static List<SignalChange> _buildBusChanges(
    math.Random r,
    int count,
    int duration,
    int bitWidth,
  ) {
    if (count <= 0) return const [];
    final step = duration / count;
    final out = <SignalChange>[];
    final maxValue = bitWidth >= 32 ? 0xFFFFFFFF : (1 << bitWidth) - 1;
    for (var i = 0; i < count; i++) {
      final v = r.nextInt(maxValue);
      final bits = v.toRadixString(2).padLeft(bitWidth, '0');
      out.add(SignalChange(time: (i * step).round(), value: 'b$bits'));
    }
    return out;
  }

  static List<SignalChange> _buildAnalogChanges(
    math.Random r,
    int count,
    int duration,
  ) {
    if (count <= 0) return const [];
    final step = duration / count;
    final out = <SignalChange>[];
    for (var i = 0; i < count; i++) {
      final v = math.sin(i * 0.3) * 100 + r.nextDouble() * 10;
      out.add(SignalChange(time: (i * step).round(), value: v.toString()));
    }
    return out;
  }
}

/// Minimal [PaintingContext] subclass that exposes a caller-supplied [Canvas]
/// without going through the layer infrastructure. Used by the benchmark to
/// drive [WaveformCanvasRenderObject.paint] in a unit-test context where a
/// full Flutter render tree is unavailable.
class _BenchmarkPaintingContext implements PaintingContext {
  _BenchmarkPaintingContext(this._canvas);

  final Canvas _canvas;

  @override
  Canvas get canvas => _canvas;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
