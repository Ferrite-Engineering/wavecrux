// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the committed community `.wcrux-widget` test fixture used to
// exercise the generic custom-widget render bridge (CommunityRiveStageRenderer
// + custom_widget_bundle_manager renderer registration).
//
// Run from the repository root any time the manifest shape or the reused
// runtime asset changes:
//
//   dart run tool/generate_community_widget_fixture.dart
//
// Output:
//
//   test/fixtures/stage/community_widget/community_gauge.wcrux-widget
//
// Unlike the curated Tachometer (which is registered directly via
// `extraStageWidgetsProvider` and rendered by its bespoke
// `TachometerStageRenderer`), this fixture is a *community* bundle: a
// manifest + `.riv` with no bundled Dart. It deliberately reuses the
// authored `assets/stage/widgets/rive/runtime/tachometer.riv` artboard —
// whose DEFAULT state machine exposes the `rpm` (Number), `redline`
// (Boolean) and `shift` (Boolean) inputs — so that loading the bundle and
// dropping it on a Stage panel drives the artboard live through the generic
// runtime (default-state-machine resolution + manifest-driven input
// routing), with no Tachometer-specific code in the path.
//
// Headless `flutter test` cannot mount the artboard (rive_native FFI is
// unavailable), so the live-render assertion lives in integration_test +
// the manual verification pass (Open Core verification §10). This fixture
// gives that path a real manifest + `.riv` to load.
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_writer.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_parameter.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';

const _reusedRivePath = 'assets/stage/widgets/rive/runtime/tachometer.riv';
const _outputDir = 'test/fixtures/stage/community_widget';
const _outputRelative = 'community_gauge.wcrux-widget';

final _manifest = StageWidgetManifest(
  id: 'com.wavecrux.test.community_gauge',
  version: '1.0.0',
  displayName: LocalizedString.localized(const {
    'en': 'Community Gauge',
    'zh': '社区仪表',
    'zh_CN': '社区仪表',
    'ja': 'コミュニティゲージ',
    'ko': '커뮤니티 게이지',
  }),
  category: StageWidgetCategory.instrument,
  runtime: ManifestRuntime.rive,
  // Bundle-relative; reuses the authored Tachometer artboard bytes.
  runtimeAssetPath: 'runtime/community_gauge.riv',
  requiredApiVersion: 1,
  signalBindings: const [
    ManifestSignalBinding(
      name: 'rpm',
      description:
          'Drives the gauge needle; mapped 0..255 → 0.0..1.0 and '
          'written to the artboard default state machine\'s "rpm" Number '
          'input. (Tuned to stage_demo.vcd\'s 8-bit ramp so the needle '
          'sweeps the full dial in the verification demo.)',
      signalType: SignalType.vector,
      bitWidth: BitWidthRange(min: 1),
    ),
    ManifestSignalBinding(
      name: 'redline',
      description:
          'Boolean redline indicator written to the "redline" '
          'Boolean input.',
      signalType: SignalType.scalar,
    ),
    ManifestSignalBinding(
      name: 'shift',
      description: 'Boolean shift pulse written to the "shift" Boolean input.',
      signalType: SignalType.scalar,
    ),
  ],
  parameters: const [
    ManifestParameter(
      binding: 'rpm',
      normalizer: LinearNormalizer(inputMin: 0, inputMax: 255),
    ),
  ],
);

const _readme = '''
# Community Gauge — custom-widget render-bridge test fixture

A *community* `.wcrux-widget` bundle (manifest + `.riv`, no bundled Dart)
used to exercise the generic custom-widget render bridge. It reuses the
authored Tachometer artboard, whose default state machine exposes `rpm`
(Number), `redline` (Boolean) and `shift` (Boolean) inputs matching the
manifest bindings below. Loading this bundle and dropping it on a Stage
panel drives the artboard live through the generic runtime — no
Tachometer-specific code in the path.

Regenerate with: `dart run tool/generate_community_widget_fixture.dart`
''';

Future<void> main() async {
  final riveFile = File(_reusedRivePath);
  if (!riveFile.existsSync()) {
    stderr.writeln('Reused runtime asset "$_reusedRivePath" does not exist.');
    exitCode = 1;
    return;
  }
  final runtimeBytes = Uint8List.fromList(riveFile.readAsBytesSync());
  print('Read reused .riv: $_reusedRivePath (${runtimeBytes.length} bytes)');

  Directory(_outputDir).createSync(recursive: true);
  const writer = WidgetBundleWriter();
  final outputFile = await writer.writeToFile(
    path: '$_outputDir/$_outputRelative',
    manifest: _manifest,
    runtimeAssetBytes: runtimeBytes,
    readme: _readme,
  );
  print('Wrote community fixture bundle: ${outputFile.path}');
}
