// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/canvas/scroll_memory_soak_test.dart
//
// Long-running "5-minute scroll session: memory stable, not growing without
// bound" verification item (VERIFICATION_GUIDE Performance section). Drives a
// sustained scroll + zoom + pan session against a large waveform and asserts
// memory stays bounded across the whole session — no unbounded growth.
//
// ── Why this test exists / what would break without it ──────────────────────
// The waveform canvas lazily loads signal data for the visible+overscan window
// and evicts least-recently-visible signals once the loaded set exceeds a
// retention budget (`SignalLoadPlanner.budgetFor`, >= 256), and it rebuilds its
// per-signal `_changesCache`/`_initialValueCache` on every scroll/zoom/pan
// refresh. A regression that (a) stopped evicting, (b) leaked cache entries for
// scrolled-away/evicted signals, or (c) accumulated isolate/query buffers would
// not fail any single-shot test — it only manifests as steady growth under a
// long interactive session. That is exactly what this soak reproduces.
//
// ── Assertion strategy: one deterministic bound + one tolerant canary ────────
// Two complementary assertions, deliberately different in kind:
//
//  1. PRIMARY, DETERMINISTIC — loaded-signal count stays bounded. Sampled at
//     the same (top) scroll position at the end of every soak iteration, the
//     number of signals the source reports as loaded must never exceed the
//     eviction ceiling, and must not drift upward across iterations. This is a
//     tight, non-flaky, app-logic-level proof that the dominant memory
//     consumer (decompressed signal data + its canvas caches) cannot grow
//     without bound no matter how long the user scrolls. The fixture has FAR
//     more signals (`_signalCount`) than the budget, so a broken evictor would
//     let the loaded set climb toward `_signalCount` and trip this immediately.
//
//  2. SECONDARY, TOLERANT — process RSS growth canary. RSS is intentionally
//     checked only as a loose leak *canary*, never as a tight budget, because
//     it is genuinely noisy: the Dart heap grows to a plateau, GC is
//     non-deterministic (there is no forceGC seam in an integration test), and
//     absolute values swing with CI hardware. So this compares the MEDIAN RSS
//     of the last few samples against the MEDIAN of the first few
//     post-warmup samples and allows growth up to `max(baseline, _rssHeadroom)`
//     — i.e. a doubling, OR a fixed multi-hundred-MB headroom, whichever is
//     larger. A real unbounded leak over hundreds of refresh cycles is
//     multiples of baseline (GBs) and blows past this easily; ordinary
//     heap-plateau + fragmentation noise stays comfortably under it. Using the
//     median (not a single sample) further de-noises it. If RSS is unavailable
//     (reported 0 — e.g. a platform without `ProcessInfo`), the canary is
//     skipped rather than asserted vacuously; the deterministic bound still
//     runs.
//
// ── The "5 minutes", compressed ─────────────────────────────────────────────
// A literal five real minutes of wall-clock is impractical for CI. Instead the
// session runs `_soakIterations` full scroll-down→up + zoom-in/out + pan
// cycles; each cycle drives dozens of real drag gestures and provider-driven
// zoom/pan operations, so the load/evict/cache-rebuild code paths under test
// execute several hundred times over — the same repetition a five-minute human
// session would produce, which is what actually surfaces accumulation. Tune
// `_soakIterations` up for a heavier local soak; the default keeps the
// individual-file runtime in the low minutes (this file is run on its own per
// the repo's macOS relaunch-race convention, not as part of a directory sweep).
//
// Never `pumpAndSettle(Duration)` — see the repo's documented convention for
// why that hangs on background-isolate FFI work.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/services/diagnostics/memory_stats_service.dart';

import '../helpers/app_driver.dart';

/// Total scalar signals in the generated fixture. Chosen to dwarf the canvas
/// retention budget (`SignalLoadPlanner.budgetFor`, minimum 256) so eviction
/// genuinely runs on every downward scroll and a broken evictor would let the
/// loaded set climb far past the budget toward this number.
const _signalCount = 800;

/// Simulation end time (ns). Signals toggle throughout this range so that
/// zoom/pan genuinely change what `changesInRange` returns and exercise the
/// canvas's horizontal cache rebuild, not just the vertical load/evict path.
const _endTime = 800;

/// Number of full scroll-down→up + zoom + pan cycles. See the "compressed"
/// note in the header. The load/evict/refresh paths run many times per cycle.
const _soakIterations = 16;

/// Discrete scroll steps per direction per iteration. Several steps (not one
/// big jump) so every signal passes through the visible+overscan window and
/// the loaded set actually churns, matching `scroll_back_refetch_test.dart`.
const _scrollSteps = 6;

/// RSS growth headroom for the tolerant canary (see header). Growth up to
/// `max(baselineRss, _rssHeadroom)` is allowed; a real unbounded leak exceeds
/// this by multiples.
const int _rssHeadroom = 400 * 1024 * 1024; // 400 MB

/// Encodes index [i] as a base-94 VCD identifier over printable ASCII 33..126
/// (mirrors `tool/generate_scale_fixtures.dart` / the refetch fixture).
String _idCode(int i) {
  final buf = StringBuffer();
  var v = i;
  do {
    buf.writeCharCode(33 + (v % 94));
    v ~/= 94;
  } while (v > 0);
  return buf.toString();
}

/// Writes a VCD with [_signalCount] single-bit scalars named `sig<i>`, each
/// toggling on its own period across `[0, _endTime]` so the trace has real
/// transitions for the horizontal (zoom/pan) recompute path to chew on. The
/// initial `$dumpvars` value of `sig<i>` is `i % 2`; the signal then toggles
/// every `4 + (i % 12)` ticks, so each signal's value at any time is derivable
/// from its own name/period — no dependence on wellen's variable ordering.
File _writeSoakVcd(Directory dir) {
  final file = File('${dir.path}/soak_signals.vcd');
  final periods = <int>[for (var i = 0; i < _signalCount; i++) 4 + (i % 12)];
  final value = <int>[for (var i = 0; i < _signalCount; i++) i % 2];

  final buf = StringBuffer()
    ..writeln(r'$timescale 1 ns $end')
    ..writeln(r'$scope module top $end');
  for (var i = 0; i < _signalCount; i++) {
    buf.writeln('\$var wire 1 ${_idCode(i)} sig$i \$end');
  }
  buf
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end')
    ..writeln(r'$dumpvars');
  for (var i = 0; i < _signalCount; i++) {
    buf.writeln('${value[i]}${_idCode(i)}');
  }
  buf.writeln(r'$end');

  // Emit time-ordered change blocks: at each tick, toggle every signal whose
  // period divides the tick. VCD requires changes grouped under an ascending
  // `#time` header, which this loop naturally produces.
  for (var t = 1; t <= _endTime; t++) {
    final toggles = <int>[];
    for (var i = 0; i < _signalCount; i++) {
      if (t % periods[i] == 0) toggles.add(i);
    }
    if (toggles.isEmpty) continue;
    buf.writeln('#$t');
    for (final i in toggles) {
      value[i] ^= 1;
      buf.writeln('${value[i]}${_idCode(i)}');
    }
  }
  file.writeAsStringSync(buf.toString());
  return file;
}

/// Settles a scroll/zoom/pan-driven refresh: a fixed real-time settle for the
/// canvas debounce/throttle to schedule its post-frame refresh, then a bounded
/// poll for the bulk-load progress indicator to return to idle. Identical
/// rationale to `scroll_back_refetch_test.dart`'s `_settleScroll`.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await pumpUntil(
    tester,
    () => !activeTabContainer(tester).read(signalLoadProgressProvider).active,
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// Median of [values] (sorted-copy midpoint; average of the two middles for
/// even length). [values] must be non-empty.
double _median(List<int> values) {
  final sorted = [...values]..sort();
  final n = sorted.length;
  final mid = n ~/ 2;
  return n.isOdd ? sorted[mid].toDouble() : (sorted[mid - 1] + sorted[mid]) / 2;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'a sustained scroll + zoom + pan session keeps memory bounded '
    '(loaded-signal count capped, no unbounded RSS growth)',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync(
        'wavecrux_scroll_soak_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final vcd = _writeSoakVcd(tempDir);

      await loadFixtureVcdAbsolute(tester, vcd.path);

      final tab = activeTabContainer(tester);
      final source = tab.read(waveformSourceProvider).value!;
      final allVars = source.findVariables(const SignalFilter());
      expect(allVars.length, _signalCount);

      tab.read(signalGroupsProvider.notifier).addSignals(allVars);
      await tester.pump();
      await tester.pumpAndSettle();
      await _settle(tester);

      final canvasFinder = find.byType(WaveformCanvas);
      expect(canvasFinder, findsOneWidget);
      final scrollableFinder = find.descendant(
        of: canvasFinder,
        matching: find.byType(Scrollable),
      );
      expect(scrollableFinder, findsWidgets);
      final scrollState = tester.state<ScrollableState>(scrollableFinder.first);
      final maxExtent = scrollState.position.maxScrollExtent;
      expect(
        maxExtent,
        greaterThan(0),
        reason:
            '$_signalCount signals must overflow the 700 dp window for the '
            'scroll session to be meaningful',
      );

      final timeMapper = tab.read(timeMapperProvider.notifier);
      const memStats = MemoryStatsService();

      // Warm-up cycle: one full scroll + zoom pass so first-touch allocations
      // (isolate spin-up, JIT, initial caches) happen BEFORE the baseline
      // sample — otherwise baseline would be artificially low and every later
      // sample would look like "growth".
      final stepPx = maxExtent / _scrollSteps;
      for (var i = 0; i < _scrollSteps; i++) {
        await tester.drag(canvasFinder, Offset(0, -stepPx));
        await _settle(tester);
      }
      for (var i = 0; i < _scrollSteps; i++) {
        await tester.drag(canvasFinder, Offset(0, stepPx));
        await _settle(tester);
      }
      timeMapper.zoomIn(focalPixel: 400);
      await _settle(tester);
      timeMapper.fitAll();
      await _settle(tester);
      expect(tester.takeException(), isNull);

      // Establish the deterministic ceiling from the actual post-warmup loaded
      // set at rest at the top. `budgetFor` caps the loaded set; we allow a
      // generous 1.5x margin over the observed warm figure for transient
      // in-flight/overscan variance, and separately assert this ceiling is
      // itself comfortably below the total signal count (proving it's a real
      // bound, not a vacuous one that a broken evictor would also satisfy).
      final warmLoaded = memStats.collect(source: source).loadedSignalCount;
      expect(
        warmLoaded,
        greaterThan(0),
        reason: 'the top viewport must have some signals loaded',
      );
      final loadedCeiling = (warmLoaded * 1.5).ceil();
      expect(
        loadedCeiling,
        lessThan(_signalCount ~/ 2),
        reason:
            'the eviction ceiling ($loadedCeiling) must be far below the '
            '$_signalCount total signals for this bound to be meaningful — '
            'otherwise a non-evicting canvas would also pass',
      );

      final rssSamples = <int>[];
      final loadedSamples = <int>[];

      // ── The soak ──────────────────────────────────────────────────────────
      for (var iter = 0; iter < _soakIterations; iter++) {
        // Scroll all the way down…
        for (var s = 0; s < _scrollSteps; s++) {
          await tester.drag(canvasFinder, Offset(0, -stepPx));
          await _settle(tester);
        }
        // …zoom in twice and pan back and forth at the bottom (exercises the
        // horizontal changesInRange recompute over shifting windows)…
        timeMapper.zoomIn(focalPixel: 300);
        await _settle(tester);
        timeMapper.zoomIn(focalPixel: 600);
        await _settle(tester);
        timeMapper.pan(250);
        await _settle(tester);
        timeMapper.pan(-500);
        await _settle(tester);
        timeMapper.fitAll();
        await _settle(tester);
        // …then scroll all the way back up to the sampling position.
        for (var s = 0; s < _scrollSteps; s++) {
          await tester.drag(canvasFinder, Offset(0, stepPx));
          await _settle(tester);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'no exception may occur during soak iteration $iter',
        );

        // Sample at rest at the top. A couple of extra pumps give the VM's
        // scavenger a chance to run before we read RSS (a major GC can't be
        // forced from here — which is exactly why the RSS check is a loose
        // canary, not a tight budget).
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        final stats = memStats.collect(source: source);
        loadedSamples.add(stats.loadedSignalCount);
        rssSamples.add(stats.dartProcessRssBytes);

        // DETERMINISTIC bound, checked every iteration: the loaded set can
        // never exceed the eviction ceiling, no matter how long we scroll.
        expect(
          stats.loadedSignalCount,
          lessThanOrEqualTo(loadedCeiling),
          reason:
              'loaded-signal count (${stats.loadedSignalCount}) exceeded the '
              'eviction ceiling ($loadedCeiling) at iteration $iter — the '
              'retention budget is not holding under sustained scrolling',
        );
      }

      // No upward drift in the loaded set across the session: the last sample
      // must not materially exceed the first (same scroll position → same
      // visible set → same loaded set, within eviction jitter).
      expect(
        loadedSamples.last,
        lessThanOrEqualTo((loadedSamples.first * 1.25).ceil()),
        reason:
            'loaded-signal count drifted upward across the soak '
            '(${loadedSamples.first} → ${loadedSamples.last}) — a sign the '
            'evictor is falling behind sustained use',
      );

      // ── Tolerant RSS canary ────────────────────────────────────────────────
      // Only meaningful where RSS is actually observable (> 0). Compare the
      // median of the first few samples to the median of the last few.
      const window = 4;
      if (rssSamples.first > 0 && rssSamples.length >= window * 2) {
        final baseline = _median(rssSamples.sublist(0, window));
        final tail = _median(rssSamples.sublist(rssSamples.length - window));
        final allowedGrowth = baseline > _rssHeadroom
            ? baseline
            : _rssHeadroom.toDouble();
        expect(
          tail - baseline,
          lessThanOrEqualTo(allowedGrowth),
          reason:
              'process RSS grew from a baseline median of '
              '${(baseline / 1024 / 1024).toStringAsFixed(1)} MB to a tail '
              'median of ${(tail / 1024 / 1024).toStringAsFixed(1)} MB across '
              '$_soakIterations scroll/zoom/pan cycles — beyond the '
              '${(allowedGrowth / 1024 / 1024).toStringAsFixed(0)} MB leak '
              'canary. A stable session plateaus; this looks like unbounded '
              'growth.',
        );
      }

      expect(tester.takeException(), isNull);
    },
    // Long-running soak — well beyond the default per-test budget on slower
    // headless CI. The bounded `pumpUntil` polls return the instant work
    // settles, so the real time is dominated by the fixed inter-step settles,
    // not this ceiling.
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
