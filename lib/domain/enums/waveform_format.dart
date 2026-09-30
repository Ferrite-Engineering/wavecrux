// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Identifies the on-disk waveform file format that a [WaveformDataSource]
/// was loaded from.
///
/// Today wellen handles [vcd], [fst], and [ghw] directly. [lxt] and [lxt2]
/// are GTKWave's legacy formats (2003 streaming and 2005 block-indexed
/// respectively); WaveCrux opens them via the `lxt2fst` convert-on-open
/// pipeline and the active source is always FST after that
/// conversion. Carrying the *original* format separately lets the
/// Diagnostics → File Info pane display "LXT2 (converted to FST on open)"
/// even though the in-memory backing store is FST.
///
/// [unknown] is returned for sources whose format string the wellen FFI
/// surface did not recognize. It is also the value when the conversion
/// route ran but the caller did not supply an origin.
enum WaveformFormat {
  vcd,
  fst,
  ghw,
  lxt,
  lxt2,
  unknown;

  /// Parse the string label that the wellen FFI / WASM bridge returns from
  /// `wellen_file_format` (`"VCD"`, `"FST"`, `"GHW"`, …). Case-insensitive.
  /// Unknown labels collapse to [unknown].
  static WaveformFormat fromWellenLabel(String label) =>
      switch (label.toUpperCase()) {
        'VCD' => WaveformFormat.vcd,
        'FST' => WaveformFormat.fst,
        'GHW' => WaveformFormat.ghw,
        'LXT' => WaveformFormat.lxt,
        'LXT2' => WaveformFormat.lxt2,
        _ => WaveformFormat.unknown,
      };

  /// Whether this format is one of the two GTKWave legacy formats that the
  /// `lxt2fst` crate converts to FST at open time. Used by the open-file
  /// path to decide whether to invoke the converter before delegating to
  /// the wellen backend.
  bool get isLegacy =>
      this == WaveformFormat.lxt || this == WaveformFormat.lxt2;
}
