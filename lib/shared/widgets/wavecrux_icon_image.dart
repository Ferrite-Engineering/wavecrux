// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The WaveCrux app-icon bitmap, resolved resiliently across both packaging
/// contexts so it never throws an unguarded `Unable to load asset` error —
/// and never *attempts* a load that is known to fail.
///
///  * When `wavecrux` is consumed as a path/pub dependency (the Pro
///    overlay, or any downstream app), the open-core image assets are bundled
///    under `packages/wavecrux/assets/images/...`.
///  * When `wavecrux` is the *root* application (open-core standalone, and
///    every `flutter test` / `integration_test` run launched from the
///    open-core repo), the root package's own assets are bundled at the bare
///    `assets/...` path and are NOT mirrored under `packages/wavecrux/`.
///
/// The packaging context is decided by looking the key up in the
/// [AssetManifest] — a cached in-memory lookup — rather than by attempting
/// the load and catching the failure. The old try-then-fallback approach was
/// functionally correct but noisy: on Flutter Web every miss surfaced as a
/// logged HTTP 404 ("Flutter Web engine failed to fetch
/// assets/packages/wavecrux/...") on each run, because the web engine
/// reports the failed fetch before the `errorBuilder` handles it.
///
/// If neither key is bundled (a consumer that bundled no open-core image
/// assets at all), we degrade to a neutral chart glyph rather than throwing.
/// An unguarded `Image.asset` failure surfaces as an uncaught `FlutterError`
/// that trips `tester.takeException()` and reddens otherwise-passing widget
/// and integration tests — which is exactly how this seam was discovered.
class WaveCruxIconImage extends StatelessWidget {
  /// Creates the resilient WaveCrux icon image at [size] logical pixels square.
  const WaveCruxIconImage({required this.size, super.key});

  /// Width and height of the rendered icon, in logical pixels.
  final double size;

  /// Path to the icon as declared in the open-core `wavecrux` pubspec.
  static const String assetPath = 'assets/images/wavecrux_icon_1024.png';

  /// Open-core package name used to namespace the asset when `wavecrux` is a
  /// dependency rather than the root app.
  static const String assetPackage = 'wavecrux';

  /// Fully-qualified manifest key for the dependency-packaging context.
  static const String packagedAssetKey = 'packages/$assetPackage/$assetPath';

  /// Synchronously-available resolution per bundle: the bundled asset key,
  /// or `''` when neither key exists (glyph fallback). Populated by the
  /// first async manifest lookup so subsequent rebuilds render the image
  /// directly — no placeholder frame, no repeated FutureBuilder round-trip.
  static final Expando<String> _resolvedKeyCache = Expando<String>();

  /// Resolves which asset key (if any) is actually bundled, via the asset
  /// manifest — never by attempting a doomed load.
  static Future<String> _resolveKey(AssetBundle bundle) async {
    final cached = _resolvedKeyCache[bundle];
    if (cached != null) return cached;
    String resolved;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle);
      final assets = manifest.listAssets();
      resolved = assets.contains(packagedAssetKey)
          ? packagedAssetKey
          : assets.contains(assetPath)
          ? assetPath
          : '';
    } on Object {
      // Manifest unavailable (bespoke test bundles) — glyph fallback.
      resolved = '';
    }
    return _resolvedKeyCache[bundle] = resolved;
  }

  @override
  Widget build(BuildContext context) {
    final bundle = DefaultAssetBundle.of(context);
    final cached = _resolvedKeyCache[bundle];
    if (cached != null) return _buildForKey(context, bundle, cached);
    return FutureBuilder<String>(
      future: _resolveKey(bundle),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Resolution in flight (first frame only) — hold the layout slot.
          return SizedBox(width: size, height: size);
        }
        return _buildForKey(context, bundle, snapshot.data!);
      },
    );
  }

  Widget _buildForKey(BuildContext context, AssetBundle bundle, String key) {
    if (key.isEmpty) return _glyph(context);
    return Image.asset(
      key,
      bundle: bundle,
      width: size,
      height: size,
      // Manifest said the key exists, so this is unreachable in practice —
      // kept so a corrupt bundle still degrades instead of throwing.
      errorBuilder: (context, error, stackTrace) => _glyph(context),
    );
  }

  /// Neutral fallback glyph for consumers that bundled no icon asset.
  Widget _glyph(BuildContext context) => Icon(
    Icons.show_chart,
    size: size,
    color: Theme.of(context).colorScheme.onSurface,
  );
}
