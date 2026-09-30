// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Covers the discovery-based asset loader: manifest discovery under both
// the bare and the `packages/wavecrux/` prefix (the Pro path-dependency
// case), the canonical load order, per-file failure isolation, and the
// architecture parameter.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';

/// Installs a fake `AssetManifest.bin` + string assets on the root bundle
/// message channel, so `IsaDecoderAssets.loadFromBundle` sees exactly
/// [assets] (key → contents) and nothing else.
void _installFakeBundle(Map<String, String> assets) {
  final manifest = <String, Object>{
    for (final key in assets.keys) key: <Object>[],
  };
  final manifestBytes = const StandardMessageCodec().encodeMessage(manifest)!;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = const StringCodec().decodeMessage(message);
        if (key == 'AssetManifest.bin') return manifestBytes;
        final contents = assets[key];
        if (contents == null) return null;
        final bytes = Uint8List.fromList(utf8.encode(contents));
        return ByteData.view(bytes.buffer);
      });
}

String _toml(String name) =>
    File('$kIsaDecoderAssetRoot/riscv/$name.toml').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    rootBundle.clear();
  });

  group('IsaDecoderAssets.loadFromBundle', () {
    test('discovers every TOML under the bare asset prefix', () async {
      _installFakeBundle({
        '$kIsaDecoderAssetRoot/riscv/RV64I.toml': _toml('RV64I'),
        '$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml('RV32I'),
        '$kIsaDecoderAssetRoot/riscv/RV32M.toml': _toml('RV32M'),
        'assets/images/logo.png': 'not a toml',
      });

      final assets = await IsaDecoderAssets.loadFromBundle();

      expect(assets.architecture, kDefaultIsaArchitecture);
      expect(assets.availableSets, ['RV32I', 'RV32M', 'RV64I']);
      expect(assets.get('RV32I'), isA<InstructionSet>());
    });

    test(
      'falls back to the packages/wavecrux/ prefix (Pro path dep)',
      () async {
        _installFakeBundle({
          'packages/wavecrux/$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml(
            'RV32I',
          ),
          'packages/wavecrux/$kIsaDecoderAssetRoot/riscv/RV64I.toml': _toml(
            'RV64I',
          ),
        });

        final assets = await IsaDecoderAssets.loadFromBundle();

        expect(assets.availableSets, ['RV32I', 'RV64I']);
      },
    );

    test('prefers the bare prefix when both are present', () async {
      _installFakeBundle({
        '$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml('RV32I'),
        'packages/wavecrux/$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml(
          'RV32I',
        ),
        'packages/wavecrux/$kIsaDecoderAssetRoot/riscv/RV64I.toml': _toml(
          'RV64I',
        ),
      });

      // The bare prefix carries only RV32I, so picking it is observable.
      final assets = await IsaDecoderAssets.loadFromBundle();
      expect(assets.availableSets, ['RV32I']);
    });

    test('returns the sets in canonical load order regardless of manifest '
        'iteration order', () async {
      // Manifest insertion order deliberately inverted.
      _installFakeBundle({
        '$kIsaDecoderAssetRoot/riscv/RV64M.toml': _toml('RV64M'),
        '$kIsaDecoderAssetRoot/riscv/RV64I.toml': _toml('RV64I'),
        '$kIsaDecoderAssetRoot/riscv/RV32M.toml': _toml('RV32M'),
        '$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml('RV32I'),
      });

      final assets = await IsaDecoderAssets.loadFromBundle();

      expect(assets.availableSets, ['RV32I', 'RV32M', 'RV64I', 'RV64M']);
    });

    test('isolates per-file parse failures', () async {
      _installFakeBundle({
        '$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml('RV32I'),
        '$kIsaDecoderAssetRoot/riscv/RV32BROKEN.toml': 'this is not toml [[[',
      });

      final assets = await IsaDecoderAssets.loadFromBundle();

      expect(assets.availableSets, ['RV32I']);
      expect(assets.get('RV32BROKEN'), isNull);
    });

    test('ignores nested directories and non-TOML files', () async {
      _installFakeBundle({
        '$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml('RV32I'),
        '$kIsaDecoderAssetRoot/riscv/NOTICE.md': '# notice',
        '$kIsaDecoderAssetRoot/riscv/nested/RV64I.toml': _toml('RV64I'),
      });

      final assets = await IsaDecoderAssets.loadFromBundle();

      expect(assets.availableSets, ['RV32I']);
    });

    test('honors the architecture parameter', () async {
      _installFakeBundle({
        '$kIsaDecoderAssetRoot/riscv/RV32I.toml': _toml('RV32I'),
        '$kIsaDecoderAssetRoot/other/RV32M.toml': _toml('RV32M'),
      });

      final assets = await IsaDecoderAssets.loadFromBundle(
        architecture: 'other',
      );

      expect(assets.architecture, 'other');
      expect(assets.availableSets, ['RV32M']);
    });

    test('degrades to an empty cache when nothing is bundled', () async {
      _installFakeBundle({'assets/images/logo.png': 'x'});

      final assets = await IsaDecoderAssets.loadFromBundle();

      expect(assets.availableSets, isEmpty);
    });
  });

  group('IsaDecoderAssets.fromMap', () {
    test('re-sorts into canonical load order', () {
      final assets = IsaDecoderAssets.fromMap({
        'RV64I': parseInstructionSetToml(_toml('RV64I')),
        'RV32I': parseInstructionSetToml(_toml('RV32I')),
      });

      expect(assets.availableSets, ['RV32I', 'RV64I']);
      expect(assets.architecture, kDefaultIsaArchitecture);
    });
  });
}
