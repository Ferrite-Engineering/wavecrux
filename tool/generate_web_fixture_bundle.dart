// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// tool/generate_web_fixture_bundle.dart
//
// Emits `integration_test/web/web_fixture_bundle.g.dart` — the base64-embedded
// fixture corpus the Chrome-headless cross-bridge suite loads through
// `WellenWasmProvider`, plus the legacy LXT/LXT2 captures the web
// convert-on-open suite feeds through the `lxt2fst` WASM converter.
//
// Why embed instead of `rootBundle` assets or `fetch()`:
//
//   * A `flutter drive -d web-server` test runs in a real browser with no
//     `dart:io` — it cannot read `test/fixtures/*` off disk.
//   * Declaring the fixtures as pubspec `assets:` would ship every test VCD/
//     FST/GHW inside the production web bundle. Unacceptable.
//   * `fetch()` from the web-server would couple the test to a served path and
//     a running HTTP origin.
//
// Base64-embedding the (tiny — KB-scale) fixtures into a generated Dart source
// keeps them out of the app bundle, works in-browser with zero I/O, and is
// fully deterministic. The corpus is small enough that the generated file
// stays well under a few hundred KB.
//
// Each entry also carries the committed `.expected.json` companion (the Layer 1
// cross-bridge gold). FST entries reuse their VCD mirror's companion: the FST
// is a `vcd2fst` mirror of the same waveform, so `WellenWasmProvider` reading
// the FST must reproduce the identical per-path answers — a genuine
// cross-format + cross-bridge check.
//
// Pure `dart:io` / `dart:convert` — no Flutter, no FFI. Run with:
//
//   dart run tool/generate_web_fixture_bundle.dart
//
// Regenerate whenever a fixture or its `.expected.json` companion changes.

import 'dart:convert';
import 'dart:io';

/// One fixture to embed: `(name, fixturePath, companionPath, format)`.
///
/// `companionPath` is the committed `.expected.json` gold. FST entries point at
/// the VCD mirror's companion on purpose (same waveform, matched by path).
const _entries = <(String, String, String, String)>[
  // ── VCD (hand-authored companions, except direction_test which is FFI-gen) ──
  (
    'scalar_basics',
    'test/fixtures/vcd/scalar_basics.vcd',
    'test/fixtures/vcd/scalar_basics.expected.json',
    'VCD',
  ),
  (
    'vector_formats',
    'test/fixtures/vcd/vector_formats.vcd',
    'test/fixtures/vcd/vector_formats.expected.json',
    'VCD',
  ),
  (
    'analog_real',
    'test/fixtures/vcd/analog_real.vcd',
    'test/fixtures/vcd/analog_real.expected.json',
    'VCD',
  ),
  (
    'deep_hierarchy',
    'test/fixtures/vcd/deep_hierarchy.vcd',
    'test/fixtures/vcd/deep_hierarchy.expected.json',
    'VCD',
  ),
  (
    'direction_test',
    'test/fixtures/vcd/direction_test.vcd',
    'test/fixtures/vcd/direction_test.expected.json',
    'VCD',
  ),
  // ── FST mirrors (companion = the VCD mirror's gold) ──
  (
    'scalar_basics',
    'test/fixtures/fst/scalar_basics.fst',
    'test/fixtures/vcd/scalar_basics.expected.json',
    'FST',
  ),
  (
    'vector_formats',
    'test/fixtures/fst/vector_formats.fst',
    'test/fixtures/vcd/vector_formats.expected.json',
    'FST',
  ),
  (
    'analog_real',
    'test/fixtures/fst/analog_real.fst',
    'test/fixtures/vcd/analog_real.expected.json',
    'FST',
  ),
  (
    'deep_hierarchy',
    'test/fixtures/fst/deep_hierarchy.fst',
    'test/fixtures/vcd/deep_hierarchy.expected.json',
    'FST',
  ),
  (
    'direction_test',
    'test/fixtures/fst/direction_test.fst',
    'test/fixtures/vcd/direction_test.expected.json',
    'FST',
  ),
  // ── GHW (FFI-generated companion) ──
  (
    'vhdl_types',
    'test/fixtures/ghw/vhdl_types.ghw',
    'test/fixtures/ghw/vhdl_types.expected.json',
    'GHW',
  ),
];

/// Legacy LXT/LXT2 captures, embedded as a separate list: wellen cannot read
/// them, so they go through the `lxt2fst` WASM converter first
/// (`web_legacy_lxt_open_test.dart`) and must stay out of the cross-bridge
/// sweep over [_entries]. Each companion is the ground truth recorded from the
/// capture's source VCD (see `test/fixtures/legacy/README.md`).
const _legacyEntries = <(String, String, String, String)>[
  (
    'simple_counter',
    'test/fixtures/legacy/simple_counter.lxt2',
    'test/fixtures/legacy/simple_counter.expected.json',
    'LXT2',
  ),
  (
    'simple_counter',
    'test/fixtures/legacy/simple_counter.lxt',
    'test/fixtures/legacy/simple_counter.expected.json',
    'LXT',
  ),
  (
    'multi_scope',
    'test/fixtures/legacy/multi_scope.lxt2',
    'test/fixtures/legacy/multi_scope.expected.json',
    'LXT2',
  ),
  (
    'vector_signals',
    'test/fixtures/legacy/vector_signals.lxt2',
    'test/fixtures/legacy/vector_signals.expected.json',
    'LXT2',
  ),
];

const _output = 'integration_test/web/web_fixture_bundle.g.dart';

void main() {
  final buf = StringBuffer()
    ..writeln('// GENERATED FILE — DO NOT EDIT BY HAND.')
    ..writeln('//')
    ..writeln('// Regenerate with:')
    ..writeln('//   dart run tool/generate_web_fixture_bundle.dart')
    ..writeln('//')
    ..writeln(
      '// Source: the committed VCD/FST/GHW/LXT/LXT2 fixtures under test/fixtures/',
    )
    ..writeln(
      '// and their .expected.json companions. See the generator for the',
    )
    ..writeln('// rationale behind base64-embedding rather than assets/fetch.')
    ..writeln(
      '// ignore_for_file: lines_longer_than_80_chars, public_member_api_docs',
    )
    ..writeln()
    ..writeln("import 'dart:convert';")
    ..writeln("import 'dart:typed_data';")
    ..writeln()
    ..writeln(
      '/// One embedded waveform fixture plus its Layer 1 cross-bridge gold.',
    )
    ..writeln('class WebFixture {')
    ..writeln('  const WebFixture({')
    ..writeln('    required this.name,')
    ..writeln('    required this.displayName,')
    ..writeln('    required this.format,')
    ..writeln('    required this.bytesB64,')
    ..writeln('    required this.expectedJson,')
    ..writeln('  });')
    ..writeln()
    ..writeln('  /// Fixture base name, e.g. `scalar_basics`.')
    ..writeln('  final String name;')
    ..writeln()
    ..writeln('  /// Browser-facing file name with extension, used by')
    ..writeln('  /// [openBytes] for extension-based format detection.')
    ..writeln('  final String displayName;')
    ..writeln()
    ..writeln(
      '  /// `VCD` | `FST` | `GHW`, or `LXT` | `LXT2` in [kWebLegacyFixtures].',
    )
    ..writeln('  final String format;')
    ..writeln()
    ..writeln('  final String bytesB64;')
    ..writeln('  final String expectedJson;')
    ..writeln()
    ..writeln('  /// Raw file bytes, decoded on demand.')
    ..writeln('  Uint8List get bytes => base64Decode(bytesB64);')
    ..writeln()
    ..writeln('  /// Parsed `.expected.json` companion, decoded on demand.')
    ..writeln('  Map<String, dynamic> get expected =>')
    ..writeln('      jsonDecode(expectedJson) as Map<String, dynamic>;')
    ..writeln('}')
    ..writeln()
    ..writeln('/// Every fixture × format the cross-bridge suite exercises.')
    ..writeln('const List<WebFixture> kWebFixtures = [');
  _writeEntries(buf, _entries);
  buf
    ..writeln('];')
    ..writeln()
    ..writeln(
      '/// Legacy LXT/LXT2 captures for the web convert-on-open suite; their',
    )
    ..writeln('/// companions are the source VCD ground truth.')
    ..writeln('const List<WebFixture> kWebLegacyFixtures = [');
  _writeEntries(buf, _legacyEntries);
  buf.writeln('];');

  File(_output).writeAsStringSync(buf.toString());
  stdout.writeln(
    'Wrote $_output (${_entries.length} fixtures, '
    '${_legacyEntries.length} legacy).',
  );
}

void _writeEntries(
  StringBuffer buf,
  List<(String, String, String, String)> entries,
) {
  for (final (name, fixturePath, companionPath, format) in entries) {
    final fixtureFile = File(fixturePath);
    final companionFile = File(companionPath);
    if (!fixtureFile.existsSync()) {
      stderr.writeln('MISSING fixture: $fixturePath');
      exitCode = 1;
      continue;
    }
    if (!companionFile.existsSync()) {
      stderr.writeln('MISSING companion: $companionPath');
      exitCode = 1;
      continue;
    }
    final bytesB64 = base64Encode(fixtureFile.readAsBytesSync());
    // Re-encode the companion compactly so the embedded literal is stable
    // and free of incidental whitespace churn.
    final expectedJson = jsonEncode(
      jsonDecode(companionFile.readAsStringSync()),
    );
    final ext = fixturePath.split('.').last;
    final displayName = '$name.$ext';
    buf
      ..writeln('  WebFixture(')
      ..writeln("    name: '$name',")
      ..writeln("    displayName: '$displayName',")
      ..writeln("    format: '$format',")
      ..writeln("    bytesB64: '$bytesB64',")
      ..writeln('    expectedJson: ${_dartStringLiteral(expectedJson)},')
      ..writeln('  ),');
  }
}

/// Encodes [s] as a single-quoted Dart string literal, escaping the few
/// characters that matter inside one (`\`, `'`, `$`, and newlines). The JSON
/// companion text never contains literal newlines (jsonEncode escapes them),
/// but we guard anyway.
String _dartStringLiteral(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}
