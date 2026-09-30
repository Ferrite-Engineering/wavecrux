// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Hand-written FFI bindings for the lxt2fst Rust crate.
//
// The exported symbols are documented in
// `native/lxt2fst/include/lxt2fst.h`; the constants below mirror its
// `LXT2FST_*` defines verbatim. Re-stating them here (rather than
// re-running ffigen) keeps the binding surface minimal — only the four
// functions the Dart-side converter actually invokes — and gives the
// code reader a single file to consult for "what does Dart call into?".
// If the crate's symbol shape changes, bump [lxt2fstAbiVersion] in
// `lxt2fst::ABI_VERSION` and bump the [expectedAbiVersion] constant on
// the Dart side; the converter checks at load time.

// ignore_for_file: non_constant_identifier_names, camel_case_types

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

// ── Error codes (mirror lxt2fst.h) ────────────────────────────────────────

const int kLxt2FstOk = 0;
const int kLxt2FstErrFileNotFound = 1;
const int kLxt2FstErrMagicMismatch = 2;
const int kLxt2FstErrTruncated = 3;
const int kLxt2FstErrWriteFailed = 4;
const int kLxt2FstErrOom = 5;
const int kLxt2FstErrUnsupported = 6;
const int kLxt2FstErrInternal = 7;
const int kLxt2FstErrInvalidArg = 8;

// ── Format-detection enum values ──────────────────────────────────────────

const int kLxt2FstFormatUnknown = 0;
const int kLxt2FstFormatLxt = 1;
const int kLxt2FstFormatLxt2 = 2;

// ── Native function signatures ────────────────────────────────────────────

typedef _LxtAbiVersionNative = ffi.Uint32 Function();
typedef _LxtAbiVersion = int Function();

typedef _LxtDetectFormatNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> head,
      ffi.UintPtr len,
    );
typedef _LxtDetectFormat = int Function(ffi.Pointer<ffi.Uint8> head, int len);

typedef Lxt2FstProgressCallback =
    ffi.Void Function(
      ffi.Uint64 done,
      ffi.Uint64 total,
      ffi.Pointer<ffi.Void> userData,
    );

typedef _LxtConvertNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Char> inPath,
      ffi.Pointer<ffi.Char> outPath,
      ffi.Pointer<ffi.NativeFunction<Lxt2FstProgressCallback>> progress,
      ffi.Pointer<ffi.Void> userData,
    );
typedef _LxtConvert =
    int Function(
      ffi.Pointer<ffi.Char> inPath,
      ffi.Pointer<ffi.Char> outPath,
      ffi.Pointer<ffi.NativeFunction<Lxt2FstProgressCallback>> progress,
      ffi.Pointer<ffi.Void> userData,
    );

typedef _LxtLastErrorNative = ffi.Pointer<ffi.Char> Function();
typedef _LxtLastError = ffi.Pointer<ffi.Char> Function();

/// Thin wrapper that resolves the lxt2fst C-ABI symbols on a loaded
/// [ffi.DynamicLibrary] and exposes typed Dart entry points.
///
/// One instance per dylib; cheap to construct (the symbol lookups are
/// `late`). Hand-rolled rather than ffigen-generated because only four
/// symbols are needed and the input header changes only when the crate's
/// ABI version is bumped.
class Lxt2FstBindings {
  Lxt2FstBindings(ffi.DynamicLibrary lib)
    : abiVersion = lib.lookupFunction<_LxtAbiVersionNative, _LxtAbiVersion>(
        'lxt2fst_abi_version',
      ),
      detectFormat = lib
          .lookupFunction<_LxtDetectFormatNative, _LxtDetectFormat>(
            'lxt2fst_detect_format',
          ),
      convert = lib.lookupFunction<_LxtConvertNative, _LxtConvert>(
        'lxt2fst_convert',
      ),
      lastErrorMessage = lib.lookupFunction<_LxtLastErrorNative, _LxtLastError>(
        'lxt2fst_last_error_message',
      );

  /// Returns the ABI version the loaded library was built against.
  final _LxtAbiVersion abiVersion;

  /// Returns one of [kLxt2FstFormatUnknown] / [kLxt2FstFormatLxt] /
  /// [kLxt2FstFormatLxt2]. Pure-Dart equivalent lives in
  /// [LegacyFormatDetector.detect].
  final _LxtDetectFormat detectFormat;

  /// Single-shot conversion entry point. See `lxt2fst.h` for the contract
  /// and error codes.
  final _LxtConvert convert;

  /// Static-lifetime English error message borrowed from the crate's
  /// per-thread last-error buffer. Valid until the next [convert] call on
  /// the same thread.
  final _LxtLastError lastErrorMessage;

  /// Dart-side decode of [lastErrorMessage]. Returns the empty string if
  /// the crate has no recorded error.
  String readLastError() {
    final ptr = lastErrorMessage();
    if (ptr.address == 0) return '';
    return ptr.cast<Utf8>().toDartString();
  }
}
