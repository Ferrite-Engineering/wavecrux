// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Annotations in SVG export.
//
// PNG gets the overlay for free: it is a `RepaintBoundary` capture and the
// annotations are widgets inside it. SVG is hand-emitted, so every shape has to
// be written out — and every rule the canvas applies has to be re-stated here
// or the exported vector will disagree with the screen about what is drawn.
//
// The escaping tests are the ones that matter most. An annotation body is
// arbitrary prose about a design: `a < b`, `req && ack`, `the "ack" that never
// arrives`. Emit any of that raw and the document silently fails to parse in a
// browser, which is exactly where a shared SVG gets opened.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _service = ImageExportService();
const _fixturePath = 'test/fixtures/vcd/scalar_basics.vcd';

Variable _variable(String name, String ref, {int bitWidth = 1}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top',
  bitWidth: bitWidth,
);

Annotation _callout({
  String id = 'a1',
  String text = 'the ack never arrives',
  int time = 10,
  String rowId = 'top.clk',
  bool collapsed = false,
  double labelDy = 40,
}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: rowId),
  authorName: 'Dana',
  createdAt: DateTime.utc(2026, 8, 13),
  text: text,
  labelDx: 30,
  labelDy: labelDy,
  collapsed: collapsed,
);

void main() {
  if (!requireWellenFfiLibrary('SVG annotations')) return;

  late WellenProvider source;
  late TimeMapper mapper;
  late SignalGroup lanes;
  late Map<String, Variable> signalMap;
  late String clkRef;

  setUp(() async {
    source = WellenProvider();
    await source.openFile(_fixturePath);
    final vars = source.findVariables(const SignalFilter());
    for (final v in vars) {
      await source.loadSignal(v.signalRef);
    }
    final clk = vars.firstWhere((v) => v.name == 'clk');
    clkRef = clk.signalRef;
    lanes = SignalGroup(
      entries: [
        SignalEntry.signal(
          signalRef: clkRef,
          signalPath: clk.fullPath,
          displayName: 'clk',
        ),
      ],
    );
    signalMap = {clkRef: _variable('clk', clkRef)};
    mapper = TimeMapper.fitAll(
      startTime: source.startTime,
      endTime: source.endTime,
      viewportWidth: 800,
    );
  });

  tearDown(() => source.close());

  String render({
    required List<Annotation> annotations,
    Map<String, AnnotationStatus>? statuses,
  }) => _service.generateSvg(
    source: source,
    signalGroup: lanes,
    signalMap: signalMap,
    timeMapper: mapper,
    annotations: annotations,
    annotationStatuses:
        statuses ??
        {for (final a in annotations) a.id: AnnotationStatus.resolved},
  );

  String rowId() => lanes.entries.single.signalPath!;

  group('shapes', () {
    test('a callout emits a balloon, a leader and its text', () {
      final svg = render(annotations: [_callout(rowId: rowId())]);

      expect(svg, contains('<rect'));
      expect(svg, contains('<line'));
      expect(svg, contains('the ack never'));
    });

    test('an arrow emits a head and no balloon text', () {
      final svg = render(
        annotations: [
          Annotation(
            id: 'arr',
            shape: AnnotationShape.arrow,
            anchor: PointAnchor(time: 10, rowId: rowId()),
            authorName: '',
            createdAt: DateTime.utc(2026, 8, 13),
            labelDx: 40,
            labelDy: 30,
          ),
        ],
      );

      // The arrowhead is the only <path> this emitter produces.
      expect(svg, contains('<path d="M '));
      expect(svg, contains('<line'));
    });

    test('a band emits a translucent rect and its label', () {
      final svg = render(
        annotations: [
          Annotation(
            id: 'band',
            shape: AnnotationShape.band,
            anchor: const RangeAnchor(startTime: 5, endTime: 20),
            authorName: '',
            createdAt: DateTime.utc(2026, 8, 13),
            text: 'burst window',
          ),
        ],
      );

      expect(svg, contains('fill-opacity="0.14"'));
      expect(svg, contains('burst window'));
    });

    test('a collapsed callout emits a numbered dot rather than a balloon', () {
      final svg = render(
        annotations: [_callout(rowId: rowId(), collapsed: true)],
      );

      expect(svg, contains('<circle'));
      expect(
        svg,
        isNot(contains('the ack never')),
        reason: 'a collapsed note shows its number, not its body',
      );
    });
  });

  group('status styling', () {
    test('a drifted note gets a dashed leader', () {
      final svg = render(
        annotations: [_callout(rowId: rowId())],
        statuses: {'a1': AnnotationStatus.drifted},
      );

      expect(svg, contains('stroke-dasharray'));
      // The amber the canvas uses, so screen and document agree.
      expect(svg, contains('rgb(232,163,61)'));
    });

    test('a resolved note has no dashes', () {
      final svg = render(annotations: [_callout(rowId: rowId())]);
      expect(svg, isNot(contains('stroke-dasharray')));
    });

    test('orphaned and unresolved notes draw nothing at all', () {
      // Same rule as the canvas. A static document has no panel to route them
      // to, so drawing them somewhere arbitrary would be noise a reader cannot
      // resolve.
      final svg = render(
        annotations: [
          _callout(id: 'o', text: 'orphaned note', rowId: rowId()),
          _callout(id: 'u', text: 'unresolved note', rowId: rowId()),
        ],
        statuses: {
          'o': AnnotationStatus.orphaned,
          'u': AnnotationStatus.unresolved,
        },
      );

      expect(svg, isNot(contains('orphaned note')));
      expect(svg, isNot(contains('unresolved note')));
    });

    test('a note on a row absent from this export is skipped', () {
      final svg = render(
        annotations: [_callout(text: 'not here', rowId: 'top.absent')],
      );
      expect(svg, isNot(contains('not here')));
    });
  });

  group('XML escaping', () {
    test('the five metacharacters are escaped in a body', () {
      final svg = render(
        annotations: [
          _callout(text: 'a < b && c > d "quoted" it\'s', rowId: rowId()),
        ],
      );

      expect(svg, contains('&lt;'));
      expect(svg, contains('&amp;'));
      expect(svg, contains('&gt;'));
      expect(svg, contains('&quot;'));
      expect(svg, contains('&apos;'));
      // Nothing raw survived.
      expect(svg, isNot(contains('a < b')));
    });

    test('a band label is escaped too', () {
      final svg = render(
        annotations: [
          Annotation(
            id: 'band',
            shape: AnnotationShape.band,
            anchor: const RangeAnchor(startTime: 5, endTime: 20),
            authorName: '',
            createdAt: DateTime.utc(2026, 8, 13),
            text: 'req && ack',
          ),
        ],
      );

      expect(svg, contains('req &amp;&amp; ack'));
    });

    test('the document stays well-formed with hostile text', () {
      // The failure this guards is total and silent: one raw `<` and a browser
      // renders nothing at all.
      final svg = render(
        annotations: [
          _callout(text: '</svg><script>alert(1)</script>', rowId: rowId()),
        ],
      );

      expect(svg, isNot(contains('<script>')));
      expect(svg, contains('&lt;/svg&gt;'));
      // Exactly one closing tag — the emitter's own.
      expect('</svg>'.allMatches(svg).length, 1);
    });

    test('a long body is wrapped rather than truncated to a label width', () {
      // Signal labels are cut to ten characters to fit the gutter. An
      // annotation body is prose the user wrote and expects to read back, so
      // the two must not share a sanitizer.
      const body =
          'the request is asserted here but the acknowledgement never '
          'comes back which is the bug';
      final svg = render(
        annotations: [_callout(text: body, rowId: rowId())],
      );

      expect(svg, contains('the request'));
      expect(svg, contains('acknowledgement'));
    });
  });

  group('the include switch', () {
    test('no annotations means no annotation output', () {
      final withNotes = render(annotations: [_callout(rowId: rowId())]);
      final without = render(annotations: const []);

      expect(withNotes, contains('the ack never'));
      expect(without, isNot(contains('the ack never')));
      // The waveform itself is unaffected either way.
      expect(without, contains('<svg'));
      expect(without, contains('clk'));
    });
  });

  group('the document contains what it draws', () {
    /// The lowest y any element reaches, however it expresses its geometry.
    double lowestDrawnY(String svg) {
      var lowest = 0.0;
      for (final m in RegExp(
        r'<rect[^>]*\by="([\d.]+)"[^>]*\bheight="([\d.]+)"',
      ).allMatches(svg)) {
        lowest = math.max(
          lowest,
          double.parse(m.group(1)!) + double.parse(m.group(2)!),
        );
      }
      for (final m in RegExp(r'\by2="([\d.]+)"').allMatches(svg)) {
        lowest = math.max(lowest, double.parse(m.group(1)!));
      }
      for (final m in RegExp(r'<text[^>]*\by="([\d.]+)"').allMatches(svg)) {
        lowest = math.max(lowest, double.parse(m.group(1)!));
      }
      return lowest;
    }

    double declaredHeight(String svg) => double.parse(
      RegExp(r'<svg[^>]*\bheight="([\d.]+)"').firstMatch(svg)!.group(1)!,
    );

    test('a balloon below the last lane is not clipped away', () {
      // The reported "incomplete" export. The height was computed from the lane
      // count alone, and the balloon's TOP was clamped to it — which says
      // nothing about where its BOTTOM lands. A 62 px balloon pinned at
      // `height - 2` drew 60 px past the viewBox and was silently cut off; the
      // note the export existed to show was the one missing.
      // svgHeight mirrors what the real caller computes — ruler + lanes, a
      // couple of hundred pixels — not the generous 600 default. With 600 the
      // balloon fits by luck and the bug hides.
      final svg = _service.generateSvg(
        source: source,
        signalGroup: lanes,
        signalMap: signalMap,
        timeMapper: mapper,
        svgHeight: 200,
        annotations: [
          _callout(rowId: rowId(), text: 'a' * 90, labelDy: 150),
        ],
        annotationStatuses: const {'a1': AnnotationStatus.resolved},
      );

      expect(
        lowestDrawnY(svg),
        lessThanOrEqualTo(declaredHeight(svg)),
        reason: 'every drawn element must sit inside the viewBox',
      );
    });

    test('no annotations leaves the document exactly as tall as before', () {
      // The growth is conditional. A waveform with nothing hanging below its
      // lanes must not acquire empty space at the bottom.
      final bare = render(annotations: const []);
      expect(declaredHeight(bare), 600);
    });
  });

  group('palette', () {
    test('a note with no colour of its own takes the supplied fallback', () {
      // On the canvas that fallback is the theme's primary. Baking one colour
      // into the emitter meant an export never looked like the app — and, worse,
      // that every author in a session collapsed to the same hue, destroying
      // the attribution the colour carries.
      final svg = _service.generateSvg(
        source: source,
        signalGroup: lanes,
        signalMap: signalMap,
        timeMapper: mapper,
        annotations: [_callout(rowId: rowId())],
        annotationStatuses: const {'a1': AnnotationStatus.resolved},
        palette: const SvgExportPalette(annotationDefault: '#00FF00'),
      );

      expect(svg, contains('#00FF00'));
      expect(
        svg,
        isNot(contains('#7AA2F7')),
        reason: 'the old baked accent must not survive a supplied palette',
      );
    });

    test('the background follows the palette', () {
      final svg = _service.generateSvg(
        source: source,
        signalGroup: lanes,
        signalMap: signalMap,
        timeMapper: mapper,
        palette: const SvgExportPalette(background: '#123456'),
      );
      expect(svg, contains('fill="#123456"'));
    });

    test('ruler labels use the supplied formatter, units included', () {
      // Raw ticks cannot say ns from ps. Only the viewer knows the timescale.
      final svg = _service.generateSvg(
        source: source,
        signalGroup: lanes,
        signalMap: signalMap,
        timeMapper: mapper,
        formatTime: (t) => '$t ns',
      );
      expect(svg, contains(' ns</text>'));
    });
  });
}
