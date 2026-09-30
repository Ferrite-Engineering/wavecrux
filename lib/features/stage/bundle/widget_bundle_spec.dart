// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// On-disk constants and rules for the `.wcrux-widget` archive format used
/// by the Stage Pro custom-widget SDK.
///
/// A bundle is a ZIP archive that the [WidgetBundleReader] opens, validates,
/// and turns into a [LoadedWidgetBundle]. The format is intentionally simple
/// so a bundle author can produce one with `zip` on the command line; the
/// fields here are the binding contract for both the reader and the
/// authoring CLI / [WidgetBundleWriter].
///
/// Layout inside the archive (relative paths only — see
/// [WidgetBundleSpec.maxPathSegments]):
///
/// ```text
/// manifest.yaml          // required, root, parsed by parseStageWidgetManifest
/// runtime/<asset>.riv    // required for runtime: rive (path declared in manifest)
/// runtime/<source>       // required for runtime: painter (path declared in manifest)
/// assets/icon.png        // optional, referenced by manifest.iconAssetPath
/// LICENSE                // optional, not surfaced by the loader
/// README.md              // optional, not surfaced by the loader
/// ```
///
/// All bundles are treated as untrusted content. The reader rejects archives
/// that contain entries with absolute paths, parent-traversal segments
/// (`..`), or symlinks; that exceed [maxUncompressedBytes] when expanded; or
/// whose declared API version is unsupported.
class WidgetBundleSpec {
  const WidgetBundleSpec._();

  /// File extension carried by every Stage Pro custom-widget bundle.
  static const String fileExtension = 'wcrux-widget';

  /// Path of the manifest file inside the archive, relative to the
  /// archive root. This path is fixed; bundles that put the manifest
  /// elsewhere are rejected.
  static const String manifestEntryName = 'manifest.yaml';

  /// Directory inside the archive that holds runtime assets (the `.riv`
  /// file for Rive bundles, or painter source files for painter bundles).
  ///
  /// Manifests must declare `runtime_asset_path` as a path relative to
  /// the archive root; the loader enforces that the declared path lies
  /// within this directory.
  static const String runtimeDirectoryName = 'runtime';

  /// Optional directory holding auxiliary assets (icons, sample data)
  /// referenced by the manifest. Unlike [runtimeDirectoryName] the loader
  /// does not require entries here; they are extracted on demand when the
  /// manifest names them.
  static const String assetsDirectoryName = 'assets';

  /// Manifest API version range supported by the current SDK build.
  ///
  /// Bundles whose manifest declares a `required_api_version` outside this
  /// range are rejected with [WidgetBundleSecurity.unsupportedApiVersion].
  /// Lower values mean "compiled against an older SDK"; higher values mean
  /// the bundle expects a newer SDK than is installed.
  static const int minSupportedApiVersion = 1;

  /// Highest manifest API version this SDK build understands.
  static const int maxSupportedApiVersion = 1;

  /// Maximum total uncompressed size the loader will accept across all
  /// archive entries. Designed to defeat zip-bomb-style oversize attacks
  /// that try to exhaust memory on extraction. The current limit is sized
  /// generously for legitimate bundles (a few `.riv` artboards, icons,
  /// and a manifest) while keeping the worst-case extraction bounded.
  static const int maxUncompressedBytes = 32 * 1024 * 1024; // 32 MiB

  /// Maximum number of `/`-separated segments any archive entry path may
  /// contain. Bundles that nest content very deeply are most often the
  /// product of broken authoring tooling — capping here keeps the loader
  /// from chasing pathological structures.
  static const int maxPathSegments = 8;

  /// Returns true when [path] starts with [runtimeDirectoryName] followed
  /// by a single `/`.
  static bool isRuntimePath(String path) =>
      path.startsWith('$runtimeDirectoryName/');

  /// Returns true when [path] starts with [assetsDirectoryName] followed
  /// by a single `/`.
  static bool isAssetsPath(String path) =>
      path.startsWith('$assetsDirectoryName/');
}
