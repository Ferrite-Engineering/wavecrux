// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/decoders/decoder_restore_on_open_test.dart
//
// protocol decoder restore on session open.
//
// End-to-end test for the open-core decoder serialization seam:
//
//  1. Boot the app on a fixture VCD that carries both an SPI bus and an
//     I²C bus (`protocol/multi/spi_i2c_basic.vcd` — the same fixture
//     `multi_decoder_coexistence_test.dart` uses).
//  2. Add an SPI decoder and an I²C decoder directly through
//     `activeDecodersProvider.notifier` and pump until both have
//     decoded transactions.
//  3. Snapshot the live session via `SessionNotifier.snapshot()` and
//     save it to a temp `.wavecrux` file through `SessionService`.
//  4. Attach a listener to `activeDecodersProvider` BEFORE the restore.
//  5. Restore the session via `SessionNotifier.loadFromPath(tempPath)`.
//  6. Assert:
//     * the live decoder set is exactly the two restored entries with
//       their instanceNumbers preserved,
//     * `decodeAll()` re-populated transactions against the freshly-
//       opened source,
//     * NO state observed during the restore had an empty list — the
//       `clearAll()`-then-restore flicker the `preserveDecoders` seam exists
//       to prevent never appeared.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/session/session_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'SPI + I²C decoders restore on .wavecrux open without a transient '
    'empty-state flicker',
    (tester) async {
      // 1. Boot on the combined SPI + I²C fixture.
      await loadFixtureVcd(tester, 'protocol/multi/spi_i2c_basic.vcd');

      final root = rootContainer(tester);
      final tab = root.read(tabListProvider).first;
      final container = root
          .read(tabContainerManagerProvider)
          .containerFor(tab.id);

      final source = container.read(waveformSourceProvider).value!;
      final vars = source.findVariables(const SignalFilter());
      String refFor(String name) =>
          vars.firstWhere((v) => v.name == name).signalRef;

      // 2. Activate SPI + I²C decoders. addDecoder assigns instanceNumber
      // 1 for each since they are different decoder types.
      final notifier = container.read(activeDecodersProvider.notifier)
        ..addDecoder(
          'spi',
          DecoderConfig(
            signalBindings: {
              'sclk': refFor('sclk'),
              'mosi': refFor('mosi'),
              'miso': refFor('miso'),
              'cs': refFor('cs'),
            },
          ),
        )
        ..addDecoder(
          'i2c',
          DecoderConfig(
            signalBindings: {
              'scl': refFor('scl'),
              'sda': refFor('sda'),
            },
          ),
        );

      // Drive decodeAll and wait for transactions on both. Mirrors the
      // pattern in multi_decoder_coexistence_test.dart.
      unawaited(notifier.decodeAll());
      final readyBeforeRestore = await pumpUntil(tester, () {
        final ds = container.read(activeDecodersProvider);
        return ds.length == 2 && ds.every((d) => d.transactions.isNotEmpty);
      });
      expect(
        readyBeforeRestore,
        isTrue,
        reason:
            'pre-condition: both decoders must decode before the '
            'session snapshot — otherwise the restore-side decodeAll '
            'is the only thing populating transactions and the '
            '"no-flicker" assertion below is trivially true',
      );

      // Capture instanceNumbers so we can assert they round-trip.
      final beforeRestore = {
        for (final d in container.read(activeDecodersProvider))
          d.decoderId: d.instanceNumber,
      };
      expect(beforeRestore, {'spi': 1, 'i2c': 1});

      // 3. Snapshot the session and persist it under a temp path.
      final state = container.read(sessionProvider.notifier).snapshot();
      expect(
        state.decoders,
        hasLength(2),
        reason: 'SessionNotifier._snapshot must capture both decoders',
      );

      final tempDir = await Directory.systemTemp.createTemp(
        'wavecrux_dec_restore_',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } on FileSystemException catch (_) {}
      });
      final sessionPath = '${tempDir.path}/restore.wavecrux';
      await const SessionService().saveSession(state, sessionPath);

      // 4. Listen to the active-decoders provider so we can replay every
      // intermediate emission and prove none of them was empty.
      final observed = <List<ActiveDecoder>>[
        container.read(activeDecodersProvider),
      ];
      final sub = container.listen<List<ActiveDecoder>>(
        activeDecodersProvider,
        (_, next) => observed.add(next),
      );
      addTearDown(sub.close);

      // 5. Trigger the restore.
      await container.read(sessionProvider.notifier).loadFromPath(sessionPath);

      // Wait for the post-restore decodeAll() pass to repopulate
      // transactions — without this the test would assert mid-decode.
      final readyAfterRestore = await pumpUntil(tester, () {
        final ds = container.read(activeDecodersProvider);
        return ds.length == 2 && ds.every((d) => d.transactions.isNotEmpty);
      });
      expect(
        readyAfterRestore,
        isTrue,
        reason: 'decoders must repopulate transactions after restore',
      );

      // 6a. The live decoder set is the restored pair.
      final restored = container.read(activeDecodersProvider);
      expect(restored, hasLength(2));
      expect(
        restored.map((d) => d.decoderId).toSet(),
        {'spi', 'i2c'},
      );
      expect(
        {for (final d in restored) d.decoderId: d.instanceNumber},
        beforeRestore,
        reason:
            'instanceNumbers must round-trip through the persisted '
            'snapshot so user-visible "SPI #1" / "I²C #1" labels remain '
            'stable across a restart',
      );
      expect(
        restored.every((d) => d.transactions.isNotEmpty),
        isTrue,
        reason: 'decodeAll() must run against the freshly-opened source',
      );

      // 6b. The key restore invariant: no transient empty list during
      // the restore. The seam (`preserveDecoders: true` on openFile +
      // single-replacement restoreDecoders) exists precisely so the
      // active-decoders state never visits `[]` mid-restore.
      for (final s in observed) {
        expect(
          s,
          isNotEmpty,
          reason:
              'active-decoders state observed as empty during the '
              'restore — that is the clearAll()-then-restore flicker '
              'the preserveDecoders seam exists to prevent',
        );
      }

      expect(tester.takeException(), isNull);
    },
  );
}
