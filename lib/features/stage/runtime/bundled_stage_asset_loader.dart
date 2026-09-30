// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data' show ByteData;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// The open-core package that owns the curated Stage assets (the
/// Tachometer reference widget's `manifest.yaml` + `tachometer.riv`).
///
/// These assets are declared in `wavecrux`'s own `pubspec.yaml`. When
/// `wavecrux` is the **root app**, Flutter registers them at their bare
/// `assets/...` key. When `wavecrux` is consumed as a **path
/// dependency** — the `wavecrux_pro` overlay — the exact same bytes are
/// registered under `packages/wavecrux/assets/...` instead, and the bare
/// key does not exist in the app's asset manifest. Loading a curated
/// Stage asset by its bare path therefore works in the open-core build
/// but fails in the Pro build; the helpers below resolve both.
const String kStageAssetOwnerPackage = 'wavecrux';

String _packagedKey(String assetPath, String package) =>
    'packages/$package/$assetPath';

/// Loads the bytes of a curated, bundle-declared Stage asset, resolving
/// the open-core-vs-overlay asset-key difference described on
/// [kStageAssetOwnerPackage].
///
/// Tries the bare [assetPath] first (the root-app / open-core case); on
/// failure falls back to the `packages/<package>/<assetPath>` key (the
/// dependency / Pro-overlay case). If neither resolves, the **original**
/// bare-path error is rethrown so the diagnostic names the path the
/// asset declaration actually uses rather than the internal fallback.
Future<ByteData> loadBundledStageAssetBytes(
  String assetPath, {
  AssetBundle? bundle,
  String package = kStageAssetOwnerPackage,
}) async {
  final b = bundle ?? rootBundle;
  try {
    return await b.load(assetPath);
  } on Object catch (bareError, bareStack) {
    try {
      return await b.load(_packagedKey(assetPath, package));
    } on Object {
      // Neither key resolved — surface the original bare-path failure so
      // the diagnostic names the declared path, not the fallback.
      Error.throwWithStackTrace(bareError, bareStack);
    }
  }
}

/// String counterpart of [loadBundledStageAssetBytes] — same bare →
/// `packages/<package>/` fallback, for text assets like the manifest.
Future<String> loadBundledStageAssetString(
  String assetPath, {
  AssetBundle? bundle,
  String package = kStageAssetOwnerPackage,
}) async {
  final b = bundle ?? rootBundle;
  try {
    return await b.loadString(assetPath);
  } on Object catch (bareError, bareStack) {
    try {
      return await b.loadString(_packagedKey(assetPath, package));
    } on Object {
      Error.throwWithStackTrace(bareError, bareStack);
    }
  }
}
