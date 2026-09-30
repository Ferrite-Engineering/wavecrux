// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';

void main() {
  group('DecoderConfig', () {
    const config = DecoderConfig(
      signalBindings: {'mosi': 'top.spi.mosi', 'sclk': 'top.spi.sclk'},
      parameters: {'cpol': false, 'baud': 9600},
    );

    const configEmpty = DecoderConfig(
      signalBindings: {'cs': 'top.spi.cs'},
    );

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const other = DecoderConfig(
        signalBindings: {'mosi': 'top.spi.mosi', 'sclk': 'top.spi.sclk'},
        parameters: {'cpol': false, 'baud': 9600},
      );
      expect(config, equals(other));
    });

    test('identical instances are equal', () {
      expect(config, equals(config));
    });

    test('equal with empty parameters default', () {
      const other = DecoderConfig(signalBindings: {'cs': 'top.spi.cs'});
      expect(configEmpty, equals(other));
    });

    test('not equal when signalBindings differ', () {
      const other = DecoderConfig(
        signalBindings: {'mosi': 'top.spi.mosi'},
        parameters: {'cpol': false, 'baud': 9600},
      );
      expect(config, isNot(equals(other)));
    });

    test('not equal when signalBinding value differs', () {
      const other = DecoderConfig(
        signalBindings: {'mosi': 'top.spi.mosi', 'sclk': 'top.spi.clk'},
        parameters: {'cpol': false, 'baud': 9600},
      );
      expect(config, isNot(equals(other)));
    });

    test('not equal when parameters differ', () {
      const other = DecoderConfig(
        signalBindings: {'mosi': 'top.spi.mosi', 'sclk': 'top.spi.sclk'},
        parameters: {'cpol': true, 'baud': 9600},
      );
      expect(config, isNot(equals(other)));
    });

    test('hashCode consistent with equality', () {
      const other = DecoderConfig(
        signalBindings: {'mosi': 'top.spi.mosi', 'sclk': 'top.spi.sclk'},
        parameters: {'cpol': false, 'baud': 9600},
      );
      expect(config.hashCode, equals(other.hashCode));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith returns equal when no args', () {
      expect(config.copyWith(), equals(config));
    });

    test('copyWith updates signalBindings', () {
      final updated = config.copyWith(signalBindings: {'cs': 'top.cs'});
      expect(updated.signalBindings, {'cs': 'top.cs'});
      expect(updated.parameters, config.parameters);
    });

    test('copyWith updates parameters', () {
      final updated = config.copyWith(parameters: {'cpol': true});
      expect(updated.parameters, {'cpol': true});
      expect(updated.signalBindings, config.signalBindings);
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains binding keys and parameter keys', () {
      final s = config.toString();
      expect(s, contains('mosi'));
      expect(s, contains('cpol'));
    });

    // ── JSON round-trip ───────────────────────────────────────────────────────

    test('toJson emits bindings and parameters maps', () {
      final json = config.toJson();
      expect(json['bindings'], {
        'mosi': 'top.spi.mosi',
        'sclk': 'top.spi.sclk',
      });
      expect(json['parameters'], {'cpol': false, 'baud': 9600});
    });

    test(
      'toJson omits parameters key when empty for byte-stable v1 read-back',
      () {
        final json = configEmpty.toJson();
        expect(json.containsKey('parameters'), isFalse);
        expect(json['bindings'], {'cs': 'top.spi.cs'});
      },
    );

    test('round-trips through toJson → fromJson', () {
      final decoded = DecoderConfig.fromJson(config.toJson());
      expect(decoded, equals(config));
    });

    test('round-trips an empty-parameters config', () {
      final decoded = DecoderConfig.fromJson(configEmpty.toJson());
      expect(decoded, equals(configEmpty));
    });

    test('fromJson tolerates a missing bindings field', () {
      final decoded = DecoderConfig.fromJson(const <String, Object?>{});
      expect(decoded.signalBindings, isEmpty);
      expect(decoded.parameters, isEmpty);
    });

    test('fromJson drops non-string binding values silently', () {
      final decoded = DecoderConfig.fromJson(const <String, Object?>{
        'bindings': <String, Object?>{
          'mosi': 'top.spi.mosi',
          'sclk': 42,
          'miso': null,
        },
      });
      expect(decoded.signalBindings, {'mosi': 'top.spi.mosi'});
    });

    test('fromJson preserves heterogeneous parameter value types', () {
      // Per-decoder shape validation runs at decode time, not in
      // fromJson — the serializer is decoder-agnostic.
      final decoded = DecoderConfig.fromJson(const <String, Object?>{
        'bindings': <String, Object?>{'sclk': 'top.spi.sclk'},
        'parameters': <String, Object?>{
          'bit_width': 8,
          'cpol': true,
          'mode': 'mode0',
        },
      });
      expect(decoded.parameters['bit_width'], 8);
      expect(decoded.parameters['cpol'], true);
      expect(decoded.parameters['mode'], 'mode0');
    });
  });
}
