// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the multi-decoder coexistence verification fixture used by the
// multi-decoder coexistence integration test and the manual verification guide §22.9
// ("Multi-decoder simultaneous correctness").
//
// Output:
//   verification/fixtures/protocol/multi/spi_i2c_basic.vcd
//   verification/fixtures/protocol/multi/spi_i2c_basic.spi.expected_transactions.json
//   verification/fixtures/protocol/multi/spi_i2c_basic.i2c.expected_transactions.json
//
// Usage:
//   dart run tool/generate_multi_coexistence_fixture.dart
//
// What it does:
//   Merges the two known-good single-bus fixtures —
//   `protocol/spi/generated/spi_basic.vcd` (SPI bus, 2 transactions) and
//   `protocol/i2c/generated/i2c_basic.vcd` (I²C bus, 2 transactions) — into a single
//   VCD with two sibling scopes (`spi_tb` and `i2c_tb`). The SPI signal
//   identifier codes are kept as-is; the I²C codes are remapped to a disjoint
//   set so the two buses never collide. Both timelines are interleaved by
//   timestamp.
//
//   Because the per-bus signal timelines are copied verbatim from the source
//   fixtures, decoding each bus over the combined file yields exactly the
//   transactions in the source `.expected_transactions.json` files — so the
//   companions are byte-for-byte copies of the originals (one per decoder).
//
// Re-run this after editing either source fixture so the combined file and
// its expected companions stay in sync.
//
// ignore_for_file: avoid_print

import 'dart:io';

/// A single VCD variable declaration.
class _Var {
  _Var({
    required this.kind,
    required this.width,
    required this.id,
    required this.name,
  });
  final String kind; // e.g. "wire"
  final int width;
  final String id; // single-character identifier code
  final String name;
}

/// The parsed contents of a flat single-scope scalar VCD fixture.
class _ParsedVcd {
  _ParsedVcd({
    required this.vars,
    required this.initial,
    required this.timeline,
  });

  /// Variable declarations, in file order.
  final List<_Var> vars;

  /// Initial `$dumpvars` value-change lines (already in `<value><id>` form).
  final List<String> initial;

  /// Time-ordered value changes: time → list of `<value><id>` change lines.
  final Map<int, List<String>> timeline;
}

/// Parses the limited VCD subset used by the SPI / I²C fixtures: a single
/// module scope of 1-bit scalars, a `$dumpvars` block, `#<time>` markers, and
/// scalar value-change lines (`0!`, `1"`, …). `$comment` blocks are skipped.
_ParsedVcd _parse(String path) {
  final lines = File(path).readAsLinesSync();
  final vars = <_Var>[];
  final initial = <String>[];
  final timeline = <int, List<String>>{};

  var inDumpvars = false;
  var inComment = false;
  int? currentTime;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (inComment) {
      if (line == r'$end') inComment = false;
      continue;
    }
    if (line.startsWith(r'$comment')) {
      if (!line.endsWith(r'$end')) inComment = true;
      continue;
    }
    if (line.startsWith(r'$var')) {
      // $var wire 1 ! sclk $end
      final parts = line.split(RegExp(r'\s+'));
      vars.add(
        _Var(
          kind: parts[1],
          width: int.parse(parts[2]),
          id: parts[3],
          name: parts[4],
        ),
      );
      continue;
    }
    if (line.startsWith(r'$dumpvars')) {
      inDumpvars = true;
      continue;
    }
    if (line == r'$end') {
      inDumpvars = false;
      continue;
    }
    if (line.startsWith(r'$')) {
      // $timescale / $scope / $upscope / $enddefinitions / $date / $version
      continue;
    }
    if (line.startsWith('#')) {
      currentTime = int.parse(line.substring(1));
      timeline.putIfAbsent(currentTime, () => <String>[]);
      continue;
    }

    // A scalar value-change line: <value><id>, e.g. "0!".
    if (inDumpvars) {
      initial.add(line);
    } else if (currentTime != null) {
      timeline[currentTime]!.add(line);
    }
  }

  return _ParsedVcd(vars: vars, initial: initial, timeline: timeline);
}

/// Remaps the identifier code of every change line and var in [parsed] from
/// the source id to a fresh disjoint id, returning the remapped copy.
_ParsedVcd _remap(_ParsedVcd parsed, Map<String, String> idMap) {
  String remapLine(String change) {
    // <value><id> — the id is the trailing single character.
    final value = change.substring(0, change.length - 1);
    final id = change.substring(change.length - 1);
    return '$value${idMap[id] ?? id}';
  }

  return _ParsedVcd(
    vars: [
      for (final v in parsed.vars)
        _Var(
          kind: v.kind,
          width: v.width,
          id: idMap[v.id] ?? v.id,
          name: v.name,
        ),
    ],
    initial: parsed.initial.map(remapLine).toList(),
    timeline: {
      for (final entry in parsed.timeline.entries)
        entry.key: entry.value.map(remapLine).toList(),
    },
  );
}

void main() {
  _generateSpiI2cFixture();
  _generateAllFiveFixture();
}

/// Generates the original SPI + I²C combined fixture.
///
/// Unchanged from the original single-purpose script — other tests
/// (`decoder_restore_on_open_test.dart`) depend on this exact two-bus file,
/// so it keeps its own dedicated (non-generalized) merge logic rather than
/// being folded into [_generateAllFiveFixture]'s N-source loop.
void _generateSpiI2cFixture() {
  const spiSrc = 'verification/fixtures/protocol/spi/generated/spi_basic.vcd';
  const i2cSrc = 'verification/fixtures/protocol/i2c/generated/i2c_basic.vcd';
  const spiExpected =
      'verification/fixtures/protocol/spi/generated/spi_basic.expected_transactions.json';
  const i2cExpected =
      'verification/fixtures/protocol/i2c/generated/i2c_basic.expected_transactions.json';

  final spi = _parse(spiSrc);
  final i2cRaw = _parse(i2cSrc);

  // Remap the I²C identifier codes to a set disjoint from the SPI codes.
  // SPI uses ! " # % ; assign the I²C signals fresh codes after them.
  final spiIds = spi.vars.map((v) => v.id).toSet();
  const candidates = ['&', "'", '(', ')', '*', '+', ',', '-', '.', '/'];
  final idMap = <String, String>{};
  var next = 0;
  for (final v in i2cRaw.vars) {
    while (spiIds.contains(candidates[next]) ||
        idMap.containsValue(candidates[next])) {
      next++;
    }
    idMap[v.id] = candidates[next];
    next++;
  }
  final i2c = _remap(i2cRaw, idMap);

  // Build the combined VCD.
  final out = <String>[
    r'$date',
    '  WaveCrux multi-decoder coexistence fixture',
    r'$end',
    r'$version',
    '  generate_multi_coexistence_fixture.dart',
    r'$end',
    r'$comment',
    '  Combined SPI + I2C bus fixture for multi-decoder',
    '  coexistence. The spi_tb scope is copied verbatim from',
    '  protocol/spi/generated/spi_basic.vcd (2 SPI transactions); the i2c_tb scope',
    '  is copied from protocol/i2c/generated/i2c_basic.vcd (2 I2C transactions) with',
    '  remapped identifier codes. Decoding each bus reproduces its source',
    '  expected_transactions.json exactly.',
    r'$end',
    r'$timescale 1 ns $end',
    r'$scope module spi_tb $end',
    for (final v in spi.vars)
      '\$var ${v.kind} ${v.width} ${v.id} ${v.name} \$end',
    r'$upscope $end',
    r'$scope module i2c_tb $end',
    for (final v in i2c.vars)
      '\$var ${v.kind} ${v.width} ${v.id} ${v.name} \$end',
    r'$upscope $end',
    r'$enddefinitions $end',
    r'$dumpvars',
    ...spi.initial,
    ...i2c.initial,
    r'$end',
  ];

  // Interleave both timelines by timestamp.
  final times = <int>{...spi.timeline.keys, ...i2c.timeline.keys}.toList()
    ..sort();
  for (final t in times) {
    out
      ..add('#$t')
      ..addAll(spi.timeline[t] ?? const [])
      ..addAll(i2c.timeline[t] ?? const []);
  }

  Directory('verification/fixtures/protocol/multi').createSync(recursive: true);

  const outVcd = 'verification/fixtures/protocol/multi/spi_i2c_basic.vcd';
  File(outVcd).writeAsStringSync('${out.join('\n')}\n');
  print('Wrote $outVcd');

  // The expected companions are the source files verbatim — one per decoder.
  const outSpiJson =
      'verification/fixtures/protocol/multi/spi_i2c_basic.spi.expected_transactions.json';
  const outI2cJson =
      'verification/fixtures/protocol/multi/spi_i2c_basic.i2c.expected_transactions.json';
  File(outSpiJson).writeAsStringSync(File(spiExpected).readAsStringSync());
  File(outI2cJson).writeAsStringSync(File(i2cExpected).readAsStringSync());
  print('Wrote $outSpiJson');
  print('Wrote $outI2cJson');
}

// ── all-5-decoders-simultaneously fixture ───────────────────────────────────

/// A single-bus source fixture to fold into the combined all-5 VCD.
class _FiveWaySource {
  const _FiveWaySource({
    required this.scope,
    required this.vcdPath,
    required this.expectedPath,
    required this.decoderId,
  });

  final String scope;
  final String vcdPath;
  final String expectedPath;
  final String decoderId;
}

/// Generates the "all 5 Open Core decoders simultaneously" coexistence
/// fixture used by `multi_decoder_coexistence_test.dart`.
///
/// Extends the same merge technique [_generateSpiI2cFixture] uses (parse
/// each single-bus source, remap identifier codes to a disjoint set, emit
/// one sibling scope per source, interleave the timelines by timestamp) to
/// N sources instead of 2 — this is the generalization the file header
/// promises. The first source's ids are kept as-is; every subsequent
/// source's ids are remapped into the next free slice of the full
/// printable-ASCII VCD identifier alphabet so none of the 5 buses collide.
void _generateAllFiveFixture() {
  const sources = [
    _FiveWaySource(
      scope: 'spi_tb',
      vcdPath: 'verification/fixtures/protocol/spi/generated/spi_basic.vcd',
      expectedPath:
          'verification/fixtures/protocol/spi/generated/spi_basic.expected_transactions.json',
      decoderId: 'spi',
    ),
    _FiveWaySource(
      scope: 'i2c_tb',
      vcdPath: 'verification/fixtures/protocol/i2c/generated/i2c_basic.vcd',
      expectedPath:
          'verification/fixtures/protocol/i2c/generated/i2c_basic.expected_transactions.json',
      decoderId: 'i2c',
    ),
    _FiveWaySource(
      scope: 'uart_tb',
      vcdPath: 'verification/fixtures/protocol/uart/generated/uart_basic.vcd',
      expectedPath:
          'verification/fixtures/protocol/uart/generated/uart_basic.expected_transactions.json',
      decoderId: 'uart',
    ),
    _FiveWaySource(
      scope: 'axi4lite_tb',
      vcdPath:
          'verification/fixtures/protocol/axi4lite/generated/axi4lite_basic.vcd',
      expectedPath:
          'verification/fixtures/protocol/axi4lite/generated/axi4lite_basic.expected_transactions.json',
      decoderId: 'axi4_lite',
    ),
    _FiveWaySource(
      scope: 'apb_tb',
      vcdPath: 'verification/fixtures/protocol/apb/generated/apb_basic.vcd',
      expectedPath:
          'verification/fixtures/protocol/apb/generated/apb_basic.expected_transactions.json',
      decoderId: 'apb',
    ),
  ];

  final firstParsed = _parse(sources.first.vcdPath);
  final usedIds = firstParsed.vars.map((v) => v.id).toSet();

  // Every printable-ASCII VCD identifier character ('!' .. '~'), minus
  // whatever the first source (spi) already occupies.
  final candidates = [
    for (var code = 0x21; code <= 0x7e; code++) String.fromCharCode(code),
  ].where((c) => !usedIds.contains(c)).toList();

  final parsedTimelines = <_ParsedVcd>[firstParsed];
  var next = 0;
  for (final source in sources.skip(1)) {
    final raw = _parse(source.vcdPath);
    final idMap = <String, String>{};
    for (final v in raw.vars) {
      while (usedIds.contains(candidates[next]) ||
          idMap.containsValue(candidates[next])) {
        next++;
      }
      idMap[v.id] = candidates[next];
      usedIds.add(candidates[next]);
      next++;
    }
    parsedTimelines.add(_remap(raw, idMap));
  }

  final out = <String>[
    r'$date',
    '  WaveCrux all-5-decoder coexistence fixture',
    r'$end',
    r'$version',
    '  generate_multi_coexistence_fixture.dart',
    r'$end',
    r'$comment',
    '  Combined SPI + I2C + UART + AXI4-Lite + APB bus fixture for the',
    '  "all 5 Open Core decoders simultaneously" coexistence scenario.',
    '  Each scope is copied verbatim from its own single-bus source fixture',
    '  under verification/fixtures/protocol/<decoder>/generated/, with',
    '  identifier codes remapped so none of the 5 buses collide. Decoding',
    '  each bus over the combined file reproduces its source',
    '  expected_transactions.json exactly.',
    r'$end',
    r'$timescale 1 ns $end',
    for (var i = 0; i < sources.length; i++) ...[
      '\$scope module ${sources[i].scope} \$end',
      for (final v in parsedTimelines[i].vars)
        '\$var ${v.kind} ${v.width} ${v.id} ${v.name} \$end',
      r'$upscope $end',
    ],
    r'$enddefinitions $end',
    r'$dumpvars',
    for (final t in parsedTimelines) ...t.initial,
    r'$end',
  ];

  final allTimes = <int>{
    for (final t in parsedTimelines) ...t.timeline.keys,
  }.toList()..sort();
  for (final time in allTimes) {
    out.add('#$time');
    for (final t in parsedTimelines) {
      out.addAll(t.timeline[time] ?? const []);
    }
  }

  const outDir = 'verification/fixtures/protocol/multi';
  Directory(outDir).createSync(recursive: true);

  const outVcd = '$outDir/all5_basic.vcd';
  File(outVcd).writeAsStringSync('${out.join('\n')}\n');
  print('Wrote $outVcd');

  for (final source in sources) {
    final outJson =
        '$outDir/all5_basic.${source.decoderId}.expected_transactions.json';
    File(
      outJson,
    ).writeAsStringSync(File(source.expectedPath).readAsStringSync());
    print('Wrote $outJson');
  }
}
