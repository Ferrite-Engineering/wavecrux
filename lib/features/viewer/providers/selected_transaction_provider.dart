// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';

part 'selected_transaction_provider.g.dart';

/// The currently selected (highlighted) protocol-decoder transaction.
///
/// Set when the user taps a transaction block in the waveform canvas or
/// clicks a row in the transaction table.  The canvas and the transaction
/// table both watch this provider to synchronise their highlight state.
///
/// State is a record of `(transaction, decoderInstanceId)` or `null` when
/// nothing is selected.
@Riverpod(keepAlive: true)
class SelectedTransactionNotifier extends _$SelectedTransactionNotifier {
  @override
  (DecodedTransaction, String)? build() => null;

  /// Marks [transaction] (from the decoder instance identified by
  /// [decoderInstanceId]) as selected.
  void select(DecodedTransaction transaction, String decoderInstanceId) {
    state = (transaction, decoderInstanceId);
  }

  /// Clears the current selection.
  void clearSelection() {
    state = null;
  }
}
