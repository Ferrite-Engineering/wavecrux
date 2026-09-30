// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/canvas/scroll_back_refetch_test.dart
//
// Verifies that scrolling a signal off the top of the waveform canvas far
// enough to leave the viewport-gated retention window, then scrolling back,
// re-renders it correctly — no visible gap, no stale/blank value.
//
// PENDING.md ("Mobile / tablet / adaptive layout") lists this item as
// exercising `mobile_memory_guard_provider.dart`'s off-screen signal unload.
// That is not the mechanism that actually implements scroll-driven lazy
// load/unload: `MobileMemoryGuardNotifier` only unloads signals that are
// missing from the *signal group* entirely (added-to-panel membership), is
// gated off on `DeviceClass.desktop`, and never looks at the canvas's
// vertical scroll position. The real "unload off-screen data, re-fetch via
// `loadSignal` on scroll-back" behavior lives entirely inside
// `_WaveformCanvasState` (`waveform_canvas.dart`) via `SignalLoadPlanner`:
//
//   - `_visibleSignalRefs()` computes which signal refs intersect the
//     vertical scroll viewport, expanded by an overscan margin
//     (`_overscanPx`, at least 900 px).
//   - `_refresh()` loads (`WaveformDataSource.loadSignal`) any visible-but-
//     not-yet-loaded ref and rebuilds `_changesCache`/`_initialValueCache`
//     from scratch each time — so scrolled-away signals cease to be part of
//     the render's live cache, and scrolling back triggers a real re-fetch.
//   - `_evictBeyondBudget()` unloads (`WaveformDataSource.unloadSignal`) the
//     least-recently-visible signals once the loaded set exceeds
//     `SignalLoadPlanner.budgetFor` (>= 256, or 3x the current visible
//     count) — this is the actual "off-screen signal data is unloaded"
//     contract, decoupled from `MobileMemoryGuardNotifier` and active on
//     every device class, not just mobile.
//
// This test drives that real pipeline end-to-end: a real FFI-parsed
// waveform source, a real `WaveformCanvas` widget, and real drag gestures on
// its vertical `Scrollable` — not a provider-level mock.
//
// Fixture: 300 single-bit scalar signals (`sig0`..`sig299`) each holding a
// value equal to `index % 2`, so any signal's correctness is independently
// checkable from its own name — no dependency on wellen's variable-ordering
// behavior. 300 signals comfortably exceeds `SignalLoadPlanner`'s minimum
// retention budget of 256, so scrolling through the full list (in several
// discrete steps, so no chunk of the list is skipped over) genuinely
// evicts the topmost signal from the source once enough later signals have
// been loaded — a real eviction, not just a cache-level display gap.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';

import '../helpers/app_driver.dart';

/// Total scalar signals in the generated fixture. Must exceed
/// `SignalLoadPlanner`'s minimum retention budget (256) so a full top-to-
/// bottom scroll genuinely evicts the topmost signal rather than merely
/// culling it from the current paint.
const _signalCount = 300;

/// Encodes index [i] as a VCD identifier code using printable ASCII
/// 33..126 (94 symbols), base-94 — mirrors `tool/generate_scale_fixtures.dart`
/// so thousands of unique signals fit in short codes.
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
/// holding a constant value of `i % 2` (no transitions — only the initial
/// `$dumpvars` value matters for this test).
File _writeManySignalVcd(Directory dir) {
  final file = File('${dir.path}/many_signals.vcd');
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
    buf.writeln('${i % 2}${_idCode(i)}');
  }
  buf
    ..writeln(r'$end')
    ..writeln('#100');
  file.writeAsStringSync(buf.toString());
  return file;
}

/// Settles a scroll-driven refresh: a fixed real-time settle for the
/// debounce/throttle timers in `_WaveformCanvasState._onScroll` to fire and
/// schedule the post-frame refresh, then a bounded poll for the bulk-load
/// progress indicator (when the batch is large enough to surface one) to
/// return to idle. Never `pumpAndSettle(Duration)` — see the repo's
/// documented convention for why that hangs on background-isolate FFI work.
Future<void> _settleScroll(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await pumpUntil(
    tester,
    () => !activeTabContainer(tester).read(signalLoadProgressProvider).active,
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'scrolling the topmost signal out of the retention window and back '
    're-fetches it with no gap or stale value',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync(
        'wavecrux_scroll_refetch_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final vcd = _writeManySignalVcd(tempDir);

      await loadFixtureVcdAbsolute(tester, vcd.path);

      final tab = activeTabContainer(tester);
      final source = tab.read(waveformSourceProvider).value!;
      final allVars = source.findVariables(const SignalFilter());
      expect(allVars.length, _signalCount);

      tab.read(signalGroupsProvider.notifier).addSignals(allVars);
      await tester.pump();
      await tester.pumpAndSettle();
      await _settleScroll(tester);

      // Ground truth for "the right value" — derived from the signal's own
      // name (`sig<i>` -> expected bit `i % 2`), independent of whatever
      // order wellen/`findVariables` happened to return variables in.
      final expectedBitByRef = <String, String>{
        for (final v in allVars)
          v.signalRef: (int.parse(v.name.substring(3)) % 2).toString(),
      };

      // The canvas renders signal-group entries top-to-bottom, so the first
      // entry is the signal actually painted at the top of the lane list —
      // true regardless of `findVariables`' return order.
      final entries = tab.read(signalGroupsProvider).entries;
      expect(entries.length, _signalCount);
      final topRef = entries.first.signalRef!;
      final expectedTopValue = expectedBitByRef[topRef]!;

      // Sanity: the topmost signal is visible initially and loaded with the
      // correct value.
      expect(
        source.isSignalLoaded(topRef),
        isTrue,
        reason: 'topmost signal should load as part of the initial viewport',
      );
      expect(source.valueAt(topRef, 0), expectedTopValue);

      final canvasFinder = find.byType(WaveformCanvas);
      expect(canvasFinder, findsOneWidget);
      final scrollableFinder = find.descendant(
        of: canvasFinder,
        matching: find.byType(Scrollable),
      );
      expect(scrollableFinder, findsWidgets);
      final scrollState = tester.state<ScrollableState>(
        scrollableFinder.first,
      );
      final maxExtent = scrollState.position.maxScrollExtent;
      expect(
        maxExtent,
        greaterThan(0),
        reason:
            '$_signalCount signals at the default 30 dp lane height must '
            'overflow a 700 dp-tall window for this scroll to be meaningful',
      );

      // Real drag gestures, in several discrete steps so every signal in
      // between passes through the visible+overscan window at some point
      // (a single huge jump would only ever load the start and end windows,
      // never touching the middle of the list, and would never accumulate
      // enough *distinct* loaded signals to cross the retention budget).
      const steps = 10;
      final stepPx = maxExtent / steps;
      for (var i = 0; i < steps; i++) {
        await tester.drag(canvasFinder, Offset(0, -stepPx));
        await _settleScroll(tester);
      }
      expect(tester.takeException(), isNull);

      // Scrolled all the way to the bottom: the topmost signal is well
      // outside the visible+overscan window, and — because 300 signals
      // exceeds the retention budget — has genuinely been unloaded from the
      // source, not merely culled from the current paint.
      expect(
        source.isSignalLoaded(topRef),
        isFalse,
        reason:
            'topmost signal should have been evicted once the scroll '
            'traversal loaded > 256 other signals ahead of it',
      );

      // Scroll back to the top in the same discrete-step style.
      for (var i = 0; i < steps; i++) {
        await tester.drag(canvasFinder, Offset(0, stepPx));
        await _settleScroll(tester);
      }
      expect(tester.takeException(), isNull);

      // Back at the top: the signal must have been re-fetched via a real
      // `loadSignal` call (the on-demand scroll-back re-fetch under test)
      // and show the correct value again — no gap, no stale data.
      expect(
        scrollState.position.pixels,
        lessThan(stepPx),
        reason: 'should be back near the top of the scroll extent',
      );
      expect(
        source.isSignalLoaded(topRef),
        isTrue,
        reason: 'scrolling back into view must re-fetch the topmost signal',
      );
      expect(
        source.valueAt(topRef, 0),
        expectedTopValue,
        reason:
            're-fetched data must match the original value, not stale '
            'or garbage data from a different signal',
      );
    },
  );
}
