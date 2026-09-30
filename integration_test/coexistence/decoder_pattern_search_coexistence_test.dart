// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/coexistence/decoder_pattern_search_coexistence_test.dart
//
// Decoder + multi-signal pattern search coexistence.
//
// Loads an SPI capture, activates the SPI decoder, then runs a multi-signal
// pattern search for a simple raw-signal condition (`sclk == 1`). Asserts the
// two features coexist:
//
//   * The pattern search produces at least one match → the time-ruler and
//     canvas match-highlight bands have ranges to paint.
//   * The SPI decoder's transactions are unchanged by the search (the decode
//     overlay still renders alongside the highlights).
//   * The waveform canvas and time ruler render without an unhandled
//     exception.
//
// Fixture: `protocol/spi/generated/spi_basic.vcd`. See
// `verification/VERIFICATION_GUIDE.md` §22.9 "Decoder + pattern search
// coexistence".

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'pattern-search match highlights coexist with the SPI decode overlay',
    (tester) async {
      await loadFixtureVcd(tester, 'protocol/spi/generated/spi_basic.vcd');
      await activateDecoder(tester, 'SPI');

      final root = rootContainer(tester);
      final tab = root.read(tabListProvider).first;
      final container = root
          .read(tabContainerManagerProvider)
          .containerFor(tab.id);

      final spiBefore = container
          .read(activeDecodersProvider)
          .firstWhere((d) => d.decoderId == 'spi');
      final spiTxnCountBefore = spiBefore.transactions.length;
      expect(spiTxnCountBefore, greaterThan(0));

      // Put sclk on the canvas so a lane exists to highlight.
      final source = container.read(waveformSourceProvider).value!;
      final sclk = source
          .findVariables(const SignalFilter())
          .firstWhere((v) => v.name == 'sclk');
      container.read(signalGroupsProvider.notifier).addSignal(sclk);
      await tester.pump();

      // Run a simple raw-signal pattern search: sclk == 1. search loads
      // signals via the FFI isolate; pump frames in a bounded poll so it
      // completes (a direct `await` here does not pump and can stall).
      unawaited(
        container
            .read(patternSearchProvider.notifier)
            .search(
              const SignalCondition(
                signalPath: 'sclk',
                operator: ConditionOperator.eq,
                value: '1',
              ),
              source.startTime,
              source.endTime,
            ),
      );
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final s = container.read(patternSearchProvider);
        if (s.hasResult || s.error != null) break;
      }

      final search = container.read(patternSearchProvider);
      expect(search.error, isNull, reason: 'search must not error');
      expect(
        search.hasMatches,
        isTrue,
        reason: 'sclk == 1 must match at least one region in the SPI capture',
      );
      expect(search.matchCount, greaterThan(0));
      expect(
        search.matchRanges,
        isNotEmpty,
        reason: 'match ranges feed the time-ruler and canvas highlight bands',
      );

      // The SPI overlay is untouched by the search.
      final spiAfter = container
          .read(activeDecodersProvider)
          .firstWhere((d) => d.decoderId == 'spi');
      expect(
        spiAfter.transactions.length,
        spiTxnCountBefore,
        reason: 'running a pattern search must not drop the SPI decode overlay',
      );

      expect(find.byType(WaveformCanvas), findsWidgets);
      expect(find.byType(TimeRulerWidget), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
