// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/bundle/loaded_widget_bundle.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_failure.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_reader.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_spec.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_writer.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_parameter.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';

StageWidgetManifest _minimalManifest() => const StageWidgetManifest(
  id: 'com.acme.minimal',
  version: '1.0.0',
  displayName: LocalizedString.single('Minimal'),
  category: StageWidgetCategory.instrument,
  runtime: ManifestRuntime.rive,
  runtimeAssetPath: 'runtime/minimal.riv',
  requiredApiVersion: 1,
);

StageWidgetManifest _fullManifest() => const StageWidgetManifest(
  id: 'com.acme.full',
  version: '2.5.1',
  displayName: LocalizedString.single('Full Featured'),
  category: StageWidgetCategory.peripheral,
  runtime: ManifestRuntime.rive,
  runtimeAssetPath: 'runtime/full.riv',
  requiredApiVersion: 1,
  iconAssetPath: 'assets/icon.png',
  signalBindings: [
    ManifestSignalBinding(
      name: 'speed',
      description: 'shaft speed',
      signalType: SignalType.vector,
      bitWidth: BitWidthRange(min: 8, max: 32),
    ),
  ],
  parameters: [
    ManifestParameter(
      binding: 'speed',
      normalizer: LinearNormalizer(
        inputMin: 0,
        inputMax: 1024,
      ),
    ),
  ],
);

StageWidgetManifest _localeManifest() => StageWidgetManifest(
  id: 'com.acme.locale',
  version: '0.9.0',
  displayName: LocalizedString.localized(const {
    'en': 'Gauge Cluster',
    'ja': 'ゲージクラスター',
    'zh_CN': '仪表板',
    'ko': '게이지 클러스터',
  }),
  category: StageWidgetCategory.instrument,
  runtime: ManifestRuntime.painter,
  runtimeAssetPath: 'runtime/gauge_painter',
  requiredApiVersion: 1,
);

void main() {
  late WidgetBundleWriter writer;

  setUp(() {
    writer = const WidgetBundleWriter();
  });

  Future<LoadedWidgetBundle> readBytes(
    Uint8List bytes,
    String virtualPath,
  ) {
    final r = WidgetBundleReader(
      fileReader: (_) async => bytes,
    );
    return r.read(virtualPath);
  }

  test('round-trip: minimal manifest preserves every field', () async {
    final manifest = _minimalManifest();
    final bytes = writer.buildBytes(
      manifest: manifest,
      runtimeAssetBytes: Uint8List.fromList(List<int>.generate(64, (i) => i)),
    );

    final bundle = await readBytes(bytes, '/virtual/minimal.wcrux-widget');
    expect(bundle.manifest.id, manifest.id);
    expect(bundle.manifest.version, manifest.version);
    expect(bundle.manifest.runtimeAssetPath, manifest.runtimeAssetPath);
    expect(bundle.manifest.runtime, manifest.runtime);
    expect(bundle.manifest.signalBindings, isEmpty);
    expect(bundle.manifest.parameters, isEmpty);
    expect(bundle.hasAsset(WidgetBundleSpec.manifestEntryName), isTrue);
    expect(bundle.hasAsset(manifest.runtimeAssetPath), isTrue);
  });

  test('round-trip: full manifest preserves bindings and parameters', () async {
    final manifest = _fullManifest();
    final bytes = writer.buildBytes(
      manifest: manifest,
      runtimeAssetBytes: Uint8List.fromList(const [1, 2, 3, 4]),
      assetEntries: {
        'assets/icon.png': Uint8List.fromList(const [0xff, 0xd8, 0xff]),
      },
    );
    final bundle = await readBytes(bytes, '/virtual/full.wcrux-widget');
    expect(bundle.manifest.signalBindings, hasLength(1));
    expect(bundle.manifest.signalBindings.first.bitWidth?.min, 8);
    expect(bundle.manifest.signalBindings.first.bitWidth?.max, 32);
    expect(bundle.manifest.parameters, hasLength(1));
    expect(
      bundle.manifest.parameters.first.normalizer,
      isA<LinearNormalizer>(),
    );
    expect(bundle.hasAsset('assets/icon.png'), isTrue);
    expect(bundle.readAsset('assets/icon.png'), [0xff, 0xd8, 0xff]);
  });

  test(
    'round-trip: locale-map display name preserves all four locales',
    () async {
      final manifest = _localeManifest();
      final bytes = writer.buildBytes(
        manifest: manifest,
        runtimeAssetBytes: Uint8List.fromList(const [42]),
      );
      final bundle = await readBytes(bytes, '/virtual/locale.wcrux-widget');
      final dn = bundle.manifest.displayName;
      expect(dn.resolve('en'), 'Gauge Cluster');
      expect(dn.resolve('ja'), 'ゲージクラスター');
      expect(dn.resolve('zh_CN'), '仪表板');
      expect(dn.resolve('ko'), '게이지 클러스터');
    },
  );

  test('writer rejects manifests whose runtime path is outside runtime/', () {
    expect(
      () => writer.buildBytes(
        manifest: _minimalManifest().copyWithRuntimePath(
          'outside/somewhere.riv',
        ),
        runtimeAssetBytes: Uint8List(4),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('reader: security violations are rejected with distinct kinds', () {
    test('parent-traversal entry → pathTraversal', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'manifest.yaml',
            8,
            const [104, 105, 32, 32, 32, 32, 32, 32], // 'hi      '
          ),
        )
        ..addFile(ArchiveFile('../escape.txt', 4, const [1, 2, 3, 4]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final r = WidgetBundleReader(
        fileReader: (_) async => bytes,
      );
      try {
        await r.read('/virtual/bad.wcrux-widget');
        fail('expected WidgetBundleException');
      } on WidgetBundleException catch (e) {
        expect(e.kind, WidgetBundleFailureKind.pathTraversal);
      }
    });

    test('absolute-path entry → pathTraversal', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('/etc/passwd', 4, const [1, 2, 3, 4]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final r = WidgetBundleReader(fileReader: (_) async => bytes);
      try {
        await r.read('/virtual/bad.wcrux-widget');
        fail('expected WidgetBundleException');
      } on WidgetBundleException catch (e) {
        expect(e.kind, WidgetBundleFailureKind.pathTraversal);
      }
    });

    test('symbolic link entry → symlinkRejected', () async {
      // Synthesise an archive containing a symlink entry by injecting a
      // custom decoder. ZipEncoder rejects symlinks with empty content;
      // bypassing the encoder lets the loader's symlink check actually
      // run.
      final synthetic = Archive()
        ..addFile(ArchiveFile.symlink('runtime/sym.riv', '/etc/passwd'));
      final r = WidgetBundleReader(
        fileReader: (_) async => Uint8List(8),
        archiveDecoder: (_) => synthetic,
      );
      try {
        await r.read('/virtual/sym.wcrux-widget');
        fail('expected WidgetBundleException');
      } on WidgetBundleException catch (e) {
        expect(e.kind, WidgetBundleFailureKind.symlinkRejected);
      }
    });

    test('oversize archive → oversize', () async {
      // 33 MiB single entry exceeds the 32 MiB cap.
      final big = Uint8List(33 * 1024 * 1024);
      final manifest = _minimalManifest();
      final manifestBytes = const WidgetBundleWriter().buildBytes(
        manifest: manifest,
        runtimeAssetBytes: big,
      );
      // Note: ZIP compression on zeros is highly effective so the raw
      // bytes-on-disk are tiny — but the *uncompressed* size is what the
      // reader checks.
      final r = WidgetBundleReader(fileReader: (_) async => manifestBytes);
      try {
        await r.read('/virtual/big.wcrux-widget');
        fail('expected WidgetBundleException');
      } on WidgetBundleException catch (e) {
        expect(e.kind, WidgetBundleFailureKind.oversize);
      }
    });

    test('manifest missing → manifestMissing', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('runtime/foo.riv', 4, const [1, 2, 3, 4]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final r = WidgetBundleReader(fileReader: (_) async => bytes);
      try {
        await r.read('/virtual/no-manifest.wcrux-widget');
        fail('expected WidgetBundleException');
      } on WidgetBundleException catch (e) {
        expect(e.kind, WidgetBundleFailureKind.manifestMissing);
      }
    });

    test('runtime asset missing → runtimeAssetMissing', () async {
      // Manifest references runtime/missing.riv but archive does not
      // contain that entry.
      final manifest = _minimalManifest().copyWithRuntimePath(
        'runtime/missing.riv',
      );
      // Build directly without using writer (writer requires the bytes).
      final manifestYaml = StringBuffer()
        ..writeln('id: ${manifest.id}')
        ..writeln('version: ${manifest.version}')
        ..writeln('display_name: ${manifest.displayName.resolve('en')}')
        ..writeln('category: instrument')
        ..writeln('runtime: rive')
        ..writeln('runtime_asset_path: ${manifest.runtimeAssetPath}')
        ..writeln('required_api_version: ${manifest.requiredApiVersion}');
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            WidgetBundleSpec.manifestEntryName,
            manifestYaml.length,
            manifestYaml.toString().codeUnits,
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final r = WidgetBundleReader(fileReader: (_) async => bytes);
      try {
        await r.read('/virtual/missing-runtime.wcrux-widget');
        fail('expected WidgetBundleException');
      } on WidgetBundleException catch (e) {
        expect(e.kind, WidgetBundleFailureKind.runtimeAssetMissing);
      }
    });

    test('not a zip → notAZipArchive', () async {
      // Inject a decoder that throws to simulate a corrupt archive
      // independently of how forgiving the real ZipDecoder is with tiny
      // garbage input.
      final r = WidgetBundleReader(
        fileReader: (_) async => Uint8List.fromList(const [0, 1, 2, 3, 4, 5]),
        archiveDecoder: (_) => throw const FormatException('not a ZIP'),
      );
      try {
        await r.read('/virtual/garbage.wcrux-widget');
        fail('expected WidgetBundleException');
      } on WidgetBundleException catch (e) {
        expect(e.kind, WidgetBundleFailureKind.notAZipArchive);
      }
    });
  });
}

extension on StageWidgetManifest {
  StageWidgetManifest copyWithRuntimePath(String path) => StageWidgetManifest(
    id: id,
    version: version,
    displayName: displayName,
    category: category,
    runtime: runtime,
    runtimeAssetPath: path,
    requiredApiVersion: requiredApiVersion,
    iconAssetPath: iconAssetPath,
    signalBindings: signalBindings,
    parameters: parameters,
  );
}
