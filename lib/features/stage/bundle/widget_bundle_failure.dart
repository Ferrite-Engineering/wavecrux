// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Distinct failure modes the [WidgetBundleReader] surfaces. The Settings →
/// Stage Pro → Custom Widgets panel maps each variant to a localized
/// message via the Pro ARB strings; tests assert on the variant rather
/// than on the message text.
enum WidgetBundleFailureKind {
  /// The file does not exist or is not readable.
  fileMissing,

  /// The file exists but is not a valid ZIP archive.
  notAZipArchive,

  /// The archive is missing the required `manifest.yaml` entry.
  manifestMissing,

  /// The archive contains the manifest entry but it failed YAML
  /// validation. The Pro panel surfaces the underlying parser errors.
  manifestInvalid,

  /// Manifest declares `required_api_version` outside the SDK's supported
  /// range.
  unsupportedApiVersion,

  /// Manifest declares a runtime asset that is missing from the archive
  /// or lies outside the bundle's `runtime/` directory.
  runtimeAssetMissing,

  /// Archive contains a path-traversal segment (`..` or absolute path),
  /// or otherwise tries to escape its own root.
  pathTraversal,

  /// Archive contains a symbolic link entry. Symlinks are rejected
  /// outright because the loader cannot reason about where they point.
  symlinkRejected,

  /// Archive's total uncompressed size exceeds
  /// `WidgetBundleSpec.maxUncompressedBytes`.
  oversize,

  /// Archive entry path exceeds `WidgetBundleSpec.maxPathSegments`.
  pathTooDeep,

  /// Generic I/O error reading the bundle (permission denied, locked,
  /// disk error). Distinct from [fileMissing].
  ioError,
}

/// Thrown by [WidgetBundleReader] when a bundle cannot be loaded.
///
/// Carries a structured [kind] for UI dispatch, a human-readable
/// [diagnostic] (always English — the Settings panel resolves [kind] to a
/// localized message), and the offending [bundlePath] for logging.
@immutable
class WidgetBundleException implements Exception {
  const WidgetBundleException({
    required this.kind,
    required this.diagnostic,
    required this.bundlePath,
  });

  final WidgetBundleFailureKind kind;
  final String diagnostic;
  final String bundlePath;

  @override
  String toString() =>
      'WidgetBundleException(kind: $kind, path: $bundlePath, '
      'diagnostic: $diagnostic)';
}
