// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: the pure-Dart VCD parser
/// (`DartVcdProvider`), the runtime parser-backend override
/// (`WaveformProviderMode`, `waveformProviderOverrideProvider`,
/// `ProviderOverridePanel`), and the dual-parser comparison surface
/// (`ParserComparisonService`, `parserComparisonProvider`,
/// `ParserComparisonResult`) are retired. This test fails fast if any of
/// those identifiers reappear in production code.
///
/// Background: WaveCrux uses
/// `WellenProvider` on desktop/mobile and `WellenWasmProvider` on the
/// web — one backend per platform, no fallback. The Layer 1 cross-parser
/// validation has been restated as FFI-vs-WASM validation (see
/// ARCHITECTURE.md §8.9) so the comparison-runtime UI no longer exists.
void main() {
  test('no production code references the retired DartVcdProvider', () async {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'expected lib/ at repo root');

    const banned = <String>[
      'DartVcdProvider',
      'dart_vcd_provider',
      'WaveformProviderMode',
      'waveformProviderOverride',
      'waveform_provider_override_provider',
      'ProviderOverridePanel',
      'provider_override_panel',
      'ParserComparisonService',
      'parser_comparison_service',
      'ParserComparisonResult',
      'ParserComparisonNotifier',
      'parserComparisonProvider',
      'parser_comparison_provider',
      'kParserBackendWellen',
      'kParserBackendDart',
    ];

    final offenders = <String>[];
    await _scan(lib, banned, offenders);

    expect(
      offenders,
      isEmpty,
      reason:
          'The pure-Dart VCD parser, the runtime '
          'parser-backend override, and the dual-parser comparison surface are retired. '
          'Re-introducing any of these in production code is a regression — '
          'fix:\n  ${offenders.join('\n  ')}',
    );
  });

  test('no test code re-imports the retired DartVcdProvider source', () async {
    final tests = Directory('test');
    expect(tests.existsSync(), isTrue, reason: 'expected test/ at repo root');

    const bannedInTests = <String>[
      'DartVcdProvider',
      'dart_vcd_provider',
      // The override mechanism is also gone from tests.
      'waveformProviderOverride',
      'WaveformProviderMode',
      // The comparison surface is also gone from tests.
      'ParserComparisonResult',
      'parserComparisonProvider',
      'ParserComparisonService',
    ];

    const selfReferenceAllowlist = <String>{
      'test/static/no_dart_vcd_parser_test.dart',
    };

    final offenders = <String>[];
    await for (final entity in tests.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(Platform.pathSeparator, '/');
      if (selfReferenceAllowlist.contains(rel)) continue;
      final contents = entity.readAsStringSync();
      for (final needle in bannedInTests) {
        if (contents.contains(needle)) {
          offenders.add('${entity.path}: contains "$needle"');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The Dart VCD parser and dual-parser UI are retired. '
          'Test files must no longer reference them — migrate the test to '
          'WellenProvider (and WellenWasmProvider on web). Offenders:\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}

Future<void> _scan(
  Directory root,
  List<String> banned,
  List<String> offenders,
) async {
  await for (final entity in root.list(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final contents = entity.readAsStringSync();
    for (final needle in banned) {
      if (contents.contains(needle)) {
        offenders.add('${entity.path}: contains "$needle"');
      }
    }
  }
}
