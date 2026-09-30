// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/shared/widgets/wavecrux_icon_image.dart';

/// An asset bundle that fails every load — [WaveCruxIconImage] cannot even
/// read the asset manifest, so it must degrade to the glyph fallback.
class _FailingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    throw FlutterError('Unable to load asset: "$key".');
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async {
    throw FlutterError('Unable to load asset: "$key".');
  }
}

/// Delegates to the real root bundle but records every [load] key, so a test
/// can assert which asset fetches were *attempted* — the regression surface
/// for the web-console 404 noise (the old code always tried the
/// package-qualified key first and let it fail in root-app context).
class _RecordingAssetBundle extends CachingAssetBundle {
  final List<String> loadedKeys = [];

  @override
  Future<ByteData> load(String key) {
    loadedKeys.add(key);
    return rootBundle.load(key);
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async {
    return parser(await rootBundle.loadString(key));
  }

  @override
  Future<T> loadStructuredBinaryData<T>(
    String key,
    FutureOr<T> Function(ByteData data) parser,
  ) async {
    return parser(await rootBundle.load(key));
  }
}

void main() {
  Widget host(Widget child, {AssetBundle? bundle}) {
    final app = MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
    if (bundle == null) return app;
    return DefaultAssetBundle(bundle: bundle, child: app);
  }

  /// Pumps until [finder] matches or [tries] pumps elapse — the manifest
  /// resolution and image decode complete asynchronously.
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int tries = 10,
  }) async {
    for (var i = 0; i < tries && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('renders an Image at the requested size on the happy path', (
    tester,
  ) async {
    await tester.pumpWidget(host(const WaveCruxIconImage(size: 24)));
    await pumpUntilFound(tester, find.byType(Image));

    // The manifest-resolved Image is present and correctly sized; no glyph
    // fallback was needed.
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.show_chart), findsNothing);
    final size = tester.getSize(find.byType(Image).first);
    expect(size, const Size(24, 24));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'root-app context never attempts the package-qualified fetch '
    '(the web-console 404 regression)',
    (tester) async {
      // In root-app packaging (this test run: wavecrux IS the root package)
      // only the bare asset path is bundled. The widget must resolve that
      // from the manifest and go straight to the bare key — the old
      // try-package-first approach logged an HTTP 404 on every web run.
      final bundle = _RecordingAssetBundle();
      await tester.pumpWidget(
        host(const WaveCruxIconImage(size: 24), bundle: bundle),
      );
      await pumpUntilFound(tester, find.byType(Image));

      expect(find.byType(Image), findsOneWidget);
      expect(
        bundle.loadedKeys.where(
          (k) => k.contains('packages/${WaveCruxIconImage.assetPackage}/'),
        ),
        isEmpty,
        reason:
            'no load may be attempted for the package-qualified key when '
            'the manifest shows only the bare path is bundled',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'falls back to a neutral glyph (never throws) when the asset is '
    'unresolvable in both packaging contexts',
    (tester) async {
      // A bundle that throws for every key means even the manifest cannot be
      // read — the widget must degrade to the glyph without an uncaught
      // FlutterError tripping tester.takeException().
      await tester.pumpWidget(
        host(const WaveCruxIconImage(size: 18), bundle: _FailingAssetBundle()),
      );
      await pumpUntilFound(tester, find.byIcon(Icons.show_chart));

      expect(find.byIcon(Icons.show_chart), findsOneWidget);
      final iconSize = tester.getSize(find.byIcon(Icons.show_chart).first);
      expect(iconSize.width, 18);
      expect(iconSize.height, 18);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'exposes the open-core asset path and package as the resolution seam',
    () {
      // These constants are the contract the resilient loader is built around;
      // they must match the asset declared in the open-core pubspec.
      expect(
        WaveCruxIconImage.assetPath,
        'assets/images/wavecrux_icon_1024.png',
      );
      expect(WaveCruxIconImage.assetPackage, 'wavecrux');
      expect(
        WaveCruxIconImage.packagedAssetKey,
        'packages/wavecrux/assets/images/wavecrux_icon_1024.png',
      );
    },
  );
}
