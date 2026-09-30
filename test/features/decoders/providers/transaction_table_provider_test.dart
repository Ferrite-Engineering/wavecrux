// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

const _config = DecoderConfig(signalBindings: {});

DecoderDefinition _def(String id, String name) => DecoderDefinition(
  id: id,
  displayName: name,
  description: '',
  requiredSignals: const [],
);

DecodedTransaction _tx(
  int start,
  int end,
  String label, {
  Map<String, String> fields = const {},
  bool isError = false,
}) => DecodedTransaction(
  startTime: start,
  endTime: end,
  label: label,
  fields: fields,
  isError: isError,
);

ActiveDecoder _decoder(
  String id,
  String decoderId,
  List<DecodedTransaction> transactions, {
  int instanceNumber = 1,
}) => ActiveDecoder(
  id: id,
  decoderId: decoderId,
  config: _config,
  instanceNumber: instanceNumber,
  transactions: transactions,
);

/// Creates a container with an explicit list of [ActiveDecoder]s pre-loaded.
ProviderContainer _makeContainer(List<ActiveDecoder> decoders) {
  final container = ProviderContainer(
    overrides: [
      activeDecodersProvider.overrideWith(
        () => _FixedDecodersNotifier(decoders),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _FixedDecodersNotifier extends ActiveDecodersNotifier {
  _FixedDecodersNotifier(this._initial);
  final List<ActiveDecoder> _initial;
  @override
  List<ActiveDecoder> build() => _initial;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(DecoderRegistry.instance.clear);
  tearDown(DecoderRegistry.instance.clear);

  // ── TransactionTableFilter ─────────────────────────────────────────────────

  group('TransactionTableFilter', () {
    test('default values', () {
      const f = TransactionTableFilter();
      expect(f.decoderIdFilter, isNull);
      expect(f.searchQuery, '');
      expect(f.sortColumn, TransactionSortColumn.rowNumber);
      expect(f.sortAscending, isTrue);
    });

    test('equality', () {
      const a = TransactionTableFilter(searchQuery: 'spi');
      const b = TransactionTableFilter(searchQuery: 'spi');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on any field', () {
      const base = TransactionTableFilter();
      expect(
        base,
        isNot(const TransactionTableFilter(searchQuery: 'x')),
      );
      expect(
        base,
        isNot(
          const TransactionTableFilter(
            sortColumn: TransactionSortColumn.decoder,
          ),
        ),
      );
      expect(
        base,
        isNot(const TransactionTableFilter(sortAscending: false)),
      );
      expect(
        base,
        isNot(const TransactionTableFilter(decoderIdFilter: 'd1')),
      );
    });

    test('copyWith preserves unchanged fields', () {
      const f = TransactionTableFilter(
        decoderIdFilter: 'dec_0',
        searchQuery: 'abc',
        sortColumn: TransactionSortColumn.label,
        sortAscending: false,
      );
      final copy = f.copyWith(searchQuery: 'xyz');
      expect(copy.decoderIdFilter, 'dec_0');
      expect(copy.searchQuery, 'xyz');
      expect(copy.sortColumn, TransactionSortColumn.label);
      expect(copy.sortAscending, isFalse);
    });

    test('copyWith can clear decoderIdFilter to null', () {
      const f = TransactionTableFilter(decoderIdFilter: 'dec_0');
      final copy = f.copyWith(decoderIdFilter: null);
      expect(copy.decoderIdFilter, isNull);
    });
  });

  // ── TableTransaction ───────────────────────────────────────────────────────

  group('TableTransaction', () {
    test('equality and hashCode', () {
      final tx = _tx(0, 10, 'Write 0xFF');
      final a = TableTransaction(
        rowIndex: 1,
        decoderInstanceId: 'dec_0',
        decoderDisplayName: 'SPI',
        transaction: tx,
      );
      final b = TableTransaction(
        rowIndex: 1,
        decoderInstanceId: 'dec_0',
        decoderDisplayName: 'SPI',
        transaction: tx,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes label', () {
      final t = TableTransaction(
        rowIndex: 3,
        decoderInstanceId: 'dec_0',
        decoderDisplayName: 'I2C',
        transaction: _tx(0, 5, 'Read 0x50'),
      );
      expect(t.toString(), contains('Read 0x50'));
    });
  });

  // ── TransactionTableFilterNotifier ────────────────────────────────────────

  group('TransactionTableFilterNotifier', () {
    test('initial state is default filter', () {
      final c = _makeContainer([]);
      final f = c.read(transactionTableFilterProvider);
      expect(f, const TransactionTableFilter());
    });

    test('setSearchQuery updates query', () {
      final c = _makeContainer([]);
      c.read(transactionTableFilterProvider.notifier).setSearchQuery('uart');
      expect(
        c.read(transactionTableFilterProvider).searchQuery,
        'uart',
      );
    });

    test('setDecoderFilter sets decoder ID', () {
      final c = _makeContainer([]);
      c.read(transactionTableFilterProvider.notifier).setDecoderFilter('dec_0');
      expect(
        c.read(transactionTableFilterProvider).decoderIdFilter,
        'dec_0',
      );
    });

    test('setDecoderFilter with null clears filter', () {
      final c = _makeContainer([]);
      c.read(transactionTableFilterProvider.notifier)
        ..setDecoderFilter('dec_0')
        ..setDecoderFilter(null);
      expect(
        c.read(transactionTableFilterProvider).decoderIdFilter,
        isNull,
      );
    });

    test('setSortColumn to new column resets to ascending', () {
      final c = _makeContainer([]);
      c
          .read(transactionTableFilterProvider.notifier)
          .setSortColumn(TransactionSortColumn.startTime);
      final f = c.read(transactionTableFilterProvider);
      expect(f.sortColumn, TransactionSortColumn.startTime);
      expect(f.sortAscending, isTrue);
    });

    test('setSortColumn on same column reverses direction', () {
      final c = _makeContainer([]);
      c.read(transactionTableFilterProvider.notifier)
        ..setSortColumn(TransactionSortColumn.label)
        ..setSortColumn(TransactionSortColumn.label);
      final f = c.read(transactionTableFilterProvider);
      expect(f.sortColumn, TransactionSortColumn.label);
      expect(f.sortAscending, isFalse);
    });

    test('setSortColumnAndDirection sets both fields', () {
      final c = _makeContainer([]);
      c
          .read(transactionTableFilterProvider.notifier)
          .setSortColumnAndDirection(
            TransactionSortColumn.endTime,
            ascending: false,
          );
      final f = c.read(transactionTableFilterProvider);
      expect(f.sortColumn, TransactionSortColumn.endTime);
      expect(f.sortAscending, isFalse);
    });

    test('reset returns to default', () {
      final c = _makeContainer([]);
      c.read(transactionTableFilterProvider.notifier)
        ..setSearchQuery('foo')
        ..setDecoderFilter('dec_0')
        ..setSortColumn(TransactionSortColumn.endTime)
        ..reset();
      expect(
        c.read(transactionTableFilterProvider),
        const TransactionTableFilter(),
      );
    });
  });

  // ── filteredTransactionsProvider ──────────────────────────────────────────

  group('filteredTransactionsProvider', () {
    test('empty when no decoders', () {
      final c = _makeContainer([]);
      expect(c.read(filteredTransactionsProvider), isEmpty);
    });

    test('flattens transactions from multiple decoders with 1-based index', () {
      DecoderRegistry.instance
        ..register(_def('spi', 'SPI'), (_) => throw UnimplementedError())
        ..register(_def('uart', 'UART'), (_) => throw UnimplementedError());

      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(0, 10, 'Write 0xFF'),
          _tx(20, 30, 'Read'),
        ]),
        _decoder('dec_1', 'uart', [_tx(50, 60, 'Frame A')]),
      ]);

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 3);
      expect(rows[0].rowIndex, 1);
      expect(rows[0].decoderDisplayName, 'SPI #1');
      expect(rows[1].rowIndex, 2);
      expect(rows[2].rowIndex, 3);
      expect(rows[2].decoderDisplayName, 'UART #1');
    });

    test('uses decoderId as display name when registry has no definition', () {
      final c = _makeContainer([
        _decoder('dec_0', 'mystery_decoder', [_tx(0, 10, 'Foo')]),
      ]);
      final rows = c.read(filteredTransactionsProvider);
      expect(rows.single.decoderDisplayName, 'mystery_decoder #1');
    });

    test('filter by decoderIdFilter', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [_tx(0, 10, 'A'), _tx(20, 30, 'B')]),
        _decoder('dec_1', 'uart', [_tx(50, 60, 'C')]),
      ]);
      c.read(transactionTableFilterProvider.notifier).setDecoderFilter('dec_1');

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 1);
      expect(rows.single.decoderInstanceId, 'dec_1');
    });

    test('search filters by label (case-insensitive)', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(0, 10, 'Write 0xFF'),
          _tx(20, 30, 'Read 0x50'),
        ]),
      ]);
      c.read(transactionTableFilterProvider.notifier).setSearchQuery('write');

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 1);
      expect(rows.single.transaction.label, 'Write 0xFF');
    });

    test('search filters by field value', () {
      final c = _makeContainer([
        _decoder('dec_0', 'i2c', [
          _tx(0, 10, 'Transfer', fields: {'address': '0x50', 'rw': 'W'}),
          _tx(20, 30, 'Transfer', fields: {'address': '0x48', 'rw': 'R'}),
        ]),
      ]);
      c.read(transactionTableFilterProvider.notifier).setSearchQuery('0x50');

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 1);
      expect(rows.single.transaction.fields['address'], '0x50');
    });

    test('search filters by decoder display name', () {
      DecoderRegistry.instance.register(
        _def('axi', 'AXI4-Lite'),
        (_) => throw UnimplementedError(),
      );
      final c = _makeContainer([
        _decoder('dec_0', 'axi', [_tx(0, 10, 'Write'), _tx(20, 30, 'Read')]),
      ]);
      c.read(transactionTableFilterProvider.notifier).setSearchQuery('axi4');

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 2);
    });

    test('empty search query returns all', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [_tx(0, 10, 'A'), _tx(20, 30, 'B')]),
      ]);
      c.read(transactionTableFilterProvider.notifier).setSearchQuery('  ');

      expect(c.read(filteredTransactionsProvider).length, 2);
    });

    test('sort by startTime ascending', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(30, 40, 'C'),
          _tx(10, 20, 'A'),
          _tx(20, 30, 'B'),
        ]),
      ]);
      c
          .read(transactionTableFilterProvider.notifier)
          .setSortColumn(TransactionSortColumn.startTime);

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.map((r) => r.transaction.startTime).toList(), [10, 20, 30]);
    });

    test('sort by startTime descending', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(10, 20, 'A'),
          _tx(30, 40, 'C'),
          _tx(20, 30, 'B'),
        ]),
      ]);
      c.read(transactionTableFilterProvider.notifier)
        ..setSortColumn(TransactionSortColumn.startTime)
        ..setSortColumn(
          TransactionSortColumn.startTime,
        ); // second click → descending

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.map((r) => r.transaction.startTime).toList(), [30, 20, 10]);
    });

    test('sort by endTime', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(0, 50, 'long'),
          _tx(0, 10, 'short'),
          _tx(0, 30, 'mid'),
        ]),
      ]);
      c
          .read(transactionTableFilterProvider.notifier)
          .setSortColumn(TransactionSortColumn.endTime);

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.map((r) => r.transaction.endTime).toList(), [10, 30, 50]);
    });

    test('sort by label', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(0, 10, 'Zebra'),
          _tx(0, 10, 'Alpha'),
          _tx(0, 10, 'Mango'),
        ]),
      ]);
      c
          .read(transactionTableFilterProvider.notifier)
          .setSortColumn(TransactionSortColumn.label);

      final rows = c.read(filteredTransactionsProvider);
      expect(
        rows.map((r) => r.transaction.label).toList(),
        ['Alpha', 'Mango', 'Zebra'],
      );
    });

    test('sort by decoder name across multiple decoders', () {
      DecoderRegistry.instance
        ..register(_def('spi', 'SPI'), (_) => throw UnimplementedError())
        ..register(_def('uart', 'UART'), (_) => throw UnimplementedError())
        ..register(_def('i2c', 'I2C'), (_) => throw UnimplementedError());

      final c = _makeContainer([
        _decoder('dec_0', 'spi', [_tx(0, 10, 'A')]),
        _decoder('dec_1', 'uart', [_tx(0, 10, 'B')]),
        _decoder('dec_2', 'i2c', [_tx(0, 10, 'C')]),
      ]);
      c
          .read(transactionTableFilterProvider.notifier)
          .setSortColumn(TransactionSortColumn.decoder);

      final rows = c.read(filteredTransactionsProvider);
      expect(
        rows.map((r) => r.decoderDisplayName).toList(),
        ['I2C #1', 'SPI #1', 'UART #1'],
      );
    });

    test('sort by rowNumber (default) preserves insertion order', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(30, 40, 'C'),
          _tx(10, 20, 'A'),
        ]),
      ]);

      final rows = c.read(filteredTransactionsProvider);
      expect(rows[0].rowIndex, 1);
      expect(rows[0].transaction.label, 'C');
      expect(rows[1].rowIndex, 2);
      expect(rows[1].transaction.label, 'A');
    });

    test('error transactions are included without special filtering', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [
          _tx(0, 10, 'OK'),
          _tx(20, 30, 'NACK', isError: true),
        ]),
      ]);

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 2);
      expect(rows.last.transaction.isError, isTrue);
    });

    test('combined decoder-filter and search query', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', [_tx(0, 10, 'Write 0xFF')]),
        _decoder('dec_1', 'uart', [_tx(0, 10, 'Write 0xFF')]),
      ]);
      c.read(transactionTableFilterProvider.notifier)
        ..setDecoderFilter('dec_0')
        ..setSearchQuery('write');

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 1);
      expect(rows.single.decoderInstanceId, 'dec_0');
    });

    test('decoder with no transactions contributes zero rows', () {
      final c = _makeContainer([
        _decoder('dec_0', 'spi', []),
        _decoder('dec_1', 'uart', [_tx(0, 10, 'Frame')]),
      ]);

      final rows = c.read(filteredTransactionsProvider);
      expect(rows.length, 1);
      expect(rows.single.decoderInstanceId, 'dec_1');
    });
  });
}
