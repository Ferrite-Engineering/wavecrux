// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shared types for [Lxt2FstConverter]. Pulled into its own file so the
// stub, io, and web implementations can each import it without forming a
// cycle through the conditional-export shim.

import 'package:flutter/foundation.dart';

/// A single progress update during an LXT/LXT2 → FST conversion.
///
/// Units depend on the source format and are documented on the
/// `lxt2fst_progress_fn` typedef in `native/lxt2fst/include/lxt2fst.h`:
///   * LXT2 — `(blocks_done, total_blocks)`
///   * LXT  — `(bytes_consumed, total_size)`
///
/// `done == total` is guaranteed for the final progress event before the
/// progress stream closes successfully.
@immutable
class ConversionProgress {
  const ConversionProgress({required this.done, required this.total});

  /// Number of units of work completed so far.
  final int done;

  /// Total number of units of work in the conversion.
  final int total;

  /// Fractional progress in the range `[0, 1]`. Returns `0` when [total] is
  /// `0` (the header has not yet been parsed and the total is unknown).
  double get fraction => total == 0 ? 0 : done / total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversionProgress && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);

  @override
  String toString() => 'ConversionProgress(done: $done, total: $total)';
}

/// Error raised by [Lxt2FstConverter] when the underlying conversion fails.
///
/// [code] mirrors the `LXT2FST_*` error constants in
/// `native/lxt2fst/include/lxt2fst.h`; [message] is the human-readable
/// description the crate's `lxt2fst_last_error_message` returned.
@immutable
class Lxt2FstConverterException implements Exception {
  const Lxt2FstConverterException({required this.code, required this.message});

  /// The numeric `LXT2FST_*` error code returned by the converter.
  final int code;

  /// English description of the failure.
  final String message;

  @override
  String toString() =>
      'Lxt2FstConverterException(code: $code, message: $message)';
}
