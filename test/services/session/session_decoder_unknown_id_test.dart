// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';

import '../../helpers/product_telemetry_config.dart';

/// Cross-tier-open / uninstalled-plugin contract.
///
/// `ActiveDecodersNotifier.restoreDecoders` is the entry point that
/// `SessionNotifier._restore` calls after the waveform source is ready.
/// When a persisted decoder's `decoderId` is not in the active
/// `DecoderRegistry` (e.g. a `"pro.usb"` decoder opened on the Open
/// Core viewer, or a user plugin that has since been uninstalled), the
/// restore must:
///
/// 1. NOT throw.
/// 2. Keep that entry out of the active-decoders state — there is no factory
///    for it, nothing to decode, and no row to render.
/// 3. **Hold it anyway, and write it back on the next save.** Dropping it
///    made the next save delete the user's decoder configuration for good:
///    the viewer has no undo, and nothing told them, because from their side
///    nothing had happened. This is the half of the contract that is about
///    their file rather than their screen.
/// 4. Emit a single warning line listing the held IDs so the diagnostic shows
///    up in Console / `flutter logs` for after-the-fact triage. NO snackbar,
///    NO exception — a snackbar would fire on every cross-tier open of a Pro
///    session on Open Core, which is intentional and common.

class _NoSource extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncData(null);
}

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      waveformSourceProvider.overrideWith(_NoSource.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(DecoderRegistry.instance.clear);
  tearDown(DecoderRegistry.instance.clear);

  group('ActiveDecodersNotifier.restoreDecoders — unknown decoderId', () {
    test(
      'keeps unregistered entries out of state, keeps the known one, and '
      'logs a single warning line',
      () async {
        // Register only the "spi" decoder; "future_unknown" stands in for
        // a Pro / uninstalled-plugin decoder the current build cannot
        // resolve.
        DecoderRegistry.instance.register(
          SpiDecoder.decoderDefinition,
          SpiDecoder.new,
        );

        // The skipped-decoder diagnostic is emitted via package:logging
        // (Logger 'wavecrux.decoders'), captured by the in-app issue
        // reporter's ring buffer — not debugPrint. Capture Logger.root.
        final records = <LogRecord>[];
        final originalLevel = Logger.root.level;
        Logger.root.level = Level.ALL;
        final sub = Logger.root.onRecord.listen(records.add);
        addTearDown(() async {
          await sub.cancel();
          Logger.root.level = originalLevel;
        });

        final container = _makeContainer();

        // The restore call must complete without throwing even though
        // one of the two entries is for an unregistered decoder.
        container.read(activeDecodersProvider.notifier).restoreDecoders(const [
          PersistedDecoder(
            decoderId: 'spi',
            instanceNumber: 1,
            config: DecoderConfig(
              signalBindings: {'sclk': 'top.spi.sclk', 'mosi': 'top.spi.mosi'},
            ),
          ),
          PersistedDecoder(
            decoderId: 'future_unknown',
            instanceNumber: 1,
            config: DecoderConfig(
              signalBindings: {'a': 'top.future.a'},
            ),
          ),
        ]);

        final state = container.read(activeDecodersProvider);
        expect(state, hasLength(1));
        expect(state.first.decoderId, 'spi');
        expect(state.first.instanceNumber, 1);

        // Exactly one warning was emitted for the held entry, and it names
        // the unknown decoderId so an engineer triaging the case can see what
        // this build could not instantiate.
        final warnings = records
            .where((r) => r.level >= Level.WARNING)
            .map((r) => r.message)
            .toList();
        final matching = warnings
            .where((m) => m.contains('future_unknown'))
            .toList();
        expect(
          matching,
          hasLength(1),
          reason:
              'expected one warning mentioning the unknown decoderId; '
              'got ${warnings.length} warning(s) total',
        );
        expect(matching.first, contains('SessionService restore'));
      },
    );

    test('preserves the persisted instanceNumber on the kept entry', () {
      // The user's "SPI #3" must remain "SPI #3" after a restore — the
      // numbering survives quit/relaunch.
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );

      final container = _makeContainer();
      container.read(activeDecodersProvider.notifier).restoreDecoders(const [
        PersistedDecoder(
          decoderId: 'spi',
          instanceNumber: 3,
          config: DecoderConfig(signalBindings: {'sclk': 'top.spi.sclk'}),
        ),
      ]);
      expect(
        container.read(activeDecodersProvider).first.instanceNumber,
        3,
      );

      // The internal next-counter for "spi" is bumped past 3 so a
      // subsequent addDecoder produces #4, not #1.
      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'spi',
            const DecoderConfig(
              signalBindings: {'sclk': 'top.spi.sclk'},
            ),
          );
      expect(
        container.read(activeDecodersProvider).last.instanceNumber,
        4,
      );
    });

    test('all entries unknown → empty state, no throw, single log line', () {
      // No decoders registered at all (e.g. a fresh app build with
      // only stubs available). The restore must short-circuit cleanly.
      final records = <LogRecord>[];
      final originalLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await sub.cancel();
        Logger.root.level = originalLevel;
      });

      final container = _makeContainer();
      container.read(activeDecodersProvider.notifier).restoreDecoders(const [
        PersistedDecoder(
          decoderId: 'a',
          instanceNumber: 1,
          config: DecoderConfig(signalBindings: {}),
        ),
        PersistedDecoder(
          decoderId: 'b',
          instanceNumber: 2,
          config: DecoderConfig(signalBindings: {}),
        ),
      ]);

      expect(container.read(activeDecodersProvider), isEmpty);
      expect(
        records
            .where((r) => r.level >= Level.WARNING)
            .map((r) => r.message)
            .where((m) => m.contains('SessionService restore'))
            .length,
        1,
      );
    });
  });

  group('a decoder this build cannot instantiate survives a save', () {
    const proDecoder = PersistedDecoder(
      decoderId: 'pro.usb',
      instanceNumber: 2,
      config: DecoderConfig(
        signalBindings: {'dp': 'top.usb.dp', 'dm': 'top.usb.dm'},
        parameters: {'speed': 'full'},
      ),
    );
    const known = PersistedDecoder(
      decoderId: 'spi',
      instanceNumber: 1,
      config: DecoderConfig(signalBindings: {'sclk': 'top.spi.sclk'}),
    );

    test('snapshot writes it back, verbatim, after restore dropped it from '
        'state', () {
      // The whole bug, in one round trip: open a session authored with a
      // decoder this build has no factory for, save, and the decoder must
      // still be in the document. Before the fix `snapshot()` read only from
      // `state`, so the save wrote the session without it and the user's
      // configuration was gone with no undo and no warning.
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      final container = _makeContainer();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [known, proDecoder]);

      expect(
        container.read(activeDecodersProvider).map((d) => d.decoderId),
        ['spi'],
        reason: 'the unrenderable decoder must not reach state',
      );

      final saved = notifier.snapshot();
      expect(saved.map((p) => p.decoderId), ['spi', 'pro.usb']);
      final roundTripped = saved.firstWhere((p) => p.decoderId == 'pro.usb');
      // Verbatim: the build that can finally run it gets the bindings and
      // parameters the authoring build wrote, not a reconstruction.
      expect(roundTripped.instanceNumber, 2);
      expect(roundTripped.config.signalBindings, {
        'dp': 'top.usb.dp',
        'dm': 'top.usb.dm',
      });
      expect(roundTripped.config.parameters, {'speed': 'full'});
    });

    test('survives repeated save cycles without multiplying', () {
      // Auto-save runs on a 2 s debounce off a dozen providers, so a session
      // is snapshotted many times per sitting. Holding the entry must not turn
      // into accumulating it.
      final container = _makeContainer();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [proDecoder]);

      expect(notifier.snapshot().map((p) => p.decoderId), ['pro.usb']);
      expect(notifier.snapshot().map((p) => p.decoderId), ['pro.usb']);
      notifier.restoreDecoders(notifier.snapshot());
      expect(notifier.snapshot().map((p) => p.decoderId), ['pro.usb']);
    });

    test('is released when the file is closed', () {
      // clearAll runs whenever a waveform is opened or closed. Holding across
      // it would write the previous file's decoders into the next file's
      // session — the one way this could invent a decoder instead of keep one.
      final container = _makeContainer();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [proDecoder]);
      expect(notifier.snapshot(), hasLength(1));

      notifier.clearAll();
      expect(notifier.snapshot(), isEmpty);
    });

    test('a restore with nothing missing holds nothing', () {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      final container = _makeContainer();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [known, proDecoder])
        // A second restore whose entries all resolve must clear the first
        // restore's luggage, not keep it.
        ..restoreDecoders(const [known]);

      expect(notifier.snapshot().map((p) => p.decoderId), ['spi']);
    });

    test('holdUnavailable: false drops it, for the collaboration follower', () {
      // applyCompositionRecipe mirrors somebody else's view and tells the user
      // what it could not render. It has no business writing the host's
      // decoders into the follower's own session.
      final container = _makeContainer();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [proDecoder], holdUnavailable: false);

      expect(notifier.snapshot(), isEmpty);
    });
  });
}
