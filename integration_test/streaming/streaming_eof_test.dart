// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/streaming/streaming_eof_test.dart
//
// Producer EOF handling during streaming VCD.
//
// Verifies the "unexpected EOF" path: a producer writes a header and a
// partial value-change block, then closes its end of the byte stream.
// Expected behavior:
//   (a) WaveCrux does not crash or surface an unhandled framework exception.
//   (b) All transitions received before EOF are still visible / queryable.
//   (c) The app surfaces an end-of-stream indicator (the LIVE badge clears
//       and the streaming state returns to Idle — matching the behavior
//       documented in [StreamingSourceNotifier]: "auto-transitions back to
//       StreamingViewerIdle when the underlying stream reaches EOF so the
//       user can browse the final waveform").

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../helpers/app_driver.dart';

// Header + a couple of value-change blocks. The producer closes the stream
// after this content arrives — there is no `#end` directive or final
// transition, simulating a process that died or was killed mid-stream.
const _partialVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 8 # data $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
b00000000 #
$end
#10
1!
#20
0!
b00000001 #
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'producer EOF mid-stream: partial data preserved, '
    'state returns to idle, no crash',
    (tester) async {
      // Bring up the viewer so the toolbar (LIVE badge) is wired.
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      // The active tab's container, not the toolbar's. In the PaneHost layout
      // the toolbar sits outside every tab scope, so resolving through it
      // yields the ROOT container — which nothing renders from, leaving the
      // LIVE badge dark while `streamingSourceProvider` reads Active.
      final container = activeTabContainer(tester);

      // Streaming begins idle.
      expect(
        container.read(streamingSourceProvider),
        isA<StreamingViewerIdle>(),
      );

      // Build a stream controller, start streaming, then push the header
      // and partial value-changes through it.
      final controller = StreamController<List<int>>();
      final startFuture = container
          .read(streamingSourceProvider.notifier)
          .startFromStream(controller.stream);

      controller.add(utf8.encode(_partialVcd));
      await tester.pump();
      await startFuture;
      // Use pump() rather than pumpAndSettle() because the LIVE badge has
      // a continuously running pulse animation that prevents idle.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // We must be in Active and the LIVE badge must be visible after the
      // header was successfully parsed.
      expect(
        container.read(streamingSourceProvider),
        isA<StreamingViewerActive>(),
      );
      expect(find.text('LIVE'), findsOneWidget);

      // Wait until the partial transitions have been ingested. The fixture
      // has transitions up to #20.
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final s = container.read(streamingSourceProvider);
        if (s is StreamingViewerActive && s.currentEndTime >= 20) break;
      }
      final partialState = container.read(streamingSourceProvider);
      expect(partialState, isA<StreamingViewerActive>());
      expect(
        (partialState as StreamingViewerActive).currentEndTime,
        greaterThanOrEqualTo(20),
      );

      // Capture the source so we can verify it survives EOF.
      final svcBeforeEof = container
          .read(streamingSourceProvider.notifier)
          .serviceForTesting;
      expect(svcBeforeEof, isNotNull);
      final sourceBeforeEof = container.read(waveformSourceProvider).value;
      expect(sourceBeforeEof, isNotNull);

      // ── Producer EOF: close the write side abruptly. ─────────────────
      await controller.close();

      // _stopInternal() runs as the streamEndedFuture's then-callback.
      // Pump until streaming state returns to Idle.
      var idleReached = false;
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (container.read(streamingSourceProvider) is StreamingViewerIdle) {
          idleReached = true;
          break;
        }
      }
      expect(
        idleReached,
        isTrue,
        reason: 'mid-stream EOF must transition state to Idle',
      );

      await tester.pumpAndSettle();

      // (a) No unhandled exception was thrown.
      expect(
        tester.takeException(),
        isNull,
        reason: 'EOF must not throw an unhandled exception',
      );

      // (b) All transitions received before EOF remain queryable. The
      // streaming service holds them and is still wired to the
      // WaveformSourceNotifier.
      final postEofSource = container.read(waveformSourceProvider).value;
      expect(
        postEofSource,
        isNotNull,
        reason: 'waveform source must survive EOF for post-mortem browsing',
      );
      // Load `clk` and query its value at tick 10 — partial data should
      // record the rising edge in the dumpvars + first transition. The
      // streaming service requires loadSignal() before valueAt() returns
      // a value (same as the WellenProvider lazy-loading contract).
      await postEofSource!.loadSignal('!');
      final clkValueAt10 = postEofSource.valueAt('!', 10);
      expect(
        clkValueAt10,
        equals('1'),
        reason: 'pre-EOF transition at tick 10 must remain queryable',
      );

      // (c) LIVE badge has cleared — the indicator now signals that the
      // stream ended, matching the documented post-EOF behavior.
      expect(
        find.text('LIVE'),
        findsNothing,
        reason: 'LIVE badge must clear once streaming ends',
      );
    },
  );
}
