// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';

/// Result of opening a `.wcrux-widget` archive with [WidgetBundleReader].
///
/// Wraps the parsed [manifest] together with the raw bytes of every entry
/// the loader extracted from the archive. The runtime descriptor factory
/// (the renderer's Rive controller factory and any painter adapter)
/// consults [readAsset] to fetch the runtime asset declared by
/// [StageWidgetManifest.runtimeAssetPath] without re-opening the archive.
///
/// Bundles are extracted in memory rather than to a temp directory because
/// the typical bundle is well under a megabyte and the `archive` package
/// already produces decoded `Uint8List` payloads — adding a temp-file
/// indirection would only give us a place where leaked files can
/// accumulate. Large bundles are rejected by the loader long before they
/// reach this object (see `WidgetBundleSpec.maxUncompressedBytes`).
@immutable
class LoadedWidgetBundle {
  /// Creates an immutable bundle. Callers should obtain instances from
  /// [WidgetBundleReader.read] rather than constructing directly.
  const LoadedWidgetBundle({
    required this.bundlePath,
    required this.manifest,
    required Map<String, Uint8List> entries,
  }) : _entries = entries;

  /// Absolute path of the `.wcrux-widget` file the bundle was loaded from.
  /// Used by the Settings panel to display the source path and to
  /// re-validate stale entries on app startup.
  final String bundlePath;

  /// Parsed manifest. Carries the widget id, version, runtime, and
  /// signal-binding declarations.
  final StageWidgetManifest manifest;

  final Map<String, Uint8List> _entries;

  /// Whether the bundle contains an entry at [path] (relative to the
  /// archive root, using `/` as the separator).
  bool hasAsset(String path) => _entries.containsKey(path);

  /// Returns the bytes of the entry at [path], or null when the entry is
  /// absent. The returned view is a defensive copy so the caller cannot
  /// mutate the underlying buffer.
  Uint8List? readAsset(String path) {
    final raw = _entries[path];
    if (raw == null) return null;
    return Uint8List.fromList(raw);
  }

  /// All entry paths present in the bundle. Iteration order matches the
  /// archive's entry order.
  Iterable<String> get assetPaths => _entries.keys;
}
