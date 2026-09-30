// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/services/decoders/ahb_lite_decoder.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';
import 'package:wavecrux/services/decoders/axi4lite_decoder.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';
import 'package:wavecrux/services/decoders/isa/riscv_decoder.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';
import 'package:wavecrux/services/decoders/uart_decoder.dart';
import 'package:wavecrux/services/decoders/wishbone_decoder.dart';

/// In-app help links must land on a page and a section that exist.
///
/// A link to a missing page is a 404 the user only meets by clicking it, so
/// every documentation URL is resolved against the MkDocs sources that
/// publish `docs.wavecrux.app`: the path names a `docs-site/docs/<page>.md`
/// file and the fragment an explicit `{ #id }` heading or `id="…"` marker on
/// that page.
void main() {
  final docsUrls = <String, String>{
    'docs': HelpUrls.docs,
    for (final id in HelpUrls.documentedDecoderIds)
      'decoder($id)': HelpUrls.decoder(id),
    'sigrokDecoders': HelpUrls.sigrokDecoders,
    'decoderPlugins': HelpUrls.decoderPlugins,
    'decoderPluginsInstall': HelpUrls.decoderPluginsInstall,
    'decoderPluginsSecurity': HelpUrls.decoderPluginsSecurity,
    'stage': HelpUrls.stage,
    'translateFilters': HelpUrls.translateFilters,
    'remoteApi': HelpUrls.remoteApi,
    'patternSearch': HelpUrls.patternSearch,
    'diff': HelpUrls.diff,
  };

  for (final MapEntry(key: name, value: url) in docsUrls.entries) {
    test('$name resolves to a docs-site page and anchor', () {
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, 'docs.wavecrux.app');
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      expect(segments.length, lessThanOrEqualTo(1), reason: url);
      final page = segments.isEmpty ? 'index' : segments.single;
      final file = File('docs-site/docs/$page.md');
      expect(file.existsSync(), isTrue, reason: '$url has no ${file.path}');
      if (uri.fragment.isEmpty) return;
      final source = file.readAsStringSync();
      final anchor = RegExp.escape(uri.fragment);
      expect(
        RegExp('\\{ #$anchor \\}|id="$anchor"').hasMatch(source),
        isTrue,
        reason: '$url: ${file.path} has no #${uri.fragment}',
      );
    });
  }

  test('every open-core decoder links to its own entry', () {
    final ids = [
      SpiDecoder.decoderDefinition.id,
      I2cDecoder.decoderDefinition.id,
      UartDecoder.decoderDefinition.id,
      Axi4LiteDecoder.decoderDefinition.id,
      ApbDecoder.decoderDefinition.id,
      AhbLiteDecoder.decoderDefinition.id,
      WishboneDecoder.decoderDefinition.id,
      SpiFlashDecoder.decoderDefinition.id,
      RiscvDecoder.decoderDefinition.id,
    ];
    for (final id in ids) {
      expect(
        HelpUrls.decoder(id),
        'https://docs.wavecrux.app/protocol-decoders#$id',
      );
    }
  });

  test('plugin decoders link to the guide that covers them', () {
    expect(HelpUrls.decoder('sigrok.jtag'), HelpUrls.sigrokDecoders);
    expect(HelpUrls.decoder('examples.onewire'), HelpUrls.decoderPlugins);
  });

  test('non-documentation links point at the live pages', () {
    expect(HelpUrls.privacyPolicy, 'https://edacrux.app/privacy');
    expect(HelpUrls.termsOfService, 'https://edacrux.app/terms');
    // The listing URL needs the numeric app id; without it the store 404s.
    expect(
      HelpUrls.appStore,
      matches(RegExp(r'^https://apps\.apple\.com/app/wavecrux/id\d+$')),
    );
  });
}
