// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Computes a stable content fingerprint of the bytes of a loaded waveform
/// file, used by the collaborative-viewing *waveform-identity* check.
///
/// Each participant fingerprints the file they have open and announces the
/// digest over the session handshake (see
/// `CollaborationService.updateWaveformIdentity`). When the digests reported by
/// participants disagree, the Pro overlay surfaces a "different waveform loaded"
/// warning. Only the digest crosses the network — never sample data — so the
/// relay stays metadata-only.
///
/// The fingerprint is taken over the **bytes the user picked** (the original
/// file), not any converted-on-open derivative (e.g. LXT2→FST), so two
/// engineers who opened the same source file match regardless of local
/// conversion artifacts.
///
/// **Why a plain rolling hash and not SHA-256.** An earlier `package:crypto`
/// SHA-256 implementation crashed the macOS (Apple Silicon) build at launch: the
/// Dart JIT's optimizing compiler miscompiled SHA-256's integer-heavy round
/// function (the faulting thread ran JIT'd code while the background compiler
/// sat in `IntegerInstructionSelector`/`RangeAnalysis`), `EXC_BAD_ACCESS` the
/// moment a restored session hashed its file. This check does not need a
/// cryptographic digest — the threat model is *accidental* divergence
/// (different captures, a stale re-sim, the wrong file), not an adversary
/// engineering a collision. Two independent rolling polynomial hashes (folding
/// in the byte length) are a simple multiply/add/mod loop the optimizer handles
/// fine, and every intermediate stays below 2^53 so the result is **identical
/// on native and on web** (where ints are JS doubles).
///
/// Hashing is best-effort: any I/O failure (file removed, unreadable, streaming
/// source with no on-disk bytes) yields `null`, which the identity check treats
/// as "no reported hash" — never a false mismatch.
abstract final class WaveformContentHash {
  // Two independent rolling polynomial hashes over distinct primes. Each
  // intermediate (h * base + byte) stays below 2^53, so native (64-bit int) and
  // web (JS double) produce identical digests.
  static const int _mod1 = 1000000007;
  static const int _mod2 = 998244353;
  static const int _base1 = 131;
  static const int _base2 = 137;

  /// Content fingerprint of the file at [path].
  ///
  /// Reads the file as an async byte stream ([File.openRead]) — the bytes are
  /// pulled off the platform I/O thread and folded on the current isolate's
  /// event loop, so a large file neither blocks the caller nor holds the whole
  /// file in memory. Returns `null` if the file cannot be read. Not available
  /// on web (no `dart:io`); web callers use [ofBytes].
  static Future<String?> ofFile(String path) async {
    assert(!kIsWeb, 'ofFile uses dart:io; web callers must use ofBytes');
    try {
      var h1 = 0;
      var h2 = 0;
      var length = 0;
      await for (final chunk in File(path).openRead()) {
        length += chunk.length;
        for (var i = 0; i < chunk.length; i++) {
          final b = chunk[i] + 1;
          h1 = (h1 * _base1 + b) % _mod1;
          h2 = (h2 * _base2 + b) % _mod2;
        }
      }
      return _format(length, h1, h2);
    } on Object {
      return null;
    }
  }

  /// Content fingerprint of [bytes]. Synchronous — used on web where the
  /// picked file's bytes are already in memory.
  static String ofBytes(Uint8List bytes) {
    var h1 = 0;
    var h2 = 0;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i] + 1;
      h1 = (h1 * _base1 + b) % _mod1;
      h2 = (h2 * _base2 + b) % _mod2;
    }
    return _format(bytes.length, h1, h2);
  }

  static String _format(int length, int h1, int h2) =>
      '${length.toRadixString(16)}-'
      '${h1.toRadixString(16)}-${h2.toRadixString(16)}';
}
