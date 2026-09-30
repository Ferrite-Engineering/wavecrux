// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/streaming/interactive_vcd_test.dart
//
// Interactive / streaming VCD progressive parse end-to-end.
//
// Exercises the full streaming pipeline (StreamingVcdService →
// StreamingSourceNotifier → WaveformSourceNotifier.attachStreamingSource
// → hierarchy → LIVE-badge state machine → EOF auto-stop) by feeding a
// hand-crafted VCD through a `StreamController<List<int>>`. The test
// drives the same `_start(Stream<List<int>>)` code path that production
// uses for `--stdin` and `--pipe`, so a regression in any of those
// production paths is also caught by this test.
//
// Why a StreamController, not a real stdin or FIFO:
//   - `flutter_test` cannot redirect the parent process's stdin.
//   - `File.openRead()` on a POSIX FIFO returns whatever bytes are
//     currently buffered then signals EOF, so a regular file or FIFO
//     cannot reproduce true progressive arrival from a test.
//   - The `@visibleForTesting` `startFromStream` seam on
//     [StreamingSourceNotifier] delegates to the same private `_start`
//     method that `startFromStdin` and `startFromPipe` call, so test
//     coverage at this seam is faithful coverage of the production code.
//
// The test boots the app with a small fixture so the viewer is active
// (so the toolbar's LIVE badge can become visible). It then closes that
// initial waveform and replaces it with the streaming source — the
// same sequence a user goes through when they invoke
// `wavecrux --stdin` after already having a file open.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../helpers/app_driver.dart';

// ── Hand-crafted streaming VCD fixture ────────────────────────────────────────
//
// Header + a `$dumpvars` block + ten transition timestamps. Splits cleanly
// into a header portion, a first half of transitions, and a second half so
// the test can assert that hierarchy is visible after the header alone,
// then that endTime advances when the second half arrives.

const _streamingHeader = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " rst $end
$var wire 8 # data $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
1"
b00000000 #
$end
''';

const _streamingFirstHalf = '''
#10
1!
#20
0!
#30
1!
0"
b00000001 #
#40
0!
#50
1!
b00000010 #
''';

const _streamingSecondHalf = '''
#60
0!
#70
1!
#80
0!
#90
1!
b11111111 #
#100
0!
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'progressive streaming parse: header → hierarchy, '
    'second half extends endTime, EOF returns to idle',
    (tester) async {
      // Boot into the viewer with a small fixture so the toolbar / canvas
      // chrome is mounted and ready to receive a streaming source via
      // attachStreamingSource(). This mirrors how a user starts a
      // streaming session: the viewer is already on screen.
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      // Resolve the active tab's ProviderContainer, which is the one
      // production code drives for --stdin / --pipe flag-driven streaming:
      // `ViewerScreen` starts and stops streaming through the active tab.
      //
      // Deliberately NOT `ProviderScope.containerOf(<ViewerToolbar element>)`.
      // In the PaneHost layout the toolbar is a *sibling* of PaneHost, outside
      // every tab scope, so that resolves the ROOT container — an instance
      // nothing renders from. Driving it would leave the badge dark while
      // `streamingSourceProvider` reported Active, which is exactly the false
      // pass this test exists to prevent. The toolbar reaches per-tab streaming
      // state through the root-scope `activeTabStreamingProvider` mirror.
      final container = activeTabContainer(tester);

      // Streaming starts idle before any chunks have arrived.
      expect(
        container.read(streamingSourceProvider),
        isA<StreamingViewerIdle>(),
      );

      // Open a StreamController and start streaming. _start runs the same
      // sequence as startFromStdin / startFromPipe: createService,
      // attachStreamingSource, listen for streamEndedFuture, await header,
      // start elapsed timer, transition to Active.
      final controller = StreamController<List<int>>();
      final startFuture = container
          .read(streamingSourceProvider.notifier)
          .startFromStream(controller.stream);

      // ── Feed the header ────────────────────────────────────────────────
      // Header bytes complete the `$enddefinitions $end` directive and
      // resolve `headerParsedFuture`. Until those bytes arrive,
      // startFromStream awaits inside the service.
      controller.add(utf8.encode(_streamingHeader));
      await tester.pump();

      // The header future resolves on the StreamingVcdService side via a
      // microtask. Pump until startFromStream completes — i.e. the notifier
      // has transitioned from Starting to Active. Use pump() rather than
      // pumpAndSettle() because the LIVE badge starts a repeating pulse
      // animation that prevents the framework from ever reaching idle.
      await startFuture;
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // ── Assert hierarchy is visible (signals appeared) ─────────────────
      final source = container.read(waveformSourceProvider).value;
      expect(source, isNotNull, reason: 'streaming source must be attached');
      expect(
        source!.rootScopes,
        isNotEmpty,
        reason: 'header parse should populate rootScopes',
      );
      expect(source.rootScopes.first.name, equals('top'));
      expect(
        source.rootScopes.first.variables.map((v) => v.name),
        containsAll(<String>['clk', 'rst', 'data']),
        reason: 'all three declared signals must be in the hierarchy',
      );

      // Streaming state must be Active and the LIVE badge must be visible
      // in the viewer toolbar.
      expect(
        container.read(streamingSourceProvider),
        isA<StreamingViewerActive>(),
      );
      expect(
        find.text('LIVE'),
        findsOneWidget,
        reason: 'LIVE badge must appear in the toolbar while streaming',
      );

      // ── Feed the first half of value changes ───────────────────────────
      controller.add(utf8.encode(_streamingFirstHalf));
      await tester.pump();

      // Wait until endTime catches up to the last value change in the first
      // half (#50). The debounced onDataUpdated stream fires within a few
      // milliseconds in tests since updateInterval is set to 100ms; pump
      // a generous window so the active state's currentEndTime updates.
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final s = container.read(streamingSourceProvider);
        if (s is StreamingViewerActive && s.currentEndTime >= 50) break;
      }
      final firstHalfState = container.read(streamingSourceProvider);
      expect(firstHalfState, isA<StreamingViewerActive>());
      expect(
        (firstHalfState as StreamingViewerActive).currentEndTime,
        greaterThanOrEqualTo(50),
        reason: 'first-half transitions must extend currentEndTime to ≥ 50',
      );

      // The waveform source's endTime must also reflect the partial data.
      // The streaming service exposes the same data via the
      // WaveformDataSource interface, so the value column / canvas would
      // also see this updated state.
      final svc = container
          .read(streamingSourceProvider.notifier)
          .serviceForTesting;
      expect(svc, isNotNull);
      expect(svc!.endTime, greaterThanOrEqualTo(50));

      // ── Feed the second half of value changes ──────────────────────────
      controller.add(utf8.encode(_streamingSecondHalf));
      await tester.pump();

      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final s = container.read(streamingSourceProvider);
        if (s is StreamingViewerActive && s.currentEndTime >= 100) break;
      }
      final secondHalfState = container.read(streamingSourceProvider);
      expect(
        secondHalfState,
        isA<StreamingViewerActive>(),
        reason: 'streaming must still be Active before EOF',
      );
      expect(
        (secondHalfState as StreamingViewerActive).currentEndTime,
        greaterThanOrEqualTo(100),
        reason: 'second-half transitions must extend currentEndTime to 100',
      );
      // Crucially: the hierarchy must NOT have been re-loaded between the
      // two halves — the same source instance is still attached. (We check
      // this via reference identity on the WaveformSourceNotifier value.)
      expect(
        container.read(waveformSourceProvider).value,
        same(source),
        reason: 'app must not reload — same WaveformDataSource instance',
      );

      // ── Close the stream → simulate producer EOF ───────────────────────
      await controller.close();

      // streamEndedFuture resolves on EOF, which triggers _stopInternal()
      // via the streamEndedFuture.then() callback in _start(). Poll until
      // the state transitions back to Idle.
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
        reason: 'natural EOF must transition state to Idle',
      );

      // After EOF the LIVE badge must be gone, but the accumulated data
      // remains queryable (user can browse the final waveform).
      // Once the streaming state is Idle the pulse animation has stopped,
      // so pumpAndSettle() is safe again.
      await tester.pumpAndSettle();
      expect(
        find.text('LIVE'),
        findsNothing,
        reason: 'LIVE badge must disappear once streaming ends',
      );
      expect(
        container.read(waveformSourceProvider).value,
        isNotNull,
        reason: 'accumulated waveform data must remain queryable post-EOF',
      );

      // No unhandled framework exceptions throughout the test.
      expect(tester.takeException(), isNull);
    },
  );
}
