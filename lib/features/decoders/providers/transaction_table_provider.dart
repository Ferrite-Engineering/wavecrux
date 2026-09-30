// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

part 'transaction_table_provider.g.dart';

/// Columns the transaction table can be sorted by.
enum TransactionSortColumn { rowNumber, decoder, startTime, endTime, label }

/// Filter and sort state for [TransactionTablePanel].
@immutable
class TransactionTableFilter {
  const TransactionTableFilter({
    this.decoderIdFilter,
    this.searchQuery = '',
    this.sortColumn = TransactionSortColumn.rowNumber,
    this.sortAscending = true,
  });

  /// Only show transactions from this decoder instance ID, or null for all.
  final String? decoderIdFilter;

  /// Case-insensitive substring searched across [DecodedTransaction.label],
  /// the decoder display name, and all [DecodedTransaction.fields] values.
  final String searchQuery;

  final TransactionSortColumn sortColumn;
  final bool sortAscending;

  TransactionTableFilter copyWith({
    Object? decoderIdFilter = _kUnset,
    String? searchQuery,
    TransactionSortColumn? sortColumn,
    bool? sortAscending,
  }) {
    return TransactionTableFilter(
      decoderIdFilter: identical(decoderIdFilter, _kUnset)
          ? this.decoderIdFilter
          : decoderIdFilter as String?,
      searchQuery: searchQuery ?? this.searchQuery,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransactionTableFilter &&
        other.decoderIdFilter == decoderIdFilter &&
        other.searchQuery == searchQuery &&
        other.sortColumn == sortColumn &&
        other.sortAscending == sortAscending;
  }

  @override
  int get hashCode =>
      Object.hash(decoderIdFilter, searchQuery, sortColumn, sortAscending);

  static const Object _kUnset = Object();
}

/// A [DecodedTransaction] enriched with decoder-instance context for display.
@immutable
class TableTransaction {
  const TableTransaction({
    required this.rowIndex,
    required this.decoderInstanceId,
    required this.decoderDisplayName,
    required this.transaction,
  });

  /// 1-based sequential number before any filter or sort is applied.
  final int rowIndex;

  /// The [ActiveDecoder.id] that produced this transaction.
  final String decoderInstanceId;

  /// Human-readable decoder name (from [DecoderDefinition.displayName]).
  final String decoderDisplayName;

  final DecodedTransaction transaction;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableTransaction &&
        other.rowIndex == rowIndex &&
        other.decoderInstanceId == decoderInstanceId &&
        other.decoderDisplayName == decoderDisplayName &&
        other.transaction == transaction;
  }

  @override
  int get hashCode =>
      Object.hash(rowIndex, decoderInstanceId, decoderDisplayName, transaction);

  @override
  String toString() =>
      'TableTransaction(row: $rowIndex, decoder: $decoderDisplayName, '
      'label: "${transaction.label}")';
}

/// Manages the transaction table's filter, search, and sort state.
///
/// keepAlive so the filter persists when the panel is hidden and reshown.
@Riverpod(keepAlive: true)
class TransactionTableFilterNotifier extends _$TransactionTableFilterNotifier {
  @override
  TransactionTableFilter build() => const TransactionTableFilter();

  /// Sets the decoder instance ID filter. Pass `null` to show all decoders.
  void setDecoderFilter(String? decoderId) {
    state = state.copyWith(decoderIdFilter: decoderId);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Changes the sort column.  If [column] is already the active sort column,
  /// the sort direction is reversed.  Otherwise it resets to ascending.
  void setSortColumn(TransactionSortColumn column) {
    if (state.sortColumn == column) {
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      state = state.copyWith(sortColumn: column, sortAscending: true);
    }
  }

  /// Sets both sort column and direction explicitly (used by DataTable.onSort).
  void setSortColumnAndDirection(
    TransactionSortColumn column, {
    required bool ascending,
  }) {
    state = state.copyWith(sortColumn: column, sortAscending: ascending);
  }

  void reset() => state = const TransactionTableFilter();
}

/// All transactions from all active decoders, flattened, filtered, and sorted
/// according to [TransactionTableFilterNotifier].
///
/// Recomputes whenever [activeDecodersProvider] state changes or the
/// filter state changes.
@riverpod
List<TableTransaction> filteredTransactions(Ref ref) {
  final decoders = ref.watch(activeDecodersProvider);
  final filter = ref.watch(transactionTableFilterProvider);

  // 1. Flatten all transactions with decoder context and 1-based row indices.
  var index = 1;
  final all = <TableTransaction>[];
  for (final decoder in decoders) {
    final definition = DecoderRegistry.instance.getDefinition(
      decoder.decoderId,
    );
    final baseName = definition?.displayName ?? decoder.decoderId;
    final displayName = decoder.instanceLabel(baseName);
    for (final tx in decoder.transactions) {
      all.add(
        TableTransaction(
          rowIndex: index++,
          decoderInstanceId: decoder.id,
          decoderDisplayName: displayName,
          transaction: tx,
        ),
      );
    }
  }

  // 2. Apply decoder instance filter.
  var rows = filter.decoderIdFilter != null
      ? all.where((t) => t.decoderInstanceId == filter.decoderIdFilter)
      : all;

  // 3. Apply search query across label, decoder name, and all field values.
  final query = filter.searchQuery.trim().toLowerCase();
  if (query.isNotEmpty) {
    rows = rows.where((t) {
      if (t.transaction.label.toLowerCase().contains(query)) return true;
      if (t.decoderDisplayName.toLowerCase().contains(query)) return true;
      return t.transaction.fields.values.any(
        (v) => v.toLowerCase().contains(query),
      );
    });
  }

  // 4. Sort, preserving stable order on equal keys via index.
  final sorted = rows.toList()
    ..sort((a, b) {
      final cmp = switch (filter.sortColumn) {
        TransactionSortColumn.rowNumber => a.rowIndex.compareTo(b.rowIndex),
        TransactionSortColumn.decoder => a.decoderDisplayName.compareTo(
          b.decoderDisplayName,
        ),
        TransactionSortColumn.startTime => a.transaction.startTime.compareTo(
          b.transaction.startTime,
        ),
        TransactionSortColumn.endTime => a.transaction.endTime.compareTo(
          b.transaction.endTime,
        ),
        TransactionSortColumn.label => a.transaction.label.compareTo(
          b.transaction.label,
        ),
      };
      return filter.sortAscending ? cmp : -cmp;
    });

  return sorted;
}
