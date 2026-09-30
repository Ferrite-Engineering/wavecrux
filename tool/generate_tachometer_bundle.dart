// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the committed `.wcrux-widget` packaging artifact for the
// open-core Tachometer reference widget.
//
// Run from the repository root any time the manifest, runtime asset, or
// editor-source changes:
//
//   dart run tool/generate_tachometer_bundle.dart
//
// The output path is:
//
//   assets/stage/widgets/rive/tachometer.wcrux-widget
//
// The generator parses `assets/stage/widgets/rive/manifest.yaml`, reads
// the runtime asset declared by the manifest's `runtime_asset_path`,
// pipes both through `WidgetBundleWriter`, and writes the resulting
// `.wcrux-widget` archive into the assets directory.
//
// The committed bundle is a packaging artifact: the Tachometer widget is
// registered directly by `registerBuiltinStageWidgets()`, so this bundle
// does not drive its loading path. It exists as a reference artifact
// for community widget authors studying the `.wcrux-widget` archive
// layout and as the canonical sample bundle used by the documentation
// in `assets/stage/widgets/rive/README.md`.
//
// Tooling scripts print progress to stdout so developers re-running the
// generator see what was produced.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:wavecrux/features/stage/bundle/widget_bundle_writer.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_yaml_parser.dart';

const _assetsDir = 'assets/stage/widgets/rive';
const _manifestRelative = 'manifest.yaml';
const _outputRelative = 'tachometer.wcrux-widget';

const _readme = '''
# Tachometer — reference Stage widget bundle

This `.wcrux-widget` archive is the packaging artifact for the open-core
Tachometer reference widget. It is not the widget's loading path — the
widget is registered directly by `registerBuiltinStageWidgets()` — but
exists as a reference artifact for community widget authors studying the
`.wcrux-widget` layout.

Layout inside this archive matches the spec
(`lib/features/stage/bundle/widget_bundle_spec.dart`):

```
manifest.yaml          # the manifest below
runtime/tachometer.riv # Rive runtime asset
README.md              # this file
```

See the editor contract in `assets/stage/widgets/rive/README.md` (in the
source tree) for the state-machine name and named-input contract.
''';

Future<void> main() async {
  const manifestPath = '$_assetsDir/$_manifestRelative';
  const outputPath = '$_assetsDir/$_outputRelative';

  final manifestSource = File(manifestPath).readAsStringSync();
  final manifest = parseStageWidgetManifest(manifestSource);
  print('Parsed manifest: ${manifest.id} v${manifest.version}');

  final runtimeAssetPath = '$_assetsDir/${manifest.runtimeAssetPath}';
  final runtimeFile = File(runtimeAssetPath);
  if (!runtimeFile.existsSync()) {
    stderr.writeln(
      'Runtime asset "$runtimeAssetPath" does not exist. The placeholder '
      'must be present even when zero-byte; see '
      'assets/stage/widgets/rive/README.md.',
    );
    exitCode = 1;
    return;
  }
  final runtimeBytes = Uint8List.fromList(runtimeFile.readAsBytesSync());
  print(
    'Read runtime asset: ${manifest.runtimeAssetPath} '
    '(${runtimeBytes.length} bytes)',
  );

  const writer = WidgetBundleWriter();
  final outputFile = await writer.writeToFile(
    path: outputPath,
    manifest: manifest,
    runtimeAssetBytes: runtimeBytes,
    readme: _readme,
  );
  print('Wrote bundle: ${outputFile.path}');
}
