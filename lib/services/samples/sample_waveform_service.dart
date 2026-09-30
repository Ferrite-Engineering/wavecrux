// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;

/// Loads the bundled sample waveform that backs the Welcome screen's
/// "Open Sample Waveform" button.
///
/// ## Why a bundled sample exists
///
/// Before this existed, a first-run user faced an empty canvas whose only
/// action was "Open File…" — useless until they supplied a waveform of their
/// own. On mobile that is not merely inconvenient but impossible: an iPhone
/// cannot produce a VCD, and a reviewer (or an evaluating engineer) has no
/// way to see the app do anything at all. The bundled sample makes the app
/// demonstrate itself in one tap on every platform.
///
/// ## What the sample is
///
/// [assetPath] is a verbatim copy of
/// `verification/fixtures/protocol/multi/all5_basic.vcd` — the five-decoder
/// coexistence fixture. It drives SPI, I²C, UART, AXI4-Lite, and APB traffic
/// simultaneously in ~5 KB, so a single tap shows real signal transitions
/// *and* decoded protocol transactions rather than a couple of lonely clock
/// lines. It is a `generated/` fixture (emitted by
/// `tool/generate_multi_coexistence_fixture.dart`), not a `captured/` one, so
/// shipping it in the app bundle carries no third-party license obligation.
class SampleWaveformService {
  const SampleWaveformService();

  /// Bundle path of the sample waveform. Declared in `pubspec.yaml`.
  static const String assetPath = 'assets/samples/all5_basic.vcd';

  /// File name the sample is materialized under, and the display name shown
  /// on its tab. Deliberately not the fixture's internal `all5_basic` name —
  /// the user sees this string, and "WaveCrux Sample.vcd" reads as an
  /// intentional demo rather than a leaked test artifact.
  static const String fileName = 'WaveCrux Sample.vcd';

  /// Reads the sample's bytes out of the asset bundle.
  ///
  /// [bundle] defaults to [rootBundle]; tests inject a fake bundle instead of
  /// depending on the real asset being registered in the test binary.
  Future<Uint8List> loadBytes({AssetBundle? bundle}) async {
    final data = await (bundle ?? rootBundle).load(assetPath);
    return data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
  }

  /// Copies the sample out of the asset bundle onto the real filesystem and
  /// returns the resulting absolute path.
  ///
  /// The waveform engine reads through `dart:ffi` from a background isolate
  /// and needs a real file — it cannot read an asset-bundle key. Web has no
  /// filesystem and no FFI, so callers there must use [loadBytes] and route
  /// through the byte-loading path instead; calling this on web throws.
  ///
  /// The file is rewritten on every call rather than reused when present, so
  /// a sample truncated by an interrupted earlier copy repairs itself instead
  /// of failing to parse forever.
  Future<String> materializeToFile({AssetBundle? bundle}) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'materializeToFile is unavailable on web — use loadBytes and the '
        'byte-loading path instead.',
      );
    }
    final bytes = await loadBytes(bundle: bundle);
    final dir = await _sampleDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Directory the sample is written into.
  ///
  /// Prefers the app-support directory so the sample survives the OS reaping
  /// caches mid-session (iOS may purge the temp directory under pressure,
  /// which would break an auto-reload or a session restore pointing at it).
  /// Falls back to the system temp directory when the platform channel is
  /// unavailable — the same `MissingPluginException` fallback the settings
  /// color-theme section uses.
  Future<Directory> _sampleDirectory() async {
    try {
      final support = await path_provider.getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'samples'));
    } on Exception {
      return Directory(p.join(Directory.systemTemp.path, 'wavecrux-samples'));
    }
  }
}
