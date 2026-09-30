// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';

void main() {
  group('PersistedDecoder', () {
    const config = DecoderConfig(
      signalBindings: {
        'sclk': 'top.spi.sclk',
        'mosi': 'top.spi.mosi',
        'miso': 'top.spi.miso',
        'cs': 'top.spi.cs',
      },
      parameters: {'cpol': false, 'cpha': false},
    );

    const persisted = PersistedDecoder(
      decoderId: 'spi',
      instanceNumber: 2,
      config: config,
    );

    test('equality holds across identical construction', () {
      const other = PersistedDecoder(
        decoderId: 'spi',
        instanceNumber: 2,
        config: config,
      );
      expect(persisted, equals(other));
      expect(persisted.hashCode, other.hashCode);
    });

    test('inequality on any differing field', () {
      const differentId = PersistedDecoder(
        decoderId: 'i2c',
        instanceNumber: 2,
        config: config,
      );
      const differentInstance = PersistedDecoder(
        decoderId: 'spi',
        instanceNumber: 1,
        config: config,
      );
      const differentConfig = PersistedDecoder(
        decoderId: 'spi',
        instanceNumber: 2,
        config: DecoderConfig(signalBindings: {}),
      );

      expect(persisted, isNot(equals(differentId)));
      expect(persisted, isNot(equals(differentInstance)));
      expect(persisted, isNot(equals(differentConfig)));
    });

    test('copyWith independently updates each field', () {
      expect(persisted.copyWith(), equals(persisted));
      expect(persisted.copyWith(decoderId: 'uart').decoderId, 'uart');
      expect(persisted.copyWith(instanceNumber: 7).instanceNumber, 7);
      expect(
        persisted
            .copyWith(
              config: const DecoderConfig(signalBindings: {'a': 'b'}),
            )
            .config
            .signalBindings,
        {'a': 'b'},
      );
    });

    test('toJson emits decoderId, instanceNumber, and nested config', () {
      final json = persisted.toJson();
      expect(json['decoderId'], 'spi');
      expect(json['instanceNumber'], 2);
      expect(json['config'], isA<Map<String, Object?>>());
      final configJson = json['config']! as Map<String, Object?>;
      expect(configJson['bindings'], config.signalBindings);
      expect(configJson['parameters'], config.parameters);
    });

    test('round-trips through toJson → fromJson', () {
      final decoded = PersistedDecoder.fromJson(persisted.toJson());
      expect(decoded, equals(persisted));
    });

    test('fromJson tolerates a missing config field as empty bindings', () {
      final decoded = PersistedDecoder.fromJson(const <String, Object?>{
        'decoderId': 'spi',
        'instanceNumber': 3,
      });
      expect(decoded.decoderId, 'spi');
      expect(decoded.instanceNumber, 3);
      expect(decoded.config.signalBindings, isEmpty);
      expect(decoded.config.parameters, isEmpty);
    });

    test(
      'fromJson preserves an empty decoderId so unknown-id restore can fire',
      () {
        // The seam intentionally does not drop entries with an empty
        // decoderId at parse time — the unknown-id restore branch in
        // SessionService is responsible for logging and skipping. Dropping
        // here would mask the diagnostic.
        final decoded = PersistedDecoder.fromJson(const <String, Object?>{
          'instanceNumber': 1,
          'config': <String, Object?>{
            'bindings': <String, Object?>{'sclk': 'top.spi.sclk'},
          },
        });
        expect(decoded.decoderId, '');
      },
    );
  });
}
