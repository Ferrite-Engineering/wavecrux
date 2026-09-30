// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';

const _config = DecoderConfig(
  signalBindings: {'sclk': 'top.sclk', 'mosi': 'top.mosi'},
  parameters: {'cpol': '0'},
);

const _tx = DecodedTransaction(
  startTime: 0,
  endTime: 1000,
  label: 'Write 0xFF',
  fields: {'data': '0xFF'},
);

void main() {
  group('ActiveDecoder — construction', () {
    test('holds provided fields', () {
      const d = ActiveDecoder(
        id: 'decoder_0',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(d.id, 'decoder_0');
      expect(d.decoderId, 'spi');
      expect(d.config, _config);
      expect(d.instanceNumber, 1);
      expect(d.transactions, isEmpty);
    });

    test('transactions default to empty list', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'uart',
        config: _config,
        instanceNumber: 1,
      );
      expect(d.transactions, isEmpty);
    });

    test('accepts non-empty transactions', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
        transactions: [_tx],
      );
      expect(d.transactions, const [_tx]);
    });
  });

  group('ActiveDecoder — instanceLabel', () {
    test('returns baseName #instanceNumber', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(d.instanceLabel('SPI'), 'SPI #1');
    });

    test('uses instanceNumber in label', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 3,
      );
      expect(d.instanceLabel('UART'), 'UART #3');
    });
  });

  group('ActiveDecoder — copyWith', () {
    test('updates id', () {
      const d = ActiveDecoder(
        id: 'old',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(d.copyWith(id: 'new').id, 'new');
    });

    test('updates decoderId', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(d.copyWith(decoderId: 'uart').decoderId, 'uart');
    });

    test('updates config', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      const newConfig = DecoderConfig(signalBindings: {'tx': 'top.tx'});
      expect(d.copyWith(config: newConfig).config, newConfig);
    });

    test('updates transactions', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(d.copyWith(transactions: const [_tx]).transactions, const [_tx]);
    });

    test('updates instanceNumber', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(d.copyWith(instanceNumber: 2).instanceNumber, 2);
    });

    test('preserves unchanged fields', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 2,
        transactions: [_tx],
      );
      final copy = d.copyWith(id: 'y');
      expect(copy.decoderId, 'spi');
      expect(copy.config, _config);
      expect(copy.instanceNumber, 2);
      expect(copy.transactions, const [_tx]);
    });
  });

  group('ActiveDecoder — equality', () {
    test('equal when all fields match', () {
      const a = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
        transactions: [_tx],
      );
      const b = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
        transactions: [_tx],
      );
      expect(a, equals(b));
    });

    test('not equal when id differs', () {
      const a = ActiveDecoder(
        id: 'a',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      const b = ActiveDecoder(
        id: 'b',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when decoderId differs', () {
      const a = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      const b = ActiveDecoder(
        id: 'x',
        decoderId: 'uart',
        config: _config,
        instanceNumber: 1,
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when config differs', () {
      const a = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      const b = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: DecoderConfig(signalBindings: {}),
        instanceNumber: 1,
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when instanceNumber differs', () {
      const a = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      const b = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 2,
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when transactions differ', () {
      const a = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      const b = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
        transactions: [_tx],
      );
      expect(a, isNot(equals(b)));
    });

    test('identical instance equals itself', () {
      const d = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(d, equals(d));
    });

    test('hashCode is consistent', () {
      const a = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      const b = ActiveDecoder(
        id: 'x',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 1,
      );
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ActiveDecoder — toString', () {
    test('contains id, decoderId, and instanceNumber', () {
      const d = ActiveDecoder(
        id: 'decoder_0',
        decoderId: 'spi',
        config: _config,
        instanceNumber: 2,
      );
      final s = d.toString();
      expect(s, contains('decoder_0'));
      expect(s, contains('spi'));
      expect(s, contains('2'));
    });
  });
}
