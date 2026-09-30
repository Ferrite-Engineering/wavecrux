// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The production loaders resolve the LXT/LXT2 converter from the wellen FFI
// library.
//
// Every platform bundles exactly one native library, libwellen_ffi, and the
// Rust `wellen_ffi` crate links `lxt2fst` so that library exports the
// converter's `lxt2fst_*` C ABI next to `wellen_*`. These tests pin both halves
// of that contract: the converter's loader asks for the wellen library (never
// a standalone `liblxt2fst`, which no build produces), and the library the
// shared resolver opens really carries every symbol the Dart bindings look up.

@TestOn('vm')
library;

import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/native/bindings/lxt2fst_bindings.dart';
import 'package:wavecrux/native/wellen_ffi_library_io.dart';
// Imported directly, not through the conditional lxt2fst_converter.dart
// export: static analysis resolves that to the stub, which has no FFI surface.
import 'package:wavecrux/services/waveform/lxt2fst_converter_io.dart';

import '../helpers/wellen_ffi_library_gate.dart';

/// Every symbol `Lxt2FstBindings` resolves (see `lxt2fst.h`).
const _lxt2fstSymbols = [
  'lxt2fst_abi_version',
  'lxt2fst_detect_format',
  'lxt2fst_convert',
  'lxt2fst_last_error_message',
];

void main() {
  test(
    'the converter asks for the wellen FFI library, never liblxt2fst',
    () async {
      final requested = <String>[];
      final converter = Lxt2FstConverter(
        libraryOpener: (path) {
          requested.add(path);
          throw ArgumentError('not loading $path in this test');
        },
      );

      await expectLater(
        converter.ensureLoaded(),
        throwsA(isA<Lxt2FstConverterException>()),
      );

      expect(requested, isNotEmpty);
      expect(requested.first, wellenFfiLibraryFileName());
      for (final path in requested) {
        expect(path, endsWith(wellenFfiLibraryFileName()));
        expect(path, isNot(contains('lxt2fst')));
      }
    },
  );

  if (!requireWellenFfiLibrary('wellen FFI library exports')) return;

  test('the shared resolver opens a library exporting wellen_* and '
      'lxt2fst_*', () {
    final lib = openWellenFfiLibrary();
    expect(lib.providesSymbol('wellen_open'), isTrue);
    expect(lib.providesSymbol('wellen_last_open_error'), isTrue);
    for (final symbol in _lxt2fstSymbols) {
      expect(
        lib.providesSymbol(symbol),
        isTrue,
        reason: '$symbol missing — is native/lxt2fst linked into wellen_ffi?',
      );
    }
    expect(
      Lxt2FstBindings(lib).abiVersion(),
      Lxt2FstConverter.expectedAbiVersion,
    );
  });

  test('the converter loads through the production opener', () async {
    final opened = <String>[];
    final converter = Lxt2FstConverter(
      libraryOpener: (path) {
        final lib = ffi.DynamicLibrary.open(path);
        opened.add(path);
        return lib;
      },
    );

    await converter.ensureLoaded();

    expect(opened, hasLength(1));
    expect(opened.single, endsWith(wellenFfiLibraryFileName()));
  });
}
