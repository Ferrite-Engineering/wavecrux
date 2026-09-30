// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates the **annotation review demo** — the fixture the marketing
// screenshots of the annotations feature are captured from.
//
// Deliberately NOT the same thing as `examples/annotations/`. That one is a
// verification fixture: four signals, and notes that are *supposed* to be
// broken (an orphaned row, a signal that does not exist, a drifted witness) so
// the status rules can be exercised. It is the right fixture for testing and
// the wrong one for a picture — a screenshot of it advertises a feature
// failing.
//
// This one is a design under review that a reader can follow:
//
//   * a bus master requests, is granted a cycle later, and bursts writes into
//     a 16-deep FIFO;
//   * `fifo_full` asserts on the cycle the count reaches 16 — but `wr_en` is
//     generated from the PREVIOUS cycle's count, so two more beats land after
//     full and `overflow` pulses. That is the bug the notes are about;
//   * the drain afterwards is correct, and one note says so, because a review
//     that only ever points at faults reads as a bug list rather than as
//     somebody thinking.
//
// Six annotations cover every shape and both anchor kinds: three callouts, one
// arrow, one full-height band and one lane-confined band.
//
// ### Witnesses are computed, not invented
//
// Each note's witness is read out of the same event table the VCD is written
// from, through the app's own `ValueFormatService` in `DisplayFormat.binary` —
// the identical call `AnnotationWitnessService.capture` makes. A hand-typed
// witness that disagreed with the trace would render every balloon in the
// drift amber, and the screenshot would show the feature crying wolf. The
// generator asserts each one is readable before it writes.
//
//   dart run tool/generate_annotations_demo_fixture.dart
//
// Writes examples/annotation-review/{bus-review.vcd,.wavecrux,README.md}.
//
// Timescale 1ns, 100 MHz clock, 600 ns of trace — about 60 cycles, which fills
// a canvas at a legible zoom without the lanes turning into a grey hatch.

import 'dart:io';

import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/services/session/session_service.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

// ── the design under review ────────────────────────────────────────────────

const _scope = 'tb.dut';

/// Every signal, in the order it appears in the lane list. The VCD identifier
/// codes are assigned from this list, so the table is the single source of
/// truth for both the file and the session's rows.
const _signals = <_Sig>[
  _Sig('clk', 1),
  _Sig('rst_n', 1),
  _Sig('req', 1),
  _Sig('gnt', 1),
  _Sig('state', 3),
  _Sig('addr', 16),
  _Sig('wdata', 32),
  _Sig('wr_en', 1),
  _Sig('fifo_wr', 1),
  _Sig('fifo_count', 5),
  _Sig('fifo_full', 1),
  _Sig('overflow', 1),
];

class _Sig {
  const _Sig(this.name, this.width);
  final String name;
  final int width;

  String get path => '$_scope.$name';
}

/// VCD identifier code for [name] — printable ASCII from '!', assigned by
/// position in [_signals].
String _idOf(String name) {
  final i = _signals.indexWhere((s) => s.name == name);
  if (i < 0) throw StateError('no such signal: $name');
  return String.fromCharCode(33 + i);
}

int _widthOf(String name) => _signals.firstWhere((s) => s.name == name).width;

/// A raw VCD value for a bus of [width] bits.
String _bus(int value, int width) => 'b${value.toRadixString(2)}';

// ── FSM encoding, mirrored in the notes ────────────────────────────────────

const _stIdle = 0;
const _stArb = 1;
const _stWrite = 2;
const _stDrain = 3;

const _clkPeriod = 10; // ns — 100 MHz
const _endTime = 480;

/// FIFO depth. `fifo_full` asserts when the count reaches this.
const _fifoDepth = 16;

/// The moment `wr_en` first asserts, and the first beat of the burst.
const _burstStart = 80;

/// The cycle `fifo_count` reaches [_fifoDepth] and `fifo_full` asserts.
const _fullTime = _burstStart + (_fifoDepth - 1) * _clkPeriod; // 230

/// The overflow pulse — two beats after full, which is the bug.
const _overflowTime = _fullTime + 2 * _clkPeriod; // 250

/// Where the drain ends and the count is back at zero.
const _drainEnd = _overflowTime + 2 * _clkPeriod + _fifoDepth * _clkPeriod;

Future<void> main() async {
  final events = _buildEvents();
  final times = events.keys.toList()..sort();

  /// The raw VCD value of [name] at [t] — the last value written at or before
  /// it, exactly as a reader resolves it.
  String? rawAt(String name, int t) {
    final id = _idOf(name);
    String? raw;
    for (final tm in times) {
      if (tm > t) break;
      final v = events[tm]![id];
      if (v != null) raw = v;
    }
    return raw;
  }

  /// The canonical, width-padded bit string a witness stores — through the
  /// app's own formatter, so this cannot drift from what the app computes.
  String witnessBits(String name, int t) {
    final raw = rawAt(name, t);
    if (raw == null) {
      throw StateError(
        'no value for $name at $t ns — a witness computed here would be '
        'null and the note would carry no drift check',
      );
    }
    return const ValueFormatService().format(
      raw,
      _widthOf(name),
      DisplayFormat.binary,
    );
  }

  final annotations = _buildAnnotations(witnessBits);
  final vcd = _buildVcd(events, times);

  const dir = 'examples/annotation-review';
  Directory(dir).createSync(recursive: true);
  File('$dir/bus-review.vcd').writeAsStringSync(vcd);
  await _writeSession(
    path: '$dir/bus-review.wavecrux',
    annotations: annotations,
  );
  File('$dir/README.md').writeAsStringSync(_readme(annotations));

  stdout
    ..writeln(
      'Wrote $dir/bus-review.vcd (${times.length} timesteps, '
      'end=$_endTime ns)',
    )
    ..writeln(
      'Wrote $dir/bus-review.wavecrux (${_signals.length} rows, '
      '${annotations.length} annotations)',
    )
    ..writeln('Wrote $dir/README.md');
  for (final a in annotations) {
    stdout.writeln(
      '  ${a.shape.name.padRight(7)} @ ${a.sortTime.toString().padLeft(3)} ns '
      '${a.rowId ?? '(full height)'}'
      '${a.witness == null ? '' : '  witness=${a.witness!.bits}'}',
    );
  }
}

// ── the trace ──────────────────────────────────────────────────────────────

/// Builds `time -> {vcdId: rawValue}`, writing only the values that change.
Map<int, Map<String, String>> _buildEvents() {
  final ev = <int, Map<String, String>>{};

  void put(int t, String name, String raw) =>
      (ev[t] ??= <String, String>{})[_idOf(name)] = raw;

  // Free-running clock for the whole window.
  for (var t = 0; t <= _endTime; t += _clkPeriod ~/ 2) {
    put(t, 'clk', (t ~/ (_clkPeriod ~/ 2)).isEven ? '1' : '0');
  }

  // Reset, and the idle pose everything starts from.
  put(0, 'rst_n', '0');
  put(0, 'req', '0');
  put(0, 'gnt', '0');
  put(0, 'state', _bus(_stIdle, 3));
  put(0, 'addr', _bus(0, 16));
  put(0, 'wdata', _bus(0, 32));
  put(0, 'wr_en', '0');
  put(0, 'fifo_wr', '0');
  put(0, 'fifo_count', _bus(0, 5));
  put(0, 'fifo_full', '0');
  put(0, 'overflow', '0');
  put(40, 'rst_n', '1');

  // The handshake: req, then gnt one cycle later off the registered arbiter.
  put(60, 'req', '1');
  put(60, 'state', _bus(_stArb, 3));
  put(70, 'gnt', '1');
  put(_burstStart, 'state', _bus(_stWrite, 3));

  // The burst. wr_en and fifo_wr run together; the count climbs one per cycle.
  put(_burstStart, 'wr_en', '1');
  put(_burstStart, 'fifo_wr', '1');
  for (var i = 0; i < _fifoDepth + 2; i++) {
    final t = _burstStart + i * _clkPeriod;
    put(t, 'addr', _bus(0x1000 + i * 4, 16));
    put(t, 'wdata', _bus(0xA5A50000 + i, 32));
    // The count saturates at the depth — the FIFO cannot hold more, which is
    // exactly why the two writes past it are lost rather than stored.
    final count = i + 1 <= _fifoDepth ? i + 1 : _fifoDepth;
    put(t, 'fifo_count', _bus(count, 5));
  }

  // fifo_full asserts on the cycle the count reaches the depth.
  put(_fullTime, 'fifo_full', '1');

  // THE BUG: wr_en is generated from the previous cycle's count, so two more
  // beats are driven after full. The second one raises overflow.
  put(_overflowTime, 'overflow', '1');
  put(_overflowTime + _clkPeriod, 'wr_en', '0');
  put(_overflowTime + _clkPeriod, 'fifo_wr', '0');
  put(_overflowTime + _clkPeriod, 'state', _bus(_stDrain, 3));
  put(_overflowTime + 2 * _clkPeriod, 'overflow', '0');

  // The drain, which is correct: one beat out per cycle, no further writes.
  final drainStart = _overflowTime + 2 * _clkPeriod;
  for (var i = 1; i <= _fifoDepth; i++) {
    put(drainStart + i * _clkPeriod, 'fifo_count', _bus(_fifoDepth - i, 5));
  }
  // full clears on the first beat OUT, not when the writes stop — the FIFO is
  // still full for the whole two cycles the overflow is being raised.
  put(drainStart + _clkPeriod, 'fifo_full', '0');

  // Back to idle.
  put(_drainEnd + _clkPeriod, 'state', _bus(_stIdle, 3));
  put(_drainEnd + _clkPeriod, 'req', '0');
  put(_drainEnd + _clkPeriod, 'gnt', '0');

  return ev;
}

String _buildVcd(Map<int, Map<String, String>> events, List<int> times) {
  final b = StringBuffer()
    ..writeln(r'$date WaveCrux annotation review demo $end')
    ..writeln(r'$version generate_annotations_demo_fixture.dart $end')
    ..writeln(r'$timescale 1ns $end')
    ..writeln(r'$scope module tb $end')
    ..writeln(r'$scope module dut $end');
  for (final s in _signals) {
    final range = s.width > 1 ? ' [${s.width - 1}:0]' : '';
    b.writeln('\$var wire ${s.width} ${_idOf(s.name)} ${s.name}$range \$end');
  }
  b
    ..writeln(r'$upscope $end')
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end');

  final last = <String, String>{};
  var first = true;
  for (final tm in times) {
    final changes = <String>[];
    events[tm]!.forEach((id, val) {
      if (last[id] == val) return;
      last[id] = val;
      changes.add(val.startsWith('b') ? '$val $id' : '$val$id');
    });
    if (changes.isEmpty) continue;
    if (first) {
      b
        ..writeln('#$tm')
        ..writeln(r'$dumpvars');
      changes.forEach(b.writeln);
      b.writeln(r'$end');
      first = false;
    } else {
      b.writeln('#$tm');
      changes.forEach(b.writeln);
    }
  }
  b.writeln('#$_endTime');
  return b.toString();
}

// ── the review ─────────────────────────────────────────────────────────────

/// Who the notes are signed by.
///
/// Open core stamps the collaboration display name from Settings when one is
/// set, and an empty string otherwise. A signed note is what the panel and the
/// review minutes are built around, so the fixture carries one.
const _author = 'D. Whitfield';

/// Fixed creation timestamps. A generator that stamped `DateTime.now()` would
/// rewrite the fixture on every run and turn a re-generate into a diff.
DateTime _at(int minute) => DateTime.utc(2026, 8, 16, 14, minute);

List<Annotation> _buildAnnotations(String Function(String, int) witnessBits) {
  AnnotationWitness w(String name, int t) =>
      AnnotationWitness(bits: witnessBits(name, t));

  return <Annotation>[
    // 1 — the handshake reads correctly, and the note says why. A review that
    // only points at faults reads as a bug list rather than as somebody
    // thinking about the design.
    Annotation(
      id: 'rev-gnt-latency',
      shape: AnnotationShape.callout,
      anchor: PointAnchor(time: 70, rowId: 'tb.dut.gnt'),
      text:
          'gnt is registered off req — one cycle of arbitration latency, '
          'by design.',
      authorName: _author,
      createdAt: _at(2),
      labelDx: 40,
      labelDy: 60,
      witness: w('gnt', 70),
    ),

    // 2 — the full-height band naming the burst. No rowId: it belongs to the
    // whole canvas, not to one lane.
    Annotation(
      id: 'rev-burst-window',
      shape: AnnotationShape.band,
      anchor: const RangeAnchor(
        startTime: _burstStart,
        endTime: _overflowTime + _clkPeriod,
      ),
      text: 'write burst — 18 beats driven',
      authorName: _author,
      createdAt: _at(4),
    ),

    // 3 — the cause.
    Annotation(
      id: 'rev-full-late',
      shape: AnnotationShape.callout,
      anchor: PointAnchor(time: _fullTime, rowId: 'tb.dut.fifo_full'),
      text:
          'fifo_full asserts at count 16, but wr_en came from the previous '
          'cycle.',
      authorName: _author,
      createdAt: _at(6),
      labelDx: -300,
      labelDy: 50,
      witness: w('fifo_full', _fullTime),
    ),

    // 4 — an arrow, no balloon: "this write, right here". Arrows carry no
    // text by construction.
    Annotation(
      id: 'rev-stray-write',
      shape: AnnotationShape.arrow,
      anchor: const PointAnchor(
        time: _fullTime + _clkPeriod,
        rowId: 'tb.dut.fifo_wr',
      ),
      authorName: _author,
      createdAt: _at(7),
      labelDx: -60,
      labelDy: -70,
      witness: w('fifo_wr', _fullTime + _clkPeriod),
    ),

    // 5 — the symptom, and the fix.
    Annotation(
      id: 'rev-overflow',
      shape: AnnotationShape.callout,
      anchor: const PointAnchor(
        time: _overflowTime,
        rowId: 'tb.dut.overflow',
      ),
      text:
          'Two beats land after full. Fix: drive wr_en from almost_full in '
          'u_fifo_ctrl.',
      authorName: _author,
      createdAt: _at(9),
      labelDx: 40,
      labelDy: 30,
      witness: w('overflow', _overflowTime),
    ),

    // 6 — a band confined to one lane, and a note that clears the drain.
    Annotation(
      id: 'rev-drain-ok',
      shape: AnnotationShape.band,
      anchor: const RangeAnchor(
        startTime: _overflowTime + 2 * _clkPeriod,
        endTime: _drainEnd,
        rowId: 'tb.dut.fifo_count',
      ),
      // Short on purpose: a band's label draws from the band's start edge and
      // has the rest of the canvas to run into. The long version ran off the
      // right-hand edge in the first capture.
      text: 'drain is correct',
      authorName: _author,
      createdAt: _at(11),
    ),
  ];
}

// ── the session ────────────────────────────────────────────────────────────

Future<void> _writeSession({
  required String path,
  required List<Annotation> annotations,
}) async {
  final state = SessionState(
    // Relative, so the pair travels together — open the .wavecrux, not the
    // .vcd, and WaveCrux resolves the sibling trace.
    sourceFilePath: 'bus-review.vcd',
    signalGroup: SignalGroup(
      entries: [
        for (final s in _signals)
          SignalEntry.signal(
            // Backend-local and therefore not stable; the loader re-resolves
            // it from signalPath. Written anyway so the file is well-formed.
            signalRef: (_idOf(s.name).codeUnitAt(0) - 33).toString(),
            signalPath: s.path,
            displayName: s.name,
            format: s.width > 4
                ? DisplayFormat.hexadecimal
                : DisplayFormat.binary,
            // Twelve lanes at 28 px leave room below the last lane for the
            // balloons, which is where they hang once the Annotations dock
            // takes the bottom half of the window.
            laneHeight: 28,
          ),
      ],
    ),
    // Both cursors bracket the bug, so the delta readout says "20 ns" — the
    // two cycles the burst overran by.
    cursorState: const CursorState(
      primaryCursorTime: _fullTime,
      secondaryCursorTime: _overflowTime,
    ),
    markerState: const MarkerState(
      markers: {'a': _burstStart, 'b': _overflowTime},
    ),
    // All 480 ns inside ~960 logical px of canvas, which is what a 1680-wide
    // window leaves after both docks. Measured from a real capture, not
    // guessed: at 0.35 the trace overran the canvas and the two right-hand
    // balloons were clipped by the edge. Fit-to-window if your display
    // disagrees — only the framing depends on this.
    ticksPerPixel: 0.5,
    // Otherwise the signal tree renders as a single collapsed `tb` row and the
    // left dock reads as empty.
    expandedScopePaths: const {'tb', 'tb.dut'},
    annotations: annotations,
    annotationsVisible: true,
    // Tri-state: `true` is "explicitly opened", which is what a demo wants —
    // the panel is where the notes are a list rather than scattered balloons.
    annotationsPanelVisible: true,
    // `annotationsPanelVisible` alone only says the Annotations TAB exists —
    // it does not open the dock that holds it, and it does not make that tab
    // the active one. Both were false in the first capture and the panel
    // stayed collapsed to its icon strip. `transactionViewVisible` is the
    // (legacy-named) bottom-dock-is-open flag.
    transactionViewVisible: true,
    bottomDockTab: 'annotations',
  );

  await const SessionService().saveSession(state, path);
}

// ── the guide ──────────────────────────────────────────────────────────────

String _readme(List<Annotation> annotations) =>
    '''
# Annotation review demo

Generated by `tool/generate_annotations_demo_fixture.dart`. **Do not
hand-edit** — re-run the generator instead.

```
File ▸ Open…  →  examples/annotation-review/bus-review.wavecrux
```

The session references `bus-review.vcd` by a **relative** path, so the pair
travels together. Open the `.wavecrux`, not the `.vcd`.

## What this is for

The marketing screenshots of annotations, and any demo where the feature has
to look like a real review rather than a test. It is deliberately separate
from `examples/annotations/`, which is the verification fixture — that one
carries notes that are *supposed* to be broken (orphaned rows, a signal that
does not exist, a drifted witness) so the status rules can be exercised. Those
are the right cases to test and the wrong ones to photograph.

## The design, and the bug

A bus master requests, is granted a cycle later off a registered arbiter, and
bursts writes into a 16-deep FIFO. `fifo_full` asserts on the cycle
`fifo_count` reaches 16 — but `wr_en` is generated from the **previous**
cycle's count, so two more beats are already committed. The second one raises
`overflow` at ${_overflowTime} ns. The drain afterwards is correct.

## The notes

${annotations.map((a) => '- **${a.shape.name}** at ${a.sortTime} ns on '
        '${a.rowId == null ? 'the whole canvas' : '`${a.rowId}`'}'
        '${a.hasText ? ' — "${a.text.split('.').first}…"' : ' — no balloon, '
                  'by construction'}').join('\n')}

Every witness is computed from the same event table the VCD is written from,
through the app's own `ValueFormatService`. If any balloon renders in the
drift amber on a freshly generated pair, the generator and the trace have
diverged and that is a bug, not a demo.

## Capturing the open-core screenshot

1. Open the session. The Annotations panel opens with it — the session carries
   `annotationsPanelVisible: true`, which is the explicit "opened" state of the
   tri-state, not the automatic one.
2. Fit the trace to the window if the saved zoom does not suit your display.
3. Nudge any balloon that collides with another. Dragging a balloon moves the
   **label** and provably not the anchor, so the notes stay attached to the
   ticks they describe no matter how the frame is composed.
4. Capture the whole window, matching the framing of `Hero.png` on the site.

## Capturing the collaboration screenshot

Cursors only exist with a live peer, so this needs two running instances —
two machines on the same LAN is the least fiddly, because each gets its own
identity and display name for free.

1. Copy this whole directory to both machines.
2. Host the session from the machine you will capture on, and open the same
   `bus-review.wavecrux` on the other.
3. Join, and approve the request on the host.
4. Have the joiner write one note — a reply to `rev-overflow` reads well — so
   the frame shows a remote cursor **and** a remote-authored annotation.
5. Capture from the host.

**Do not photograph the full invite string.** It carries the session key and
grants access for as long as the session runs. Crop it out, or end the session
before the image leaves the machine.
''';
