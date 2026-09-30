// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';

import '../../../helpers/product_telemetry_config.dart';

/// Presenter resolver: local refs P* ↔ paths.
SignalIdentityResolver _presenter() => SignalIdentityResolver(
  pathToRef: const {'top.sclk': 'P1', 'top.mosi': 'P2'},
  refToPath: const {'P1': 'top.sclk', 'P2': 'top.mosi'},
);

/// Follower resolver: different local refs L* for the same paths.
SignalIdentityResolver _follower() => SignalIdentityResolver(
  pathToRef: const {'top.sclk': 'L1', 'top.mosi': 'L2'},
  refToPath: const {'L1': 'top.sclk', 'L2': 'top.mosi'},
);

void main() {
  setUp(DecoderRegistry.instance.clear);
  tearDown(DecoderRegistry.instance.clear);

  group('ActiveDecodersNotifier view-composition recipe seams', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer(overrides: [productTelemetryConfig]));
    tearDown(() => c.dispose());

    final spiId = SpiDecoder.decoderDefinition.id;

    void registerSpi() => DecoderRegistry.instance.register(
      SpiDecoder.decoderDefinition,
      SpiDecoder.new,
    );

    test('toCompositionRecipe rewrites binding refs to canonical paths', () {
      registerSpi();
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            spiId,
            const DecoderConfig(
              signalBindings: {'sclk': 'P1', 'mosi': 'P2'},
              parameters: {'cpol': 1},
            ),
          );

      final recipe = c
          .read(activeDecodersProvider.notifier)
          .toCompositionRecipe(
            _presenter(),
          );
      expect(recipe, hasLength(1));
      expect(recipe.first.config.signalBindings, {
        'sclk': 'top.sclk',
        'mosi': 'top.mosi',
      });
      expect(recipe.first.config.parameters, {'cpol': 1});
    });

    test('round-trip: apply re-binds to follower-local refs', () {
      registerSpi();
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            spiId,
            const DecoderConfig(
              signalBindings: {'sclk': 'P1', 'mosi': 'P2'},
            ),
          );
      final recipe = c
          .read(activeDecodersProvider.notifier)
          .toCompositionRecipe(
            _presenter(),
          );

      final follower = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(follower.dispose);
      final result = follower
          .read(activeDecodersProvider.notifier)
          .applyCompositionRecipe(recipe, _follower());

      expect(result.missingDecoderIds, isEmpty);
      expect(result.missingSignalPaths, isEmpty);
      final applied = follower.read(activeDecodersProvider);
      expect(applied, hasLength(1));
      expect(applied.first.decoderId, spiId);
      expect(applied.first.config.signalBindings, {'sclk': 'L1', 'mosi': 'L2'});
    });

    test('missing-decoder degradation: unregistered decoder is dropped + '
        'reported', () {
      // SPI is NOT registered in the follower's build.
      const recipe = [
        PersistedDecoder(
          decoderId: 'axi4_full',
          instanceNumber: 1,
          config: DecoderConfig(signalBindings: {'awvalid': 'top.aw'}),
        ),
      ];
      final result = c
          .read(activeDecodersProvider.notifier)
          .applyCompositionRecipe(
            recipe,
            SignalIdentityResolver(
              pathToRef: const {'top.aw': 'L1'},
              refToPath: const {'L1': 'top.aw'},
            ),
          );
      expect(result.missingDecoderIds, ['axi4_full']);
      expect(c.read(activeDecodersProvider), isEmpty);
    });

    test('missing-signal degradation: unresolved path binds to empty + '
        'reported', () {
      registerSpi();
      const recipe = [
        PersistedDecoder(
          decoderId: 'spi',
          instanceNumber: 1,
          config: DecoderConfig(
            signalBindings: {'sclk': 'top.sclk', 'mosi': 'top.absent'},
          ),
        ),
      ];
      final result = c
          .read(activeDecodersProvider.notifier)
          .applyCompositionRecipe(recipe, _follower());

      expect(result.missingSignalPaths, ['top.absent']);
      final applied = c.read(activeDecodersProvider);
      expect(applied.first.config.signalBindings, {'sclk': 'L1', 'mosi': ''});
    });
  });
}
