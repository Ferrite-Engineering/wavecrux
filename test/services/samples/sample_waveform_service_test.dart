// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/samples/sample_waveform_service.dart';

/// Asset bundle that serves one canned payload for the sample's asset key and
/// throws for anything else, so the tests exercise the service without
/// depending on the real asset being registered in the test binary.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(String payload) : payload = utf8.encode(payload);

  final Uint8List payload;

  @override
  Future<ByteData> load(String key) async {
    if (key != SampleWaveformService.assetPath) {
      throw ArgumentError.value(key, 'key', 'unexpected asset key');
    }
    return ByteData.sublistView(payload);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      utf8.decode(payload);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = SampleWaveformService();

  test('loads the sample bytes out of the asset bundle', () async {
    final bytes = await service.loadBytes(bundle: _FakeBundle(r'$date x $end'));
    expect(utf8.decode(bytes), r'$date x $end');
  });

  test('materializes the sample to a real, re-readable file', () async {
    // The waveform engine parses through FFI on a background isolate and
    // cannot read an asset-bundle key, so the asset must land on disk.
    const contents = '\$timescale 1 ns \$end\n';
    final path = await service.materializeToFile(
      bundle: _FakeBundle(contents),
    );

    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsStringSync(), contents);
    expect(p.basename(path), SampleWaveformService.fileName);
  });

  test(
    'rewrites the file on every call so a truncated copy self-repairs',
    () async {
      // A copy interrupted partway through would otherwise poison the sample
      // permanently: the file exists, so a reuse-if-present implementation
      // would keep handing the parser a half-written VCD forever.
      final first = await service.materializeToFile(
        bundle: _FakeBundle('good contents'),
      );
      File(first).writeAsStringSync('garbage that should be replaced');

      final second = await service.materializeToFile(
        bundle: _FakeBundle('good contents'),
      );
      expect(File(second).readAsStringSync(), 'good contents');
    },
  );

  group('the shipped asset', () {
    // The pubspec bundles a copy of the five-decoder coexistence fixture.
    // These assert the real file on disk, not the fake bundle — a drifted or
    // deleted copy must fail here rather than at App Store review.
    final asset = File('assets/samples/all5_basic.vcd');
    final fixture = File('verification/fixtures/protocol/multi/all5_basic.vcd');

    test('exists and is byte-identical to its verification fixture', () {
      expect(
        asset.existsSync(),
        isTrue,
        reason: 'assets/samples/all5_basic.vcd is declared in pubspec.yaml',
      );
      expect(fixture.existsSync(), isTrue);
      expect(asset.readAsBytesSync(), fixture.readAsBytesSync());
    });

    test('is a parseable VCD carrying all five decodable buses', () {
      // The point of shipping this particular fixture is that one tap shows
      // decoded protocol transactions, not two lonely clock lines. If it is
      // ever swapped for something thinner, the demo stops demonstrating.
      final text = asset.readAsStringSync();
      expect(text, startsWith(r'$date'));
      for (final scope in const [
        'spi_tb',
        'i2c_tb',
        'uart_tb',
        'axi4lite_tb',
        'apb_tb',
      ]) {
        expect(text, contains(scope), reason: 'missing scope $scope');
      }
    });

    test('stays small enough to ship in the app bundle', () {
      expect(asset.lengthSync(), lessThan(64 * 1024));
    });
  });
}
