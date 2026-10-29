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

    test('toString tells apart configs that differ only in values', () {
      // A failed `equals` prints both sides with toString. When it printed
      // keys only, two configs with the same slots but different refs, paths
      // or parameter values read identically, and the mismatch was invisible.
      const byRef = DecoderConfig(signalBindings: {'dp': '3'});
      const otherRef = DecoderConfig(signalBindings: {'dp': '4'});
      const withPath = DecoderConfig(
        signalBindings: {'dp': '3'},
        signalPaths: {'dp': 'tb.usb.dp'},
      );
      const otherParam = DecoderConfig(
        signalBindings: {'dp': '3'},
        parameters: {'speed': 'full'},
      );
      const sameKeyOtherParam = DecoderConfig(
        signalBindings: {'dp': '3'},
        parameters: {'speed': 'high'},
      );
      final printed = [
        byRef,
        otherRef,
        withPath,
        otherParam,
        sameKeyOtherParam,
      ].map((c) => c.toString()).toList();
      expect(printed.toSet(), hasLength(printed.length));
      expect(withPath.toString(), contains('tb.usb.dp'));
      expect(sameKeyOtherParam.toString(), contains('high'));
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

  group('DecoderConfig signalPaths (#54)', () {
    const config = DecoderConfig(
      signalBindings: {'clk': '28', 'tlp_data': '1404'},
      signalPaths: {'clk': 'top.clk', 'tlp_data': 'top.pcie.tlp_data'},
    );

    test('defaults to empty', () {
      expect(const DecoderConfig(signalBindings: {}).signalPaths, isEmpty);
    });

    test('toJson writes bindingPaths beside the plain bindings map', () {
      final json = config.toJson();
      // The ref map keeps its old shape, so a build that predates paths still
      // reads the bindings.
      expect(json['bindings'], {'clk': '28', 'tlp_data': '1404'});
      expect(json['bindingPaths'], {
        'clk': 'top.clk',
        'tlp_data': 'top.pcie.tlp_data',
      });
    });

    test('toJson omits bindingPaths when empty', () {
      const plain = DecoderConfig(signalBindings: {'clk': '28'});
      expect(plain.toJson().containsKey('bindingPaths'), isFalse);
    });

    test('JSON round-trip preserves the paths', () {
      expect(DecoderConfig.fromJson(config.toJson()), config);
    });

    test('a pre-1.1.1 config (no bindingPaths) reads with empty paths', () {
      final decoded = DecoderConfig.fromJson(const <String, Object?>{
        'bindings': <String, Object?>{'clk': '28'},
      });
      expect(decoded.signalBindings, {'clk': '28'});
      expect(decoded.signalPaths, isEmpty);
    });

    test('non-string path values are dropped', () {
      final decoded = DecoderConfig.fromJson(const <String, Object?>{
        'bindings': <String, Object?>{'clk': '28'},
        'bindingPaths': <String, Object?>{'clk': 5},
      });
      expect(decoded.signalPaths, isEmpty);
    });

    test('paths take part in equality and hashCode', () {
      const other = DecoderConfig(
        signalBindings: {'clk': '28', 'tlp_data': '1404'},
      );
      expect(config == other, isFalse);
      expect(
        config.copyWith(signalPaths: const {}),
        other,
      );
      expect(
        config.copyWith(signalPaths: const {}).hashCode,
        other.hashCode,
      );
    });

    test('copyWith keeps paths unless replaced', () {
      expect(
        config.copyWith(parameters: const {'x': 1}).signalPaths,
        config.signalPaths,
      );
    });
  });
}
