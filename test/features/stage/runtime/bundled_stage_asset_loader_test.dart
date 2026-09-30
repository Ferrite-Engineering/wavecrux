// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/runtime/bundled_stage_asset_loader.dart';

/// Minimal in-memory [AssetBundle] that only serves the keys it's given,
/// throwing a [FlutterError] (the same shape as the real bundle's
/// not-found error) for anything else. Lets us simulate the open-core
/// build (bare key only) vs. the Pro overlay (packages/wavecrux/ key
/// only) without a real asset manifest.
class _MapBundle extends AssetBundle {
  _MapBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final value = _assets[key];
    if (value == null) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.view(Uint8List.fromList(utf8.encode(value)).buffer);
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) => throw UnimplementedError();
}

String _decode(ByteData data) => utf8.decode(
  data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
);

void main() {
  const barePath = 'assets/stage/widgets/rive/manifest.yaml';
  const packagedPath =
      'packages/wavecrux/assets/stage/widgets/rive/manifest.yaml';

  group('loadBundledStageAssetBytes', () {
    test('resolves the bare key (open-core / root-app build)', () async {
      final bundle = _MapBundle({barePath: 'bare'});
      final data = await loadBundledStageAssetBytes(barePath, bundle: bundle);
      expect(_decode(data), 'bare');
    });

    test('falls back to packages/<owner>/ key (Pro overlay build)', () async {
      // The bare key is absent — exactly the Pro build, where the asset
      // lives under packages/wavecrux/.
      final bundle = _MapBundle({packagedPath: 'packaged'});
      final data = await loadBundledStageAssetBytes(barePath, bundle: bundle);
      expect(_decode(data), 'packaged');
    });

    test('rethrows the bare-path error when neither key resolves', () async {
      final bundle = _MapBundle(const {});
      await expectLater(
        loadBundledStageAssetBytes(barePath, bundle: bundle),
        // The surfaced error names the *bare* declared path, not the
        // internal packages/wavecrux/ fallback.
        throwsA(
          predicate(
            (e) =>
                e.toString().contains(barePath) &&
                !e.toString().contains('packages/wavecrux'),
          ),
        ),
      );
    });
  });

  group('loadBundledStageAssetString', () {
    test('resolves the bare key', () async {
      final bundle = _MapBundle({barePath: 'bare-str'});
      expect(
        await loadBundledStageAssetString(barePath, bundle: bundle),
        'bare-str',
      );
    });

    test('falls back to the packages/<owner>/ key', () async {
      final bundle = _MapBundle({packagedPath: 'packaged-str'});
      expect(
        await loadBundledStageAssetString(barePath, bundle: bundle),
        'packaged-str',
      );
    });
  });
}
