// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:wavecrux/features/stage/bundle/loaded_widget_bundle.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_failure.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_spec.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_validation_error.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_yaml_parser.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';

/// Loads a `.wcrux-widget` archive into a [LoadedWidgetBundle].
///
/// All loaded bundles are treated as untrusted. The reader rejects:
///
/// - Path-traversal entries (`..`, absolute paths, drive-letter paths).
/// - Symbolic-link entries.
/// - Archives whose total uncompressed size exceeds
///   `WidgetBundleSpec.maxUncompressedBytes` (zip-bomb defence).
/// - Archive entries with more than `WidgetBundleSpec.maxPathSegments`
///   path segments.
/// - Manifests outside the SDK's supported `required_api_version` range.
/// - Manifests that pass YAML validation but reference a runtime asset
///   missing from the archive or outside the bundle's `runtime/`
///   directory.
///
/// Each rejection surfaces as a [WidgetBundleException] whose
/// [WidgetBundleFailureKind] the caller maps to a localized user message.
class WidgetBundleReader {
  /// Creates a reader. The default [archiveDecoder] uses the standard
  /// `package:archive` ZIP decoder; tests may inject a stub for failure
  /// injection without touching disk.
  WidgetBundleReader({
    Archive Function(List<int> bytes)? archiveDecoder,
    Future<List<int>> Function(String path)? fileReader,
  }) : _archiveDecoder = archiveDecoder ?? _defaultDecoder,
       _fileReader = fileReader ?? _defaultFileReader;

  final Archive Function(List<int> bytes) _archiveDecoder;
  final Future<List<int>> Function(String path) _fileReader;

  static Archive _defaultDecoder(List<int> bytes) =>
      ZipDecoder().decodeBytes(bytes, verify: true);

  static Future<List<int>> _defaultFileReader(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.fileMissing,
        diagnostic: 'Bundle file does not exist',
        bundlePath: path,
      );
    }
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.ioError,
        diagnostic: 'Failed to read bundle: ${e.message}',
        bundlePath: path,
      );
    }
  }

  /// Reads the bundle at [path], validates it, and returns a
  /// [LoadedWidgetBundle].
  ///
  /// Throws [WidgetBundleException] on every failure path; never returns
  /// null and never silently degrades.
  Future<LoadedWidgetBundle> read(String path) async {
    final bytes = await _fileReader(path);
    final archive = _decodeOrThrow(bytes, path);

    final extracted = <String, Uint8List>{};
    var totalSize = 0;
    for (final entry in archive) {
      if (entry.isSymbolicLink) {
        throw WidgetBundleException(
          kind: WidgetBundleFailureKind.symlinkRejected,
          diagnostic: 'Archive entry is a symlink: ${entry.name}',
          bundlePath: path,
        );
      }
      _validateEntryName(entry.name, path);
      if (entry.isDirectory) continue;

      totalSize += entry.size;
      if (totalSize > WidgetBundleSpec.maxUncompressedBytes) {
        throw WidgetBundleException(
          kind: WidgetBundleFailureKind.oversize,
          diagnostic:
              'Bundle uncompressed size exceeds the '
              '${WidgetBundleSpec.maxUncompressedBytes ~/ (1024 * 1024)} '
              'MiB limit',
          bundlePath: path,
        );
      }

      final content = entry.content as List<int>;
      extracted[entry.name] = Uint8List.fromList(content);
    }

    final manifestBytes = extracted[WidgetBundleSpec.manifestEntryName];
    if (manifestBytes == null) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.manifestMissing,
        diagnostic:
            'Bundle is missing required entry '
            '"${WidgetBundleSpec.manifestEntryName}"',
        bundlePath: path,
      );
    }

    final manifestSource = utf8.decode(manifestBytes, allowMalformed: false);
    final manifest = _parseManifestOrThrow(manifestSource, path);

    if (manifest.requiredApiVersion < WidgetBundleSpec.minSupportedApiVersion ||
        manifest.requiredApiVersion > WidgetBundleSpec.maxSupportedApiVersion) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.unsupportedApiVersion,
        diagnostic:
            'Manifest required_api_version '
            '${manifest.requiredApiVersion} is outside the SDK supported '
            'range '
            '[${WidgetBundleSpec.minSupportedApiVersion}, '
            '${WidgetBundleSpec.maxSupportedApiVersion}]',
        bundlePath: path,
      );
    }

    _validateRuntimeAsset(
      manifest.runtimeAssetPath,
      manifest.runtime,
      extracted,
      path,
    );

    return LoadedWidgetBundle(
      bundlePath: path,
      manifest: manifest,
      entries: extracted,
    );
  }

  Archive _decodeOrThrow(List<int> bytes, String path) {
    try {
      return _archiveDecoder(bytes);
    } on Object catch (e) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.notAZipArchive,
        diagnostic: 'Failed to decode ZIP archive: $e',
        bundlePath: path,
      );
    }
  }

  void _validateEntryName(String name, String path) {
    if (name.isEmpty) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.pathTraversal,
        diagnostic: 'Archive entry has an empty name',
        bundlePath: path,
      );
    }
    if (name.startsWith('/') || name.startsWith(r'\')) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.pathTraversal,
        diagnostic: 'Archive entry uses an absolute path: $name',
        bundlePath: path,
      );
    }
    // Reject Windows drive-letter paths (e.g. "C:/foo").
    if (name.length >= 2 && name[1] == ':') {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.pathTraversal,
        diagnostic: 'Archive entry uses a drive-letter path: $name',
        bundlePath: path,
      );
    }
    final normalized = name.replaceAll(r'\', '/');
    final segments = normalized.split('/');
    if (segments.length > WidgetBundleSpec.maxPathSegments) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.pathTooDeep,
        diagnostic:
            'Archive entry has too many path segments '
            '(${segments.length} > ${WidgetBundleSpec.maxPathSegments}): '
            '$name',
        bundlePath: path,
      );
    }
    for (final segment in segments) {
      if (segment == '..' || segment == '.') {
        throw WidgetBundleException(
          kind: WidgetBundleFailureKind.pathTraversal,
          diagnostic:
              'Archive entry contains a parent-traversal segment: $name',
          bundlePath: path,
        );
      }
    }
  }

  void _validateRuntimeAsset(
    String runtimeAssetPath,
    ManifestRuntime runtime,
    Map<String, Uint8List> extracted,
    String path,
  ) {
    if (runtimeAssetPath.isEmpty) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.runtimeAssetMissing,
        diagnostic: 'Manifest declares an empty runtime_asset_path',
        bundlePath: path,
      );
    }
    if (!WidgetBundleSpec.isRuntimePath(runtimeAssetPath)) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.runtimeAssetMissing,
        diagnostic:
            'Manifest runtime_asset_path "$runtimeAssetPath" must live '
            'under "${WidgetBundleSpec.runtimeDirectoryName}/" inside the '
            'bundle',
        bundlePath: path,
      );
    }
    if (!extracted.containsKey(runtimeAssetPath)) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.runtimeAssetMissing,
        diagnostic:
            'Manifest references runtime asset "$runtimeAssetPath" which '
            'is missing from the bundle archive',
        bundlePath: path,
      );
    }
    // ManifestRuntime is consumed when constructing descriptors; the
    // reader does not enforce extension shape (e.g. .riv) because painter
    // bundles deliberately have no fixed extension.
    runtime.toString();
  }

  StageWidgetManifest _parseManifestOrThrow(
    String manifestSource,
    String path,
  ) {
    try {
      return parseStageWidgetManifest(manifestSource);
    } on ManifestValidationException catch (e) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.manifestInvalid,
        diagnostic: 'Manifest validation failed: $e',
        bundlePath: path,
      );
    } on FormatException catch (e) {
      throw WidgetBundleException(
        kind: WidgetBundleFailureKind.manifestInvalid,
        diagnostic: 'Manifest is not valid YAML: ${e.message}',
        bundlePath: path,
      );
    }
  }
}
