// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/features/viewer/providers/selected_transaction_provider.dart';

ProviderContainer _makeContainer() => ProviderContainer();

void main() {
  group('SelectedTransactionNotifier', () {
    test('initial state is null', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedTransactionProvider), isNull);
    });

    test('select() sets state to (transaction, decoderInstanceId)', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const tx = DecodedTransaction(
        startTime: 100,
        endTime: 300,
        label: 'Write 0xFF',
      );
      container
          .read(selectedTransactionProvider.notifier)
          .select(tx, 'decoder_0');

      final state = container.read(selectedTransactionProvider);
      expect(state, isNotNull);
      expect(state!.$1, equals(tx));
      expect(state.$2, equals('decoder_0'));
    });

    test('select() can be called multiple times — last call wins', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const tx1 = DecodedTransaction(startTime: 0, endTime: 100, label: 'A');
      const tx2 = DecodedTransaction(startTime: 200, endTime: 400, label: 'B');

      container
          .read(selectedTransactionProvider.notifier)
          .select(tx1, 'decoder_0');
      container
          .read(selectedTransactionProvider.notifier)
          .select(tx2, 'decoder_1');

      final state = container.read(selectedTransactionProvider);
      expect(state!.$1, equals(tx2));
      expect(state.$2, equals('decoder_1'));
    });

    test('clearSelection() resets state to null', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const tx = DecodedTransaction(
        startTime: 100,
        endTime: 300,
        label: 'Frame',
      );
      container
          .read(selectedTransactionProvider.notifier)
          .select(tx, 'decoder_0');

      container.read(selectedTransactionProvider.notifier).clearSelection();

      expect(container.read(selectedTransactionProvider), isNull);
    });

    test('clearSelection() is a no-op when already null', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      container.read(selectedTransactionProvider.notifier).clearSelection();

      expect(container.read(selectedTransactionProvider), isNull);
    });

    test('select() with error transaction stores isError flag', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const tx = DecodedTransaction(
        startTime: 100,
        endTime: 200,
        label: 'ERR',
        isError: true,
        errorMessage: 'Protocol violation',
      );
      container
          .read(selectedTransactionProvider.notifier)
          .select(tx, 'decoder_2');

      final state = container.read(selectedTransactionProvider)!;
      expect(state.$1.isError, isTrue);
      expect(state.$1.errorMessage, equals('Protocol violation'));
    });

    test('state change notifies listeners', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      var callCount = 0;
      container.listen(selectedTransactionProvider, (_, _) {
        callCount++;
      });

      const tx = DecodedTransaction(startTime: 0, endTime: 50, label: 'X');
      container
          .read(selectedTransactionProvider.notifier)
          .select(tx, 'decoder_0');
      container.read(selectedTransactionProvider.notifier).clearSelection();

      expect(callCount, equals(2));
    });

    test('select() stores full fields map', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const tx = DecodedTransaction(
        startTime: 0,
        endTime: 100,
        label: 'I2C Write',
        fields: {'address': '0x50', 'data': '0xFF', 'ack': 'ACK'},
      );
      container
          .read(selectedTransactionProvider.notifier)
          .select(tx, 'decoder_0');

      final stored = container.read(selectedTransactionProvider)!.$1;
      expect(stored.fields['address'], equals('0x50'));
      expect(stored.fields['data'], equals('0xFF'));
    });
  });
}
