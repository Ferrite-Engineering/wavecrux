// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/plugins/extra_decoders_provider.dart';

void main() {
  group('extraDecodersProvider', () {
    test('open-core default is an empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(extraDecodersProvider), isEmpty);
    });

    test('overlay override surfaces additional registrations', () {
      const def = DecoderDefinition(
        id: 'fake_pro',
        displayName: 'Fake Pro',
        description: 'Test fixture for the overlay seam',
        requiredSignals: [
          SignalBinding(name: 'sig', description: 'test'),
        ],
        requiredTier: LicenseTier.pro,
      );
      final container = ProviderContainer(
        overrides: [
          extraDecodersProvider.overrideWithValue(<ExtraDecoderRegistration>[
            (definition: def, factory: _FakeDecoder.new),
          ]),
        ],
      );
      addTearDown(container.dispose);

      final extras = container.read(extraDecodersProvider);
      expect(extras, hasLength(1));
      expect(extras.first.definition, def);
      expect(extras.first.definition.requiredTier, LicenseTier.pro);

      // Factory is callable and produces a decoder bound to the supplied
      // config, confirming the typedef shape is correct.
      final decoder = extras.first.factory(
        const DecoderConfig(signalBindings: {'sig': 'top.sig'}),
      );
      expect(decoder.definition, def);
    });
  });
}

class _FakeDecoder implements ProtocolDecoder {
  // Constructor must accept a DecoderConfig to match the DecoderFactory typedef
  // even when this fixture decoder ignores the bindings.
  const _FakeDecoder(DecoderConfig _);

  @override
  DecoderDefinition get definition => const DecoderDefinition(
    id: 'fake_pro',
    displayName: 'Fake Pro',
    description: 'Test fixture for the overlay seam',
    requiredSignals: [
      SignalBinding(name: 'sig', description: 'test'),
    ],
    requiredTier: LicenseTier.pro,
  );

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => const [];
}
