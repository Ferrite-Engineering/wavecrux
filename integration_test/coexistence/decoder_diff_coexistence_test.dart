// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/coexistence/decoder_diff_coexistence_test.dart
//
// Decoder + waveform diff coexistence.
//
// Loads a primary SPI capture, activates the SPI decoder on it, then enters
// diff mode against a second related capture (a different SPI mode, so the
// shared signals diverge). Asserts that the protocol-decode overlay and the
// diff overlays coexist:
//
//   * The SPI decoder's transactions survive entering diff mode (the overlay
//     still renders on the primary waveform — its decode state is unchanged).
//   * The diff engine produces matched signals with at least one divergence
//     region → the amber time-ruler divergence bands have data to paint.
//   * XOR traces are produced for the differing signals → the canvas XOR
//     diff lanes have data to inject after the differing lane.
//   * The waveform canvas and time ruler render without an unhandled
//     exception.
//
// Fixtures: `protocol/spi/generated/spi_basic.vcd` (primary) and
// `protocol/spi/generated/spi_mode1.vcd` (comparison). See
// `verification/VERIFICATION_GUIDE.md` §22.9 "Decoder + diff coexistence".

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/app_driver.dart';

String _fixturePath(String relative) => [
  Directory.current.path,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'SPI decode overlay and diff XOR/divergence overlays coexist',
    (tester) async {
      await loadFixtureVcd(tester, 'protocol/spi/generated/spi_basic.vcd');
      await activateDecoder(tester, 'SPI');

      final root = rootContainer(tester);
      final tab = root.read(tabListProvider).first;
      final container = root
          .read(tabContainerManagerProvider)
          .containerFor(tab.id);

      // Decoder produced its transactions before diff mode is entered.
      final spiBefore = container
          .read(activeDecodersProvider)
          .firstWhere((d) => d.decoderId == 'spi');
      expect(spiBefore.transactions, isNotEmpty);
      final spiTxnCountBefore = spiBefore.transactions.length;

      // Put a differing signal on the canvas so a matched lane exists for the
      // XOR diff lane to be injected after.
      final source = container.read(waveformSourceProvider).value!;
      final mosi = source
          .findVariables(const SignalFilter())
          .firstWhere((v) => v.name == 'mosi');
      container.read(signalGroupsProvider.notifier).addSignal(mosi);
      await tester.pump();

      // Enter diff mode against a different SPI mode capture (same signal
      // names, divergent timelines).
      unawaited(
        container
            .read(diffProvider.notifier)
            .loadSecondFile(
              _fixturePath('protocol/spi/generated/spi_mode1.vcd'),
            ),
      );

      // Bounded poll: wait for the diff computation to settle.
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final s = container.read(diffProvider);
        if (!s.isLoading && s.diffResult != null) break;
      }

      final diff = container.read(diffProvider);
      expect(diff.error, isNull, reason: 'diff load must not error');
      expect(diff.isActive, isTrue, reason: 'diff mode must be active');
      expect(diff.diffResult, isNotNull);
      expect(
        diff.diffResult!.matchedSignals,
        isNotEmpty,
        reason: 'the shared SPI signals must match across the two captures',
      );
      expect(
        diff.totalDivergences,
        greaterThan(0),
        reason: 'divergent SPI modes must produce time-ruler divergence bands',
      );
      expect(
        diff.xorTraces,
        isNotEmpty,
        reason: 'differing signals must produce XOR diff-lane traces',
      );

      // The SPI overlay is untouched by entering diff mode.
      final spiAfter = container
          .read(activeDecodersProvider)
          .firstWhere((d) => d.decoderId == 'spi');
      expect(
        spiAfter.transactions.length,
        spiTxnCountBefore,
        reason: 'entering diff mode must not drop the SPI decode overlay',
      );

      // Both rendering surfaces are present and the frame is exception-free.
      expect(find.byType(WaveformCanvas), findsWidgets);
      expect(find.byType(TimeRulerWidget), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
