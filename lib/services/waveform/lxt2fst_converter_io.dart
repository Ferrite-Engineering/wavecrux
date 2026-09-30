// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Desktop/mobile [Lxt2FstConverter] implementation.
//
// The `lxt2fst_*` C ABI ships inside the wellen FFI library — the Rust
// `wellen_ffi` crate links `lxt2fst` — so it is opened with the same
// resolver as the parser (`openWellenFfiLibrary`) and is present wherever
// wellen is: bundled in every desktop and Android build, statically linked
// on iOS, and at `native/wellen_ffi/target/` under `flutter test`.
//
// Each `convertPath` call spawns a one-shot background isolate that:
//   1. Resolves and loads the wellen FFI library.
//   2. Wires a `NativeCallable.isolateLocal` progress callback that
//      forwards `(done, total)` over a SendPort to the calling isolate.
//   3. Invokes `lxt2fst_convert`. The call is synchronous from the FFI
//      side; while it runs the worker pumps progress events through the
//      port.
//   4. Sends a terminal `_DoneMsg` or `_ErrorMsg` and exits.
//
// The Dart side returns a broadcast-style [Stream] backed by a
// [StreamController] that the receive-port handler drives. If the
// subscription is cancelled mid-conversion, the isolate is killed and the
// partial `outPath` is best-effort removed — cancellation mid-conversion
// produces no output file.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'package:wavecrux/native/bindings/lxt2fst_bindings.dart';
import 'package:wavecrux/native/wellen_ffi_library_io.dart';
import 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

export 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

/// Hook so tests can stub [ffi.DynamicLibrary.open] without touching the
/// real filesystem-probe + dlopen path. Mirrors `DynamicLibraryOpener` in
/// `ffi_decoder_loader_io.dart`.
typedef Lxt2FstLibraryOpener = WellenFfiLibraryOpener;

ffi.DynamicLibrary _defaultOpener(String path) => ffi.DynamicLibrary.open(path);

/// Production [Lxt2FstConverter] backed by the native `lxt2fst` crate, as
/// linked into the wellen FFI library.
///
/// Stateless apart from the (lazily resolved) [Lxt2FstBindings] cache.
/// Each [convertPath] call is independent — there is no cross-call
/// state — so a single instance is safe to share across the whole app.
class Lxt2FstConverter {
  Lxt2FstConverter({Lxt2FstLibraryOpener? libraryOpener})
    : _opener = libraryOpener ?? _defaultOpener;

  /// ABI version this Dart side built against. The native [ABI_VERSION]
  /// constant in `lxt2fst::lib.rs` must match. Bumping one without bumping
  /// the other trips the load-time check in [ensureLoaded].
  @visibleForTesting
  static const int expectedAbiVersion = 1;

  final Lxt2FstLibraryOpener _opener;

  Lxt2FstBindings? _bindings;

  /// Loads the native library and verifies its ABI version. Cached after the
  /// first call. Throws [Lxt2FstConverterException] on failure (library not
  /// found, ABI mismatch, etc.).
  Future<void> ensureLoaded() async {
    if (_bindings != null) return;
    try {
      final lib = openWellenFfiLibrary(opener: _opener);
      final bindings = Lxt2FstBindings(lib);
      final version = bindings.abiVersion();
      if (version != expectedAbiVersion) {
        throw Lxt2FstConverterException(
          code: kLxt2FstErrInternal,
          message:
              'lxt2fst ABI version mismatch: Dart expected $expectedAbiVersion '
              'but library reports $version',
        );
      }
      _bindings = bindings;
    } on Lxt2FstConverterException {
      rethrow;
    } on Object catch (e) {
      throw Lxt2FstConverterException(
        code: kLxt2FstErrInternal,
        message: 'failed to load the lxt2fst converter from wellen_ffi: $e',
      );
    }
  }

  /// Convert the LXT/LXT2 file at [inPath] to FST at [outPath].
  ///
  /// Emits a stream of [ConversionProgress] events as the conversion runs.
  /// The terminal event satisfies `done == total` and the stream closes
  /// without an error. Failures surface as a [Lxt2FstConverterException]
  /// emitted via the stream's error channel before close.
  ///
  /// Cancelling the subscription kills the worker isolate and best-effort
  /// removes [outPath].
  Stream<ConversionProgress> convertPath({
    required String inPath,
    required String outPath,
  }) {
    late StreamController<ConversionProgress> controller;
    final receivePort = ReceivePort();
    Isolate? isolate;
    var cancelled = false;
    // Set once the conversion reaches a terminal state (success or error).
    // Distinguishes a genuine mid-conversion cancel (must delete any partial
    // output) from the subscription's *natural* cancellation after the
    // stream completes — e.g. `await stream.last` cancels its subscription
    // once it has the final event, which fires [onCancel]. Without this
    // guard that post-completion cancel would delete the FST the conversion
    // just successfully produced.
    var finished = false;

    Future<void> cleanup() async {
      try {
        final f = File(outPath);
        if (f.existsSync()) await f.delete();
      } on Object {
        // Best-effort: ignore cleanup failures.
      }
    }

    Future<void> start() async {
      try {
        await ensureLoaded();
      } on Lxt2FstConverterException catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          unawaited(controller.close());
        }
        receivePort.close();
        return;
      }
      try {
        isolate = await Isolate.spawn<_WorkerArgs>(
          _convertWorkerEntry,
          _WorkerArgs(
            mainPort: receivePort.sendPort,
            inPath: inPath,
            outPath: outPath,
          ),
          debugName: 'lxt2fst-convert',
        );
      } on Object catch (e) {
        if (!controller.isClosed) {
          controller.addError(
            Lxt2FstConverterException(
              code: kLxt2FstErrInternal,
              message: 'failed to spawn lxt2fst worker isolate: $e',
            ),
          );
          unawaited(controller.close());
        }
        receivePort.close();
      }
    }

    receivePort.listen((msg) async {
      if (cancelled || controller.isClosed) return;
      if (msg is _ProgressMsg) {
        controller.add(ConversionProgress(done: msg.done, total: msg.total));
      } else if (msg is _DoneMsg) {
        // Mark finished *before* closing so the subscription's natural
        // cancel-on-done does not trip the [onCancel] cleanup below.
        finished = true;
        await controller.close();
        receivePort.close();
        isolate?.kill(priority: Isolate.immediate);
      } else if (msg is _ErrorMsg) {
        finished = true;
        controller.addError(
          Lxt2FstConverterException(code: msg.code, message: msg.message),
        );
        await controller.close();
        // The conversion failed: remove any partial output here. The
        // post-close cancel then skips cleanup (finished == true).
        await cleanup();
        receivePort.close();
        isolate?.kill(priority: Isolate.immediate);
      }
    });

    controller = StreamController<ConversionProgress>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        cancelled = true;
        isolate?.kill(priority: Isolate.immediate);
        receivePort.close();
        // Only delete the output for a genuine mid-conversion cancel. After
        // the stream has completed (success or error), the output is either
        // the finished FST or was already removed by the error handler —
        // either way it must not be deleted here.
        if (!finished) await cleanup();
      },
    );

    return controller.stream;
  }

  /// Byte-based conversion is web-only — desktop / mobile builds always
  /// have a real filesystem and use [convertPath] instead.
  Future<Uint8List> convertBytes(
    Uint8List input, {
    void Function(int done, int total)? onProgress,
  }) {
    throw UnsupportedError(
      'Lxt2FstConverter.convertBytes is web-only; use convertPath on '
      'desktop/mobile.',
    );
  }
}

// ── Isolate worker ──────────────────────────────────────────────────────────

class _WorkerArgs {
  const _WorkerArgs({
    required this.mainPort,
    required this.inPath,
    required this.outPath,
  });

  final SendPort mainPort;
  final String inPath;
  final String outPath;
}

class _ProgressMsg {
  const _ProgressMsg(this.done, this.total);
  final int done;
  final int total;
}

class _DoneMsg {
  const _DoneMsg();
}

class _ErrorMsg {
  const _ErrorMsg(this.code, this.message);
  final int code;
  final String message;
}

/// Top-level isolate entry — must be top-level for [Isolate.spawn].
///
/// Re-opens the library inside the isolate (libraries do not transfer across
/// isolates), wires a progress callback, invokes `lxt2fst_convert`, and
/// posts a terminal message before returning.
void _convertWorkerEntry(_WorkerArgs args) {
  final mainPort = args.mainPort;
  ffi.NativeCallable<Lxt2FstProgressCallback>? progressCallable;
  try {
    final lib = openWellenFfiLibrary(opener: _defaultOpener);
    final bindings = Lxt2FstBindings(lib);

    progressCallable = ffi.NativeCallable<Lxt2FstProgressCallback>.isolateLocal(
      (int done, int total, ffi.Pointer<ffi.Void> userData) {
        mainPort.send(_ProgressMsg(done, total));
      },
    );

    final inUtf8 = args.inPath.toNativeUtf8();
    final outUtf8 = args.outPath.toNativeUtf8();
    int code;
    String errorMessage;
    try {
      code = bindings.convert(
        inUtf8.cast<ffi.Char>(),
        outUtf8.cast<ffi.Char>(),
        progressCallable.nativeFunction,
        ffi.Pointer<ffi.Void>.fromAddress(0),
      );
      errorMessage = code == kLxt2FstOk ? '' : bindings.readLastError();
    } finally {
      calloc
        ..free(inUtf8)
        ..free(outUtf8);
    }
    if (code == kLxt2FstOk) {
      mainPort.send(const _DoneMsg());
    } else {
      mainPort.send(
        _ErrorMsg(
          code,
          errorMessage.isEmpty
              ? 'lxt2fst_convert returned code $code'
              : errorMessage,
        ),
      );
    }
  } on Object catch (e) {
    mainPort.send(
      _ErrorMsg(kLxt2FstErrInternal, 'lxt2fst worker crashed: $e'),
    );
  } finally {
    progressCallable?.close();
  }
}
