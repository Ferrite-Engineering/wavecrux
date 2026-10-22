// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/remote/cxp/formal_stream_coordinate_resolver.dart';
import 'package:wavecrux/services/waveform/streaming_vcd_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

/// The `formal.trace_step` receiver (CXP §9.9.3) against **real witness
/// traces**: every VCD SymbiYosys and EQY wrote for the formal corpus, copied
/// byte for byte into `test/fixtures/formal/captured/` (see its
/// `PROVENANCE.md`).
///
/// The expected tick of every step is not computed by the code under test. It
/// is read off each file's text by [_smtSteps]: the trace declares the
/// solver's own step counter, `smt_step`, and the time of each of its values
/// is the time that step sits at. The waveform readers do not expose that
/// variable (it is declared outside every scope), which is exactly why the
/// resolver has to recover the grid from the clock, and why this independent
/// reading is the right oracle for it.
void main() {
  final root = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'formal',
    'captured',
  );

  List<File> corpus() {
    final dir = Directory(root);
    expect(dir.existsSync(), isTrue, reason: '$root is missing');
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.vcd'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'no witness trace under $root');
    return files;
  }

  Future<(StreamingVcdService, List<Variable>)> open(String path) async {
    final source = StreamingVcdService();
    await source.openFile(path);
    await source.streamEndedFuture;
    final variables = source.findVariables(const SignalFilter());
    for (final v in variables) {
      await source.loadSignal(v.signalRef);
    }
    addTearDown(source.close);
    return (source, variables);
  }

  CxpStreamCoordinate step(int k) => CxpStreamCoordinate(
    streamId: CxpStreamCoordinate.formalTraceStepStreamId,
    sequenceIndex: k,
  );

  test('the committed copies are the corpus SimCrux ships', () {
    final files = corpus();
    expect(files, hasLength(27));
    expect(
      corpusDigest(root, files),
      kFormalCorpusDigest,
      reason:
          'these traces must stay byte-identical to SimCrux’s '
          'verification/fixtures/formal/ captures; re-copy them with the '
          'command in PROVENANCE.md',
    );
  });

  test('every witness trace in the corpus resolves every step to the time '
      'its smt_step value sits at', () async {
    for (final file in corpus()) {
      final name = p.relative(file.path, from: root);
      final expected = _smtSteps(file.readAsStringSync());
      expect(expected, isNotEmpty, reason: '$name declares no smt_step');
      final (source, variables) = await open(file.path);

      final grid = FormalTraceStepGrid.derive(
        source: source,
        variables: variables,
      );
      expect(grid.refusal, isNull, reason: name);
      final lattice = grid.lattice!;
      expect(lattice.lastStep, expected.keys.last, reason: name);
      for (final entry in expected.entries) {
        expect(
          lattice.tickForStep(entry.key),
          entry.value,
          reason: '$name step ${entry.key}',
        );
        final resolution = const FormalStreamCoordinateResolver().resolve(
          coordinate: step(entry.key),
          source: source,
          variables: variables,
        );
        expect(resolution.time, entry.value, reason: '$name step ${entry.key}');
        expect(resolution.step, entry.key);
      }
    }
  });

  test('the reader the app opens files with gives the same grid on every '
      'trace', () async {
    // The app opens a waveform with the native wellen reader, not the
    // streaming parser above. A reader that repeats or drops same-value
    // changes, or spells a bit differently, would move the grid.
    for (final file in corpus()) {
      final name = p.relative(file.path, from: root);
      final expected = _smtSteps(file.readAsStringSync());
      final source = WellenProvider();
      await source.openFile(file.path);
      addTearDown(source.close);
      final variables = source.findVariables(const SignalFilter());
      for (final v in variables) {
        await source.loadSignal(v.signalRef);
      }
      final grid = FormalTraceStepGrid.derive(
        source: source,
        variables: variables,
      );
      expect(grid.refusal, isNull, reason: name);
      expect(grid.lattice!.lastStep, expected.keys.last, reason: name);
      for (final entry in expected.entries) {
        expect(
          grid.lattice!.tickForStep(entry.key),
          entry.value,
          reason: '$name step ${entry.key}',
        );
      }
    }
  });

  test('the half-step trap is real: every transition of a clocked trace '
      'gives a lattice twice as fine as its steps', () async {
    // What the grid would be without measuring one clock edge. Step 7 would
    // land at tick 35, between two solver steps.
    final (source, variables) = await open(
      p.join(root, 'sby/handshake_imm/captured/prove_bug/engine_0/trace.vcd'),
    );
    final ticks = <int>[
      for (final v in variables)
        for (final c in source.changesInRange(
          v.signalRef,
          source.startTime,
          source.endTime + 1,
        ))
          c.time,
    ];
    final naive = TraceStepLattice.fromTicks(
      ticks,
      start: source.startTime,
      end: source.endTime,
    );
    expect(naive!.pitch, 5);
    final grid = FormalTraceStepGrid.derive(
      source: source,
      variables: variables,
    );
    expect(grid.lattice!.pitch, 10);
  });

  group('the property meaning, read at the resolved step', () {
    String? valueAt(
      StreamingVcdService source,
      List<Variable> variables,
      String leaf,
      int time,
    ) {
      final v = variables.firstWhere((v) => v.name == leaf);
      return source.valueAt(v.signalRef, time);
    }

    for (final design in ['handshake_imm', 'handshake_slang']) {
      test(
        '$design prove_bug: f_wait is 3 at step 5, and the failure '
        'reported at step 6 lands on the last state-carrying sample',
        () async {
          // From the corpus expectation, written from the RTL: req stays high
          // from step 2 to 5, so f_wait is 3 at step 5 and the f_wait <= 2
          // check fails at step 6.
          final (source, variables) = await open(
            p.join(root, 'sby/$design/captured/prove_bug/engine_0/trace.vcd'),
          );
          final at5 = const FormalStreamCoordinateResolver().resolve(
            coordinate: step(5),
            source: source,
            variables: variables,
          );
          expect(
            int.parse(
              valueAt(source, variables, 'f_wait', at5.time!)!,
              radix: 2,
            ),
            3,
          );
          final at6 = const FormalStreamCoordinateResolver().resolve(
            coordinate: step(6),
            source: source,
            variables: variables,
          );
          expect(at6.landed, isTrue);
          expect(at6.time, 60);
        },
      );
    }

    test('fifo_slang dis: rst is high at step 0, the initial state', () async {
      final (source, variables) = await open(
        p.join(root, 'sby/fifo_slang/captured/dis/engine_0/trace.vcd'),
      );
      final at0 = const FormalStreamCoordinateResolver().resolve(
        coordinate: step(0),
        source: source,
        variables: variables,
      );
      expect(at0.time, 0);
      expect(valueAt(source, variables, 'rst', at0.time!), '1');
    });
  });

  group('refusals: the element is honoured, the step never guessed', () {
    Future<(StreamingVcdService, List<Variable>)> openText(String vcd) async {
      final dir = Directory.systemTemp.createTempSync('formal_grid_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'trace.vcd'))..writeAsStringSync(vcd);
      return await open(file.path);
    }

    test('a trace with no clock whose samples are not evenly spaced', () async {
      final (source, variables) = await openText(_nonUniformNoClock);
      final resolution = const FormalStreamCoordinateResolver().resolve(
        coordinate: step(1),
        source: source,
        variables: variables,
      );
      expect(resolution.landed, isFalse);
      expect(resolution.reason, contains('not evenly spaced'));
    });

    test('a clock whose rising edges are not evenly spaced', () async {
      final (source, variables) = await openText(_irregularClock);
      final resolution = const FormalStreamCoordinateResolver().resolve(
        coordinate: step(1),
        source: source,
        variables: variables,
      );
      expect(resolution.landed, isFalse);
      expect(resolution.reason, contains('no clock edge'));
    });

    test('two clocks that share no edge', () async {
      // Multi-clock traces were not measured, so producers omit the
      // coordinate for them; this is the receiver's own guard. Each clock
      // changes between the other's steps, so neither lattice holds.
      final (source, variables) = await openText(_twoClocks);
      final resolution = const FormalStreamCoordinateResolver().resolve(
        coordinate: step(1),
        source: source,
        variables: variables,
      );
      expect(resolution.landed, isFalse);
      expect(resolution.reason, contains('no clock edge'));
    });

    test('a data signal that changes between two clock edges', () async {
      final (source, variables) = await openText(_dataBetweenEdges);
      final resolution = const FormalStreamCoordinateResolver().resolve(
        coordinate: step(1),
        source: source,
        variables: variables,
      );
      expect(resolution.landed, isFalse);
      expect(resolution.reason, contains('no clock edge'));
    });

    test('a one-bit data signal high for one step does not displace the '
        'clock', () async {
      // Its rising edge alone gives a lattice twice as coarse, with its fall
      // between two of those steps: clock-shaped. The real clock's rises
      // between them rule it out, and the clock's lattice stands.
      final (source, variables) = await openText(_pulseBesideClock);
      final grid = FormalTraceStepGrid.derive(
        source: source,
        variables: variables,
      );
      expect(
        grid.lattice,
        const TraceStepLattice(origin: 0, pitch: 10, lastStep: 4),
      );
    });

    test('a step past the end of the trace', () async {
      final (source, variables) = await open(
        p.join(root, 'sby/fifo_slang/captured/dis/engine_0/trace.vcd'),
      );
      final resolution = const FormalStreamCoordinateResolver().resolve(
        coordinate: step(9),
        source: source,
        variables: variables,
      );
      expect(resolution.landed, isFalse);
      expect(resolution.reason, contains('past the end'));
    });

    test('another stream is not this resolver’s', () async {
      final (source, variables) = await open(
        p.join(root, 'sby/fifo_slang/captured/dis/engine_0/trace.vcd'),
      );
      final resolution = const FormalStreamCoordinateResolver().resolve(
        coordinate: CxpStreamCoordinate(
          streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
          sequenceIndex: 1,
        ),
        source: source,
        variables: variables,
      );
      expect(resolution.landed, isFalse);
      expect(
        FormalStreamCoordinateResolver.implementsStream(
          CxpStreamCoordinate.formalTraceStepStreamId,
        ),
        isTrue,
      );
      expect(
        FormalStreamCoordinateResolver.implementsStream(
          CxpStreamCoordinate.riscvFormalTraceStepStreamId,
        ),
        isFalse,
      );
    });
  });

  group('TraceStepLattice.fromTicks', () {
    test('uniform ticks give a lattice from the start', () {
      final lattice = TraceStepLattice.fromTicks(
        const [10, 20, 30],
        start: 0,
        end: 40,
      );
      expect(
        lattice,
        const TraceStepLattice(origin: 0, pitch: 10, lastStep: 4),
      );
      expect(lattice!.tickForStep(4), 40);
      expect(lattice.tickForStep(5), isNull);
      expect(lattice.contains(30), isTrue);
      expect(lattice.contains(35), isFalse);
    });

    test('irregular ticks give none', () {
      expect(
        TraceStepLattice.fromTicks(const [10, 25], start: 0, end: 40),
        isNull,
      );
    });

    test('a trace with no duration gives none', () {
      expect(TraceStepLattice.fromTicks(const [], start: 0, end: 0), isNull);
    });
  });
}

/// FNV-1a/32 of the formal corpus copies, in sorted relative-path order, each
/// file as its posix path, a newline, then its text with carriage returns
/// dropped. Pinned so a copy that drifts from SimCrux's captures fails here.
const String kFormalCorpusDigest = '0fab99c0';

/// Computes [kFormalCorpusDigest] over [files] under [root].
String corpusDigest(String root, List<File> files) {
  final entries = [
    for (final f in files)
      (p.posix.joinAll(p.split(p.relative(f.path, from: root))), f),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  var hash = 0x811C9DC5;
  void feed(Iterable<int> units) {
    for (final unit in units) {
      if (unit == 0x0D) continue;
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
  }

  for (final (rel, file) in entries) {
    feed(rel.codeUnits);
    feed(const [0x0A]);
    feed(file.readAsBytesSync());
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// The time each `smt_step` value sits at, read from [vcd]'s text: the
/// identifier `yosys-smtbmc` declared for `smt_step`, then every `#<time>`
/// and every binary value change of that identifier.
Map<int, int> _smtSteps(String vcd) {
  final declaration = RegExp(
    r'\$var\s+integer\s+\d+\s+(\S+)\s+smt_step\s+\$end',
  ).firstMatch(vcd);
  if (declaration == null) return const {};
  final id = declaration.group(1)!;
  final steps = <int, int>{};
  var time = 0;
  for (final line in vcd.split('\n')) {
    final text = line.trim();
    if (text.startsWith('#')) {
      time = int.parse(text.substring(1));
    } else if (text.startsWith('b') && text.endsWith(' $id')) {
      final bits = text.substring(1, text.length - id.length - 1);
      steps[int.parse(bits, radix: 2)] = time;
    }
  }
  return steps;
}

const String _nonUniformNoClock = r'''
$timescale 1ns $end
$scope module top $end
$var wire 4 a data $end
$upscope $end
$enddefinitions $end
#0
b0000 a
#10
b0001 a
#25
b0010 a
#40
b0011 a
''';

const String _irregularClock = r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 c clk $end
$var wire 4 a data $end
$upscope $end
$enddefinitions $end
#0
1c
b0000 a
#5
0c
#10
1c
b0001 a
#15
0c
#25
1c
b0010 a
#30
0c
#40
1c
''';

const String _twoClocks = r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 c clk $end
$var wire 1 d clk2 $end
$upscope $end
$enddefinitions $end
#0
1c
0d
#5
0c
#7
1d
#10
1c
#14
0d
#15
0c
#20
1c
#22
1d
#25
0c
#29
0d
#30
1c
#35
0c
#37
1d
#40
1c
''';

const String _dataBetweenEdges = r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 c clk $end
$var wire 4 a data $end
$upscope $end
$enddefinitions $end
#0
1c
b0000 a
#5
0c
#10
1c
b0001 a
#15
0c
#20
1c
#23
b0010 a
#25
0c
#30
1c
#35
0c
#40
1c
''';

const String _pulseBesideClock = r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 c clk $end
$var wire 1 p pulse $end
$upscope $end
$enddefinitions $end
#0
1c
0p
#5
0c
#10
1c
#15
0c
#20
1c
1p
#25
0c
#30
1c
0p
#35
0c
#40
1c
''';
