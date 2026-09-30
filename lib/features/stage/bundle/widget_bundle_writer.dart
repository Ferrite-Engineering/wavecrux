// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_spec.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_yaml_parser.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';

/// Writes a Stage Pro custom-widget [StageWidgetManifest] plus its assets
/// to a `.wcrux-widget` ZIP archive.
///
/// Used by tests to produce round-trip fixtures and intended later as the
/// implementation backing an authoring CLI. Not consumed by the live
/// loader — bundles in production are produced outside the app.
///
/// The writer mirrors the constraints the [WidgetBundleReader] enforces:
/// the manifest is written to [WidgetBundleSpec.manifestEntryName]; the
/// runtime asset is written to the path declared by the manifest, which
/// must lie under [WidgetBundleSpec.runtimeDirectoryName]; auxiliary
/// assets land under [WidgetBundleSpec.assetsDirectoryName] only when the
/// caller supplies them.
class WidgetBundleWriter {
  const WidgetBundleWriter();

  /// Builds an archive in memory and returns its raw bytes. The result is
  /// suitable for writing to disk via [writeToFile] or for streaming over
  /// a network channel.
  ///
  /// Throws [ArgumentError] when [runtimeAssetBytes] is missing or when
  /// the manifest's `runtime_asset_path` does not lie inside the runtime
  /// directory — both are precondition violations the loader would later
  /// reject anyway.
  Uint8List buildBytes({
    required StageWidgetManifest manifest,
    required Uint8List runtimeAssetBytes,
    Map<String, Uint8List> assetEntries = const {},
    String? readme,
    String? license,
  }) {
    if (!WidgetBundleSpec.isRuntimePath(manifest.runtimeAssetPath)) {
      throw ArgumentError.value(
        manifest.runtimeAssetPath,
        'manifest.runtimeAssetPath',
        'must live under "${WidgetBundleSpec.runtimeDirectoryName}/"',
      );
    }
    final manifestYaml = serializeStageWidgetManifest(manifest);
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          WidgetBundleSpec.manifestEntryName,
          utf8.encode(manifestYaml).length,
          utf8.encode(manifestYaml),
        ),
      )
      ..addFile(
        ArchiveFile(
          manifest.runtimeAssetPath,
          runtimeAssetBytes.length,
          runtimeAssetBytes,
        ),
      );
    for (final entry in assetEntries.entries) {
      archive.addFile(
        ArchiveFile(entry.key, entry.value.length, entry.value),
      );
    }
    if (readme != null) {
      archive.addFile(
        ArchiveFile(
          'README.md',
          utf8.encode(readme).length,
          utf8.encode(readme),
        ),
      );
    }
    if (license != null) {
      archive.addFile(
        ArchiveFile(
          'LICENSE',
          utf8.encode(license).length,
          utf8.encode(license),
        ),
      );
    }
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  /// Convenience wrapper around [buildBytes] that writes the resulting
  /// archive to [path].
  Future<File> writeToFile({
    required String path,
    required StageWidgetManifest manifest,
    required Uint8List runtimeAssetBytes,
    Map<String, Uint8List> assetEntries = const {},
    String? readme,
    String? license,
  }) async {
    final bytes = buildBytes(
      manifest: manifest,
      runtimeAssetBytes: runtimeAssetBytes,
      assetEntries: assetEntries,
      readme: readme,
      license: license,
    );
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
