// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

// Minimal ProtocolDecoder stub for testing
class _StubDecoder implements ProtocolDecoder {
  _StubDecoder(this._definition);

  final DecoderDefinition _definition;

  @override
  DecoderDefinition get definition => _definition;

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => [];
}

DecoderDefinition _makeDef(
  String id,
  String displayName, {
  DecoderCategory category = DecoderCategory.custom,
}) => DecoderDefinition(
  id: id,
  displayName: displayName,
  description: 'Test decoder $id',
  category: category,
  requiredSignals: const [
    SignalBinding(name: 'clk', description: 'Clock'),
  ],
);

void main() {
  final registry = DecoderRegistry.instance;

  setUp(registry.clear);

  group('DecoderRegistry', () {
    // ── register & lookup ─────────────────────────────────────────────────────

    test('isRegistered returns false for unknown id', () {
      expect(registry.isRegistered('spi'), isFalse);
    });

    test('isRegistered returns true after register', () {
      final def = _makeDef('spi', 'SPI');
      registry.register(def, (config) => _StubDecoder(def));
      expect(registry.isRegistered('spi'), isTrue);
    });

    test('getDefinition returns null for unknown id', () {
      expect(registry.getDefinition('spi'), isNull);
    });

    test('getDefinition returns registered definition', () {
      final def = _makeDef('spi', 'SPI');
      registry.register(def, (config) => _StubDecoder(def));
      expect(registry.getDefinition('spi'), equals(def));
    });

    test('getFactory returns null for unknown id', () {
      expect(registry.getFactory('spi'), isNull);
    });

    test('getFactory returns callable factory', () {
      final def = _makeDef('spi', 'SPI');
      registry.register(def, (config) => _StubDecoder(def));
      final factory = registry.getFactory('spi');
      expect(factory, isNotNull);
      final decoder = factory!(const DecoderConfig(signalBindings: {}));
      expect(decoder, isA<_StubDecoder>());
    });

    // ── listDecoders ──────────────────────────────────────────────────────────

    test('listDecoders returns empty when nothing registered', () {
      expect(registry.listDecoders(), isEmpty);
    });

    test('listDecoders returns all registered decoders', () {
      final spi = _makeDef('spi', 'SPI');
      final i2c = _makeDef('i2c', 'I2C');
      registry
        ..register(spi, (c) => _StubDecoder(spi))
        ..register(i2c, (c) => _StubDecoder(i2c));
      final list = registry.listDecoders();
      expect(list, hasLength(2));
      expect(list.map((d) => d.id), containsAll(['spi', 'i2c']));
    });

    test('listDecoders is sorted by displayName', () {
      final uart = _makeDef('uart', 'UART');
      final apb = _makeDef('apb', 'APB');
      final spi = _makeDef('spi', 'SPI');
      registry
        ..register(uart, (c) => _StubDecoder(uart))
        ..register(apb, (c) => _StubDecoder(apb))
        ..register(spi, (c) => _StubDecoder(spi));
      final names = registry.listDecoders().map((d) => d.displayName).toList();
      expect(names, ['APB', 'SPI', 'UART']);
    });

    // ── duplicate registration ────────────────────────────────────────────────

    test('re-registering same id replaces definition', () {
      final v1 = _makeDef('spi', 'SPI v1');
      final v2 = _makeDef('spi', 'SPI v2');
      registry
        ..register(v1, (c) => _StubDecoder(v1))
        ..register(v2, (c) => _StubDecoder(v2));
      expect(registry.getDefinition('spi')!.displayName, 'SPI v2');
      expect(registry.listDecoders(), hasLength(1));
    });

    // ── factory produces working decoder ─────────────────────────────────────

    test('factory-constructed decoder decode returns list', () {
      final def = _makeDef('spi', 'SPI');
      registry.register(def, (c) => _StubDecoder(def));
      final decoder = registry.getFactory('spi')!(
        const DecoderConfig(signalBindings: {'clk': 'top.clk'}),
      );
      final result = decoder.decode(
        0,
        1000,
        (name, time) => null,
        (name, s, e) => [],
      );
      expect(result, isA<List<DecodedTransaction>>());
    });

    // ── clear ─────────────────────────────────────────────────────────────────

    test('clear removes all registrations', () {
      final def = _makeDef('spi', 'SPI');
      registry
        ..register(def, (c) => _StubDecoder(def))
        ..clear();
      expect(registry.isRegistered('spi'), isFalse);
      expect(registry.listDecoders(), isEmpty);
    });

    // ── listByCategory ────────────────────────────────────────────────────────

    test('listByCategory returns empty map when nothing registered', () {
      expect(registry.listByCategory(), isEmpty);
    });

    test('listByCategory groups decoders by their category', () {
      final spi = _makeDef('spi', 'SPI', category: DecoderCategory.serial);
      final i2c = _makeDef('i2c', 'I2C', category: DecoderCategory.serial);
      final apb = _makeDef('apb', 'APB', category: DecoderCategory.amba);
      registry
        ..register(spi, (c) => _StubDecoder(spi))
        ..register(i2c, (c) => _StubDecoder(i2c))
        ..register(apb, (c) => _StubDecoder(apb));
      final byCategory = registry.listByCategory();
      expect(byCategory, hasLength(2));
      expect(byCategory[DecoderCategory.serial], hasLength(2));
      expect(byCategory[DecoderCategory.amba], hasLength(1));
    });

    test('listByCategory omits empty categories', () {
      final spi = _makeDef('spi', 'SPI', category: DecoderCategory.serial);
      registry.register(spi, (c) => _StubDecoder(spi));
      final byCategory = registry.listByCategory();
      expect(byCategory.keys, [DecoderCategory.serial]);
      // No amba/highSpeed/etc keys for unregistered categories.
      expect(byCategory.containsKey(DecoderCategory.amba), isFalse);
      expect(byCategory.containsKey(DecoderCategory.custom), isFalse);
    });

    test(
      'listByCategory entries within a category are sorted by displayName',
      () {
        final uart = _makeDef('uart', 'UART', category: DecoderCategory.serial);
        final i2c = _makeDef('i2c', 'I2C', category: DecoderCategory.serial);
        final spi = _makeDef('spi', 'SPI', category: DecoderCategory.serial);
        registry
          ..register(uart, (c) => _StubDecoder(uart))
          ..register(i2c, (c) => _StubDecoder(i2c))
          ..register(spi, (c) => _StubDecoder(spi));
        final names = registry
            .listByCategory()[DecoderCategory.serial]!
            .map((d) => d.displayName)
            .toList();
        expect(names, ['I2C', 'SPI', 'UART']);
      },
    );

    test(
      'listByCategory map iteration order matches DecoderCategory.values',
      () {
        // Fixed display order is the value of categorization — pinning this is
        // the regression guard that protects locale-independent rendering.
        final eth = _makeDef(
          'eth',
          'Ethernet AXIS',
          category: DecoderCategory.ethernet,
        );
        final apb = _makeDef('apb', 'APB', category: DecoderCategory.amba);
        final spi = _makeDef('spi', 'SPI', category: DecoderCategory.serial);
        // Register out of order — listByCategory must still return them in
        // declaration order.
        registry
          ..register(eth, (c) => _StubDecoder(eth))
          ..register(apb, (c) => _StubDecoder(apb))
          ..register(spi, (c) => _StubDecoder(spi));
        final keys = registry.listByCategory().keys.toList();
        expect(keys, [
          DecoderCategory.serial,
          DecoderCategory.amba,
          DecoderCategory.ethernet,
        ]);
      },
    );

    test('listByCategory handles default-category (custom) decoders', () {
      // Decoders with no explicit category land in the custom bucket.
      final third = _makeDef('community_decoder', 'Community Decoder');
      registry.register(third, (c) => _StubDecoder(third));
      final byCategory = registry.listByCategory();
      expect(byCategory[DecoderCategory.custom], hasLength(1));
      expect(byCategory[DecoderCategory.custom]!.first.id, 'community_decoder');
    });
  });
}
