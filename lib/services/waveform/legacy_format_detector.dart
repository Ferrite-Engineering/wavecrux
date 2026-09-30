// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Magic-byte probe that classifies a buffer as LXT, LXT2, or neither.
//
// Mirrors `lxt2fst::detect_format` in native/lxt2fst/src/lib.rs — the magic
// constants are defined there and re-stated here as the open-core "owner"
// of the detection contract on the Dart side. The probe is intentionally
// pure-Dart (no FFI, no WASM) so it can run on every build target and on
// every byte source (a `File` head-read on desktop/mobile, a `Uint8List`
// already in memory on web) without paying the cost of loading a native
// library just to identify a file.
//
// Both LXT and LXT2 begin with a 16-bit big-endian magic value:
//
//   * LXT  — 0x0138 (the 2003 streaming format)
//   * LXT2 — 0x1380 (the 2005 block-indexed format)
//
// These values share no prefix with VCD (`$date`/`$timescale` ASCII), FST
// (`0xF0`-class block headers), or GHW (`GHDLwave\n` ASCII), so 2 bytes
// are sufficient. Routing is on magic bytes,
// not extension, because users carry archives that were renamed at some
// point and the extension is an unreliable signal.

import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';

/// 16-bit big-endian magic value at offset 0 of an LXT classic file.
@visibleForTesting
const int lxtMagic = 0x0138;

/// 16-bit big-endian magic value at offset 0 of an LXT2 file.
@visibleForTesting
const int lxt2Magic = 0x1380;

/// Number of head bytes [LegacyFormatDetector.detect] needs to inspect.
/// Equal to the magic-word length; callers may pass more without harm.
const int kLegacyMagicByteCount = 2;

/// Stateless detector for the LXT / LXT2 magic-byte signatures.
///
/// Intentionally a class with a single static method so test code can
/// reference [detect] without instantiation, while the dedicated symbol
/// keeps `grep`-ability for "where do we detect legacy formats?".
class LegacyFormatDetector {
  const LegacyFormatDetector._();

  /// Classify [head] as [WaveformFormat.lxt], [WaveformFormat.lxt2], or
  /// [WaveformFormat.unknown]. Buffers shorter than [kLegacyMagicByteCount]
  /// return [WaveformFormat.unknown] — they cannot be either format.
  ///
  /// Non-legacy formats (VCD / FST / GHW) are reported as [WaveformFormat.unknown]
  /// from this detector. The caller is responsible for then delegating to
  /// the wellen backend, which carries its own format identification on
  /// successful open.
  static WaveformFormat detect(List<int> head) {
    if (head.length < kLegacyMagicByteCount) return WaveformFormat.unknown;
    final magic = (head[0] << 8) | head[1];
    return switch (magic) {
      lxtMagic => WaveformFormat.lxt,
      lxt2Magic => WaveformFormat.lxt2,
      _ => WaveformFormat.unknown,
    };
  }

  /// Open [path] and read just enough leading bytes to classify it.
  ///
  /// Throws if the file cannot be opened. Returns [WaveformFormat.unknown]
  /// if the file is shorter than [kLegacyMagicByteCount] or the magic does
  /// not match an LXT / LXT2 signature.
  ///
  /// Not supported on Flutter Web — the web build classifies the buffer
  /// it already holds via [detect].
  static Future<WaveformFormat> detectFile(String path) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'LegacyFormatDetector.detectFile requires dart:io; call detect() '
        'on an in-memory byte buffer on web.',
      );
    }
    final file = File(path);
    final handle = await file.open();
    try {
      final head = await handle.read(kLegacyMagicByteCount);
      return detect(head);
    } finally {
      await handle.close();
    }
  }

  /// Convenience for callers that already hold a [Uint8List] in memory.
  static WaveformFormat detectBytes(Uint8List bytes) => detect(bytes);
}
