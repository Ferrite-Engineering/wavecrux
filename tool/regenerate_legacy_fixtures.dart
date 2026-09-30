// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regenerates the LXT / LXT2 legacy-format test fixtures.
//
// What it produces, under `test/fixtures/legacy/`:
//
//   simple_counter.vcd   simple_counter.lxt2   simple_counter.lxt
//   multi_scope.vcd      multi_scope.lxt2
//   vector_signals.vcd   vector_signals.lxt2
//   string_values.vcd    string_values.lxt2
//   large_sample.vcd     large_sample.lxt2
//   <each>.expected.json
//
// Each fixture ships three artifacts:
//
//   * the source `.vcd` — the ground-truth capture, authored here by
//     construction so every transition is known exactly;
//   * one or more legacy conversions (`.lxt2` via GTKWave's `vcd2lxt2`,
//     and additionally `.lxt` via `vcd2lxt` for `simple_counter`);
//   * a `.expected.json` — the *wellen-loaded ground truth* of the source
//     VCD: the value `valueAt` / `changesInRange` / `nextTransition` /
//     `prevTransition` should return when the file is loaded through the
//     wellen pipeline. The bridge-equivalence test converts the
//     `.lxt2` to FST with the `lxt2fst` crate, loads it via `WellenProvider`,
//     and asserts the results match this JSON. Because wellen reads VCD
//     natively, the ground truth is generated today without the converter.
//
// The `.expected.json` values are produced here by construction from the
// same transition lists that author the VCD. They are kept in lock-step
// with wellen's actual VCD output: real-valued signals are stored as their
// raw source strings (wellen may normalize scientific notation / trailing
// zeros — verifiers compare reals numerically, not by string), and vector
// values are stored full-width because wellen left-extends VCD vectors to
// the declared bit width.
//
// GTKWave dependency (dev-machine only, NEVER shipped): `vcd2lxt` and
// `vcd2lxt2` come from GTKWave (`brew install gtkwave`, or your distro's
// gtkwave package). They are located via `PATH`. The legacy formats are
// frozen, so this tooling does not track GTKWave versions.
//
// Usage:
//   dart run tool/regenerate_legacy_fixtures.dart
//   dart run tool/regenerate_legacy_fixtures.dart --large
//
// `--large` additionally regenerates a true ~50 MB capture of the same
// shape as `large_sample` into `build/legacy_perf/` (uncommitted) for the
// progress-bar / performance path. The committed `large_sample` is a modest
// ~5 MB capture whose `.lxt2` still carries enough blocks to drive a
// visibly-moving progress bar; the ~50 MB variant is for hands-on perf runs.

// Fixture-regeneration tooling is developer-facing: the stdout summary
// (files written, sizes) is the contract, so `print` is intentional. The
// remaining suppressions are deliberate one-shot-tool idioms — per-line
// StringBuffer writes (clearer than cascades for line-oriented file formats),
// and a 64-bit LCG constant that is intentionally not dart2js-safe (this
// script is Dart-VM-only). Mirrors tool/perf/generate_vcd.dart.
// ignore_for_file: avoid_print, cascade_invocations, avoid_js_rounded_ints
// ignore_for_file: avoid_redundant_argument_values, prefer_foreach
// ignore_for_file: avoid_escaping_inner_quotes, use_raw_strings

import 'dart:convert';
import 'dart:io';

const _outDir = 'test/fixtures/legacy';
const _largePerfDir = 'build/legacy_perf';

// Modest committed large_sample: ~100 bulk signals over ~2500 steps ≈ 5 MB.
const _largeModestSteps = 2500;

// On-demand --large variant: ~10x the modest step count ≈ 50 MB.
const _largeFullSteps = 25000;

void main(List<String> args) {
  final large = args.contains('--large');

  final vcd2lxt2 = _requireTool('vcd2lxt2');
  final vcd2lxt = _requireTool('vcd2lxt');

  Directory(_outDir).createSync(recursive: true);

  final fixtures = <Fixture>[
    _simpleCounter(),
    _multiScope(),
    _vectorSignals(),
    _stringValues(),
    _largeSample(_largeModestSteps),
  ];

  print('Regenerating legacy fixtures into $_outDir');
  print('  vcd2lxt2: $vcd2lxt2');
  print('  vcd2lxt:  $vcd2lxt');
  print('');

  for (final fixture in fixtures) {
    _emitFixture(
      fixture,
      _outDir,
      vcd2lxt2: vcd2lxt2,
      vcd2lxt: fixture.alsoLxt ? vcd2lxt : null,
    );
  }

  if (large) {
    print('');
    print('Regenerating ~50 MB perf capture into $_largePerfDir (--large)');
    Directory(_largePerfDir).createSync(recursive: true);
    _emitFixture(
      _largeSample(_largeFullSteps),
      _largePerfDir,
      vcd2lxt2: vcd2lxt2,
      vcd2lxt: null,
    );
  } else {
    print('');
    print(
      '(skipped ~50 MB perf capture — pass --large to regenerate it '
      'into $_largePerfDir)',
    );
  }

  print('');
  print('Done.');
}

// ── Tool discovery ────────────────────────────────────────────────────────────

/// Locates [name] on `PATH`, returning its absolute path. Exits with a clear,
/// actionable error if the GTKWave tool is missing — fixtures must never be
/// fabricated without the real converter.
String _requireTool(String name) {
  final found = _findOnPath(name);
  if (found != null) return found;

  stderr.writeln('ERROR: required GTKWave tool "$name" not found on PATH.');
  stderr.writeln('');
  stderr.writeln('The legacy fixtures are produced by GTKWave\'s vcd2lxt /');
  stderr.writeln('vcd2lxt2 converters (dev-machine only, never shipped).');
  stderr.writeln('Install GTKWave and ensure $name is on your PATH:');
  stderr.writeln('  macOS:  brew install gtkwave');
  stderr.writeln('  Linux:  apt-get install gtkwave  (or your distro package)');
  stderr.writeln('Then re-run: dart run tool/regenerate_legacy_fixtures.dart');
  exit(1);
}

String? _findOnPath(String name) {
  final pathEnv = Platform.environment['PATH'] ?? '';
  final entries = pathEnv.split(Platform.isWindows ? ';' : ':');
  final exts = Platform.isWindows
      ? const ['.exe', '.bat', '.cmd', '']
      : const [''];
  for (final dir in entries) {
    if (dir.isEmpty) continue;
    for (final ext in exts) {
      final candidate = '$dir${Platform.pathSeparator}$name$ext';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}

// ── Fixture model ─────────────────────────────────────────────────────────────

enum SigKind { scalar, vector, real, string }

class Change {
  const Change(this.time, this.value);
  final int time;
  final String value;
}

class Sig {
  Sig({
    required this.id,
    required this.name,
    required this.scopePath,
    required this.kind,
    required this.vcdType,
    required this.changes,
    this.width,
    this.inExpected = true,
  });

  /// VCD identifier code (printable ASCII, unique within a fixture).
  final String id;
  final String name;

  /// Dotted path of the *containing* scope, e.g. `top.cpu.alu`.
  final String scopePath;
  final SigKind kind;

  /// The VCD `$var` type token (`wire`, `reg`, `real`, `string`, …). Also the
  /// `varType` reported in `.expected.json` — it is wellen's mapping of this
  /// token.
  final String vcdType;

  /// Bit width for scalar/vector signals; `null` for real and string.
  final int? width;

  /// Time-ordered value changes (must include a change at time 0).
  final List<Change> changes;

  /// Whether this signal participates in the `.expected.json` cross-check.
  /// Bulk filler signals in the large_sample fixture set this to `false`.
  final bool inExpected;

  String get fullPath => '$scopePath.$name';

  /// Declared bit width for `.expected.json`: null for real/string.
  int? get expectedBitWidth =>
      (kind == SigKind.real || kind == SigKind.string) ? null : width;
}

class Fixture {
  Fixture({
    required this.name,
    required this.sigs,
    this.alsoLxt = false,
    this.comment,
  });

  final String name;
  final List<Sig> sigs;

  /// Whether to also emit a `.lxt` (classic) conversion alongside `.lxt2`.
  final bool alsoLxt;

  /// Optional top-level note copied into `.expected.json`.
  final String? comment;

  int get endTime =>
      sigs.expand((s) => s.changes).map((c) => c.time).fold(0, _max);

  List<Sig> get expectedSigs =>
      sigs.where((s) => s.inExpected).toList(growable: false);
}

int _max(int a, int b) => a > b ? a : b;

// ── Fixture definitions ─────────────────────────────────────────────────────────

/// 8-bit counter with a toggling clock, ~50 transitions. The only fixture that
/// also gets a `.lxt` (classic) conversion.
Fixture _simpleCounter() {
  const steps = 50;
  final clk = <Change>[];
  final count = <Change>[];
  for (var i = 0; i < steps; i++) {
    final t = i * 10;
    clk.add(Change(t, (i & 1).toString()));
    count.add(Change(t, _bits(8, i)));
  }
  return Fixture(
    name: 'simple_counter',
    alsoLxt: true,
    comment:
        '8-bit counter with a toggling clock (~50 transitions). '
        'Smallest known-answer legacy fixture; also converted to classic LXT.',
    sigs: [
      Sig(
        id: '!',
        name: 'clk',
        scopePath: 'top',
        kind: SigKind.scalar,
        vcdType: 'wire',
        width: 1,
        changes: clk,
      ),
      Sig(
        id: '"',
        name: 'count',
        scopePath: 'top',
        kind: SigKind.vector,
        vcdType: 'reg',
        width: 8,
        changes: count,
      ),
    ],
  );
}

/// Hierarchical design (top.cpu.alu, top.cpu.regfile) to exercise scope-walk.
Fixture _multiScope() {
  return Fixture(
    name: 'multi_scope',
    comment:
        'Nested hierarchy (top.cpu.alu, top.cpu.regfile) exercising '
        'scope-walk and full-path resolution.',
    sigs: [
      Sig(
        id: '!',
        name: 'clk',
        scopePath: 'top',
        kind: SigKind.scalar,
        vcdType: 'wire',
        width: 1,
        changes: [
          for (var i = 0; i <= 10; i++) Change(i * 10, (i & 1).toString()),
        ],
      ),
      Sig(
        id: '"',
        name: 'reset',
        scopePath: 'top.cpu',
        kind: SigKind.scalar,
        vcdType: 'reg',
        width: 1,
        changes: const [Change(0, '1'), Change(30, '0')],
      ),
      Sig(
        id: '#',
        name: 'result',
        scopePath: 'top.cpu.alu',
        kind: SigKind.vector,
        vcdType: 'reg',
        width: 16,
        changes: [
          Change(0, _bits(16, 0x0000)),
          Change(30, _bits(16, 0x00FF)),
          Change(50, _bits(16, 0x1234)),
          Change(90, _bits(16, 0xFFFF)),
        ],
      ),
      Sig(
        id: r'$',
        name: 'zero',
        scopePath: 'top.cpu.alu',
        kind: SigKind.scalar,
        vcdType: 'wire',
        width: 1,
        changes: const [Change(0, '1'), Change(30, '0'), Change(90, '1')],
      ),
      Sig(
        id: '%',
        name: 'we',
        scopePath: 'top.cpu.regfile',
        kind: SigKind.scalar,
        vcdType: 'wire',
        width: 1,
        changes: const [Change(0, '0'), Change(40, '1'), Change(70, '0')],
      ),
      Sig(
        id: '&',
        name: 'r0',
        scopePath: 'top.cpu.regfile',
        kind: SigKind.vector,
        vcdType: 'reg',
        width: 32,
        changes: [
          Change(0, _bits(32, 0x00000000)),
          Change(40, _bits(32, 0xDEADBEEF)),
          Change(70, _bits(32, 0x00000001)),
        ],
      ),
      Sig(
        id: "'",
        name: 'r1',
        scopePath: 'top.cpu.regfile',
        kind: SigKind.vector,
        vcdType: 'reg',
        width: 32,
        changes: [
          Change(0, _bits(32, 0x00000000)),
          Change(40, _bits(32, 0xCAFEBABE)),
        ],
      ),
    ],
  );
}

/// 32-bit and 64-bit vectors with x/z values, plus real-valued signals.
Fixture _vectorSignals() {
  return Fixture(
    name: 'vector_signals',
    comment:
        '32-/64-bit vectors with x/z states and real-valued signals. '
        'Real values are stored as their raw source strings; wellen may '
        'normalize them, so verifiers compare reals numerically.',
    sigs: [
      Sig(
        id: '!',
        name: 'bus32',
        scopePath: 'top',
        kind: SigKind.vector,
        vcdType: 'wire',
        width: 32,
        changes: [
          Change(0, _bits(32, 0x00000000)),
          Change(10, _bits(32, 0x0000FFFF)),
          Change(20, _bits(32, 0xFFFFFFFF)),
          Change(30, _bits(32, 0xDEADBEEF)),
          // High nibble unknown, rest zero.
          Change(40, 'xxxx${'0' * 28}'),
          // Low nibble high-impedance, rest zero.
          Change(50, '${'0' * 28}zzzz'),
          Change(60, _bits(32, 0x00000001)),
        ],
      ),
      Sig(
        id: '"',
        name: 'bus64',
        scopePath: 'top',
        kind: SigKind.vector,
        vcdType: 'wire',
        width: 64,
        changes: [
          Change(0, '0' * 64),
          Change(20, '${'0' * 32}${'1' * 32}'),
          Change(40, '1' * 64),
          // High byte unknown.
          Change(60, '${'x' * 8}${'0' * 56}'),
        ],
      ),
      Sig(
        id: '#',
        name: 'xz32',
        scopePath: 'top',
        kind: SigKind.vector,
        vcdType: 'wire',
        width: 32,
        changes: [
          Change(0, 'x' * 32),
          Change(10, 'z' * 32),
          Change(20, 'x0' * 16),
          Change(30, 'z1' * 16),
        ],
      ),
      Sig(
        id: r'$',
        name: 'voltage',
        scopePath: 'top',
        kind: SigKind.real,
        vcdType: 'real',
        changes: const [
          Change(0, '1.8'),
          Change(20, '3.3'),
          Change(40, '-1.2'),
          Change(60, '0.0'),
        ],
      ),
      Sig(
        id: '%',
        name: 'current',
        scopePath: 'top',
        kind: SigKind.real,
        vcdType: 'real',
        changes: const [
          Change(0, '0.005'),
          Change(30, '-0.005'),
          Change(50, '1e-9'),
        ],
      ),
    ],
  );
}

/// VCD `$var string` signals — covers the LXT2 string-encoding quirk.
Fixture _stringValues() {
  return Fixture(
    name: 'string_values',
    comment:
        'VCD \$var string signals (s-prefixed value changes). LXT2 '
        'encodes string values distinctly from vectors; this fixture pins '
        'that path. String values avoid embedded whitespace (the VCD value '
        'token is whitespace-delimited).',
    sigs: [
      Sig(
        id: '!',
        name: 'state',
        scopePath: 'top',
        kind: SigKind.string,
        vcdType: 'string',
        changes: const [
          Change(0, 'IDLE'),
          Change(10, 'FETCH'),
          Change(20, 'DECODE'),
          Change(30, 'EXECUTE'),
          Change(40, 'WRITEBACK'),
          Change(50, 'IDLE'),
        ],
      ),
      Sig(
        id: '"',
        name: 'msg',
        scopePath: 'top',
        kind: SigKind.string,
        vcdType: 'string',
        changes: const [
          Change(0, 'boot'),
          Change(20, 'ready'),
          Change(40, 'halt'),
        ],
      ),
      Sig(
        id: '#',
        name: 'code',
        scopePath: 'top',
        kind: SigKind.string,
        vcdType: 'string',
        changes: const [
          Change(0, 'OK'),
          Change(30, 'error_code=0x2A'),
          Change(60, 'v1.2-rc'),
        ],
      ),
    ],
  );
}

/// Large capture for the progress-bar / performance path. A handful of
/// controlled "probe" signals (cross-checked in `.expected.json`) plus a wide
/// bulk of filler signals that drive file size. The probe signals are fixed
/// regardless of [steps]; only the bulk scales.
Fixture _largeSample(int steps) {
  const bulkCount = 100;
  const bulkWidth = 16;

  // Probe signals — fixed shape, fully cross-checked.
  final clk = <Change>[
    for (var i = 0; i < 200; i++) Change(i * 10, (i & 1).toString()),
  ];
  final counter = <Change>[
    for (var i = 0; i < 200; i++) Change(i * 10, _bits(32, i)),
  ];
  final tempr = <Change>[
    for (var i = 0; i < 10; i++)
      Change(i * 200, (20.0 + i * 1.5).toStringAsFixed(1)),
  ];
  final label = <Change>[
    for (var i = 0; i < 4; i++) Change(i * 500, 'PHASE$i'),
  ];

  final sigs = <Sig>[
    Sig(
      id: '!',
      name: 'clk',
      scopePath: 'top.bench',
      kind: SigKind.scalar,
      vcdType: 'wire',
      width: 1,
      changes: clk,
    ),
    Sig(
      id: '"',
      name: 'counter',
      scopePath: 'top.bench',
      kind: SigKind.vector,
      vcdType: 'reg',
      width: 32,
      changes: counter,
    ),
    Sig(
      id: '#',
      name: 'tempr',
      scopePath: 'top.bench',
      kind: SigKind.real,
      vcdType: 'real',
      changes: tempr,
    ),
    Sig(
      id: r'$',
      name: 'label',
      scopePath: 'top.bench',
      kind: SigKind.string,
      vcdType: 'string',
      changes: label,
    ),
  ];

  // Bulk filler signals — excluded from the cross-check, present only to
  // grow the file so the converter's progress callback has real work.
  // Deterministic LCG so the capture is reproducible.
  var lcg = 0x2545F4914F6CDD1D & 0x7FFFFFFFFFFFFFFF;
  int nextRand() {
    lcg =
        (lcg * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF;
    return (lcg >> 16) & 0xFFFF;
  }

  for (var s = 0; s < bulkCount; s++) {
    final changes = <Change>[];
    for (var i = 0; i < steps; i++) {
      changes.add(Change(i * 10, _bits(bulkWidth, nextRand())));
    }
    sigs.add(
      Sig(
        id: _bulkId(s),
        name: 'sig${s.toString().padLeft(3, '0')}',
        scopePath: 'top.bench.bulk',
        kind: SigKind.vector,
        vcdType: 'reg',
        width: bulkWidth,
        changes: changes,
        inExpected: false,
      ),
    );
  }

  return Fixture(
    name: 'large_sample',
    comment:
        'Large capture for the progress-bar / performance path. Only the '
        'four top.bench probe signals are cross-checked; the top.bench.bulk '
        'signals exist solely to grow the file. Regenerate the ~50 MB variant '
        'with --large.',
    sigs: sigs,
  );
}

/// Maps a bulk signal index to a multi-character VCD identifier code that
/// never collides with the single-character probe ids (`!"#$`).
String _bulkId(int index) {
  // Two printable-ASCII chars starting past the probe ids.
  const base = 0x30; // '0'
  final hi = base + (index ~/ 64);
  final lo = base + (index % 64);
  return '${String.fromCharCode(hi)}${String.fromCharCode(lo)}';
}

// ── Binary formatting ─────────────────────────────────────────────────────────

/// Full-width little-endian-free binary string of [value] in [width] bits.
/// wellen left-extends VCD vectors to the declared width, so emitting and
/// expecting full-width strings keeps the two in lock-step.
String _bits(int width, int value) {
  final masked = value & ((1 << width) - 1);
  return masked.toRadixString(2).padLeft(width, '0');
}

// ── Emission ──────────────────────────────────────────────────────────────────

void _emitFixture(
  Fixture fixture,
  String dir, {
  required String vcd2lxt2,
  String? vcd2lxt,
}) {
  final vcdPath = '$dir/${fixture.name}.vcd';
  final lxt2Path = '$dir/${fixture.name}.lxt2';
  final expectedPath = '$dir/${fixture.name}.expected.json';

  File(vcdPath).writeAsStringSync(_buildVcd(fixture));
  File(expectedPath).writeAsStringSync(_buildExpectedJson(fixture));

  _runConverter(vcd2lxt2, vcdPath, lxt2Path);

  String? lxtPath;
  if (vcd2lxt != null) {
    lxtPath = '$dir/${fixture.name}.lxt';
    _runConverter(vcd2lxt, vcdPath, lxtPath);
  }

  print(
    '  ${fixture.name}: '
    '${_kb(vcdPath)} VCD → ${_kb(lxt2Path)} LXT2'
    '${lxtPath == null ? '' : ', ${_kb(lxtPath)} LXT'}'
    ' (+ expected.json)',
  );
}

void _runConverter(String tool, String inPath, String outPath) {
  final result = Process.runSync(tool, [inPath, outPath]);
  if (result.exitCode != 0 || !File(outPath).existsSync()) {
    stderr.writeln('ERROR: $tool failed for $inPath (exit ${result.exitCode})');
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    exit(1);
  }
}

String _kb(String path) {
  final bytes = File(path).lengthSync();
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

// ── VCD construction ──────────────────────────────────────────────────────────

String _buildVcd(Fixture fixture) {
  final buf = StringBuffer()..writeln(r'$timescale 1 ns $end');
  _writeScopeTree(buf, fixture.sigs);
  buf.writeln(r'$enddefinitions $end');

  // Initial values (time 0) inside $dumpvars.
  buf.writeln(r'$dumpvars');
  for (final sig in fixture.sigs) {
    final first = sig.changes.first;
    assert(first.time == 0, '${sig.fullPath} must define a value at time 0');
    buf.writeln(_valueToken(sig, first.value));
  }
  buf.writeln(r'$end');

  // Remaining changes grouped by ascending time.
  final byTime = <int, List<String>>{};
  for (final sig in fixture.sigs) {
    for (final c in sig.changes) {
      if (c.time == 0) continue;
      (byTime[c.time] ??= []).add(_valueToken(sig, c.value));
    }
  }
  final times = byTime.keys.toList()..sort();
  for (final t in times) {
    buf.writeln('#$t');
    for (final token in byTime[t]!) {
      buf.writeln(token);
    }
  }
  // Trailing time marker so the end-of-trace time is unambiguous.
  buf.writeln('#${fixture.endTime}');
  return buf.toString();
}

String _valueToken(Sig sig, String value) {
  switch (sig.kind) {
    case SigKind.scalar:
      return '$value${sig.id}';
    case SigKind.vector:
      return 'b$value ${sig.id}';
    case SigKind.real:
      return 'r$value ${sig.id}';
    case SigKind.string:
      return 's$value ${sig.id}';
  }
}

/// Builds the nested `$scope`/`$var`/`$upscope` tree from the signals' scope
/// paths, emitting variables in declaration order within each scope.
void _writeScopeTree(StringBuffer buf, List<Sig> sigs) {
  final root = _ScopeNode('');
  for (final sig in sigs) {
    final segments = sig.scopePath.split('.');
    var node = root;
    for (final seg in segments) {
      node = node.children.putIfAbsent(seg, () => _ScopeNode(seg));
    }
    node.vars.add(sig);
  }
  for (final child in root.children.values) {
    _writeScopeNode(buf, child);
  }
}

void _writeScopeNode(StringBuffer buf, _ScopeNode node) {
  buf.writeln(
    r'$scope module '
    '${node.name} '
    r'$end',
  );
  for (final sig in node.vars) {
    final width = sig.width ?? 1;
    buf.writeln(
      r'$var '
      '${sig.vcdType} $width ${sig.id} ${sig.name} '
      r'$end',
    );
  }
  for (final child in node.children.values) {
    _writeScopeNode(buf, child);
  }
  buf.writeln(r'$upscope $end');
}

class _ScopeNode {
  _ScopeNode(this.name);
  final String name;
  final Map<String, _ScopeNode> children = {};
  final List<Sig> vars = [];
}

// ── expected.json construction ─────────────────────────────────────────────────

String _buildExpectedJson(Fixture fixture) {
  final endTime = fixture.endTime;
  final map = <String, Object?>{
    if (fixture.comment != null) '_comment': fixture.comment,
    'metadata': {
      'timescale': {'factor': 1, 'unit': 'nanoSeconds'},
      'startTime': 0,
      'endTime': endTime,
      'date': null,
      'version': null,
    },
    'hierarchy': {'rootScopes': _expectedHierarchy(fixture.expectedSigs)},
    'signals': {
      for (final sig in fixture.expectedSigs)
        sig.fullPath: _expectedSignal(sig, endTime),
    },
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

List<Map<String, Object?>> _expectedHierarchy(List<Sig> sigs) {
  final root = _ScopeNode('');
  for (final sig in sigs) {
    final segments = sig.scopePath.split('.');
    var node = root;
    for (final seg in segments) {
      node = node.children.putIfAbsent(seg, () => _ScopeNode(seg));
    }
    node.vars.add(sig);
  }
  return [
    for (final child in root.children.values) _expectedScope(child, child.name),
  ];
}

Map<String, Object?> _expectedScope(_ScopeNode node, String path) {
  return {
    'name': node.name,
    'type': 'module',
    'path': path,
    'childScopes': [
      for (final child in node.children.values)
        _expectedScope(child, '$path.${child.name}'),
    ],
    'variables': [
      for (final sig in node.vars)
        {
          'name': sig.name,
          'fullPath': sig.fullPath,
          'varType': sig.vcdType,
          'bitWidth': sig.expectedBitWidth,
          'direction': 'unknown',
        },
    ],
  };
}

Map<String, Object?> _expectedSignal(Sig sig, int endTime) {
  final changes = sig.changes;
  final times = <int>{
    -1,
    0,
    for (final c in changes) ...[c.time - 1, c.time, c.time + 1],
    endTime,
    endTime + 50,
  }.where((t) => t >= -1).toList()..sort();

  // valueAt probes across the full timeline.
  final valueAt = [
    for (final t in times) {'time': t, 'expected': _valueAt(changes, t)},
  ];

  // changesInRange probes: each consecutive window, the full range, and a few
  // boundary/out-of-range cases.
  final ranges = <List<int>>[
    [0, 0],
    for (var i = 0; i < changes.length - 1; i++)
      [changes[i].time, changes[i + 1].time],
    [0, endTime + 1],
    [endTime + 1, endTime + 100],
  ];
  final changesInRange = [
    for (final r in ranges)
      {
        'start': r[0],
        'end': r[1],
        'expected': [
          for (final c in changes)
            if (c.time >= r[0] && c.time < r[1])
              {'time': c.time, 'value': c.value},
        ],
      },
  ];

  final afterTimes = <int>{
    -1,
    for (final c in changes) c.time,
    endTime,
    endTime + 50,
  }.toList()..sort();
  final nextTransition = [
    for (final t in afterTimes)
      {'afterTime': t, 'expected': _nextTransition(changes, t)},
  ];

  final beforeTimes = <int>{
    0,
    for (final c in changes) ...[c.time, c.time + 1],
    endTime + 50,
  }.toList()..sort();
  final prevTransition = [
    for (final t in beforeTimes)
      {'beforeTime': t, 'expected': _prevTransition(changes, t)},
  ];

  return {
    'allChanges': [
      for (final c in changes) {'time': c.time, 'value': c.value},
    ],
    'valueAt': valueAt,
    'changesInRange': changesInRange,
    'nextTransition': nextTransition,
    'prevTransition': prevTransition,
  };
}

// Query semantics mirror WaveformDataSource: start-inclusive / end-exclusive
// ranges, strictly-greater next, strictly-less prev, last-change-at-or-before
// for valueAt.

String? _valueAt(List<Change> changes, int t) {
  String? value;
  for (final c in changes) {
    if (c.time <= t) {
      value = c.value;
    } else {
      break;
    }
  }
  return value;
}

Map<String, Object?>? _nextTransition(List<Change> changes, int afterTime) {
  for (final c in changes) {
    if (c.time > afterTime) return {'time': c.time, 'value': c.value};
  }
  return null;
}

Map<String, Object?>? _prevTransition(List<Change> changes, int beforeTime) {
  Change? found;
  for (final c in changes) {
    if (c.time < beforeTime) {
      found = c;
    } else {
      break;
    }
  }
  return found == null ? null : {'time': found.time, 'value': found.value};
}
