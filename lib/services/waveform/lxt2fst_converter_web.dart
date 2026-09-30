// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Web [Lxt2FstConverter] implementation.
//
// Mirrors `wellen_wasm_provider_web.dart`'s shape: a tiny `dart:js_interop`
// surface plus a hand-written JS shim that wires the `lxt2fst` wasm-bindgen
// module onto `globalThis.waveCruxLxt2Fst`. The shim is necessary because
// `dart:js_interop` cannot dynamically import an ES module at runtime; the
// shim wraps the dynamic import and republishes the bindings under a stable
// global. The web build runs the conversion synchronously on the main
// thread (no Workers: threads would need SharedArrayBuffer and
// cross-origin-isolation headers the web build does without) — for an LXT2 archive small enough to fit in browser memory this
// is acceptable, and the progress callback gives the UI a chance to repaint
// between blocks.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

export 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

// ── JS interop shape ──────────────────────────────────────────────────────

@JS('waveCruxLxt2Fst')
external _Lxt2FstLoader? get _waveCruxLxt2Fst;

extension type _Lxt2FstLoader._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> ensureReady();
  external JSUint8Array convert(JSUint8Array input, JSFunction? progress);
  external int abiVersion();
}

/// Web [Lxt2FstConverter] backed by the `lxt2fst` wasm-bindgen module.
class Lxt2FstConverter {
  /// Web constructor accepts (and ignores) the same argument shape as the
  /// io implementation so callers compile uniformly.
  // ignore: avoid_unused_constructor_parameters
  Lxt2FstConverter({@visibleForTesting Object? libraryOpener});

  @visibleForTesting
  static const int expectedAbiVersion = 1;

  static Future<void>? _initFuture;
  static Object? _loadError;

  /// Idempotently load the WASM module and verify its ABI version.
  Future<void> ensureLoaded() {
    if (_loadError != null) {
      return Future<void>.error(_loadError!);
    }
    _initFuture ??= _ensureLoaded();
    return _initFuture!;
  }

  static Future<void> _ensureLoaded() async {
    try {
      final loader = _waveCruxLxt2Fst;
      if (loader == null) {
        throw const Lxt2FstConverterException(
          code: kInternalCode,
          message:
              'lxt2fst loader not present on globalThis — the JS shim is '
              'missing from the web bundle.',
        );
      }
      final result = await loader.ensureReady().toDart;
      if (result != null) {
        throw Lxt2FstConverterException(
          code: kInternalCode,
          message: 'lxt2fst module failed to load: $result',
        );
      }
      final version = loader.abiVersion();
      if (version != expectedAbiVersion) {
        throw Lxt2FstConverterException(
          code: kInternalCode,
          message:
              'lxt2fst ABI mismatch: Dart expected $expectedAbiVersion but '
              'wasm reports $version',
        );
      }
    } on Object catch (e) {
      _loadError = e;
      rethrow;
    }
  }

  /// Path-based conversion is desktop/mobile-only — the web build has no
  /// filesystem and uses [convertBytes] instead.
  Stream<ConversionProgress> convertPath({
    required String inPath,
    required String outPath,
  }) {
    return Stream<ConversionProgress>.error(
      UnsupportedError(
        'Lxt2FstConverter.convertPath is not available on web; use '
        'convertBytes with bytes from the browser file picker.',
      ),
    );
  }

  /// Convert an in-memory LXT/LXT2 buffer to FST bytes.
  ///
  /// Runs synchronously on the main thread.
  /// [onProgress] is invoked inline from the WASM side at the same 50 ms / 1 %
  /// cadence as the C-ABI callback; this gives the surrounding UI a chance
  /// to repaint between blocks.
  Future<Uint8List> convertBytes(
    Uint8List input, {
    void Function(int done, int total)? onProgress,
  }) async {
    await ensureLoaded();
    final loader = _waveCruxLxt2Fst;
    if (loader == null) {
      throw const Lxt2FstConverterException(
        code: kInternalCode,
        message: 'lxt2fst loader disappeared after ensureLoaded',
      );
    }
    JSFunction? progressJs;
    if (onProgress != null) {
      progressJs = ((JSNumber done, JSNumber total) {
        onProgress(done.toDartInt, total.toDartInt);
      }).toJS;
    }
    try {
      final result = loader.convert(input.toJS, progressJs);
      return result.toDart;
    } on Object catch (e) {
      throw Lxt2FstConverterException(
        code: kInternalCode,
        message: 'lxt2fst convert failed: $e',
      );
    }
  }

  /// Force-resets internal init state. Test-only.
  @visibleForTesting
  static void resetInitForTests() {
    _initFuture = null;
    _loadError = null;
  }
}

// Internal alias so we don't pull the kLxt2FstErrInternal constant through
// the FFI-only bindings file on the web build (which has no `dart:ffi`).
const int kInternalCode = 7;
