// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_writer.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';

// Local copy of the bundle test helpers for the Custom Widgets settings panel
// tests. The canonical helpers live at
// `wavecrux/test/features/stage/bundle/_bundle_test_helpers.dart`.

StageWidgetManifest sampleManifest({
  String id = 'com.acme.test',
  String displayName = 'Sample',
  String version = '1.0.0',
  StageWidgetCategory category = StageWidgetCategory.instrument,
  String runtimeAssetPath = 'runtime/sample.riv',
  ManifestRuntime runtime = ManifestRuntime.rive,
}) => StageWidgetManifest(
  id: id,
  version: version,
  displayName: LocalizedString.single(displayName),
  category: category,
  runtime: runtime,
  runtimeAssetPath: runtimeAssetPath,
  requiredApiVersion: 1,
);

Future<File> writeSampleBundle({
  required String path,
  StageWidgetManifest? manifest,
  Uint8List? runtimeBytes,
}) {
  final m = manifest ?? sampleManifest();
  final bytes = runtimeBytes ?? Uint8List.fromList(const [1, 2, 3, 4]);
  return const WidgetBundleWriter().writeToFile(
    path: path,
    manifest: m,
    runtimeAssetBytes: bytes,
  );
}
