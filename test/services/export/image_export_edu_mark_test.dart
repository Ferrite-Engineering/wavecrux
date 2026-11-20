// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The educational-licence mark on image exports: present in the PNG and the
// SVG when the caller passes one, and the documents are exactly what they
// always were when it does not.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../helpers/fake_waveform_data_source.dart';

const _service = ImageExportService();
const _mark = 'Made with WaveCrux Educational · Non-commercial use only';

final _source = FakeWaveformDataSource(
  signals: {
    'clk': const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 500, value: '1'),
    ],
  },
);

final _group = SignalGroup(
  entries: [SignalEntry.signal(signalRef: 'clk', displayName: 'clk')],
);

final _signalMap = {
  'clk': const Variable(
    name: 'clk',
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: 'clk',
    scopePath: 'top',
    bitWidth: 1,
  ),
};

final _mapper = TimeMapper.fitAll(
  startTime: 0,
  endTime: 1000,
  viewportWidth: 1040,
);

String _svg({String? eduMark}) => _service.generateSvg(
  source: _source,
  signalGroup: _group,
  signalMap: _signalMap,
  timeMapper: _mapper,
  eduMark: eduMark,
);

/// RGBA of the pixel at ([x], [y]) in a PNG.
Future<List<int>> _pixel(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = (await image.toByteData())!;
  final offset = (y * image.width + x) * 4;
  final rgba = [for (var i = 0; i < 4; i++) data.getUint8(offset + i)];
  image.dispose();
  codec.dispose();
  return rgba;
}

void main() {
  group('generateSvg — educational-licence mark', () {
    test('writes the mark as a text element, bottom-right', () {
      final svg = _svg(eduMark: _mark);

      expect(svg, contains('class="crux-edu-mark"'));
      expect(svg, contains('text-anchor="end"'));
      expect(svg, contains('>$_mark</text>'));
      // The last element before the document closes, below everything else.
      expect(
        svg.trimRight(),
        endsWith('>$_mark</text>\n</svg>'),
      );
    });

    test('grows the document by a band for the mark', () {
      final plain = _svg();
      final marked = _svg(eduMark: _mark);
      final heightOf = RegExp('<svg[^>]* height="([0-9.]+)"');

      final plainHeight = double.parse(heightOf.firstMatch(plain)!.group(1)!);
      final markedHeight = double.parse(
        heightOf.firstMatch(marked)!.group(1)!,
      );
      expect(markedHeight, plainHeight + 18);
    });

    test('escapes the mark as XML', () {
      final svg = _svg(eduMark: 'A & <B>');

      expect(svg, contains('A &amp; &lt;B&gt;'));
      expect(svg, isNot(contains('A & <B>')));
    });

    test('without a mark the document is unchanged and unmarked', () {
      final svg = _svg();

      expect(svg, isNot(contains('crux-edu-mark')));
      expect(svg, isNot(contains('Educational')));
    });
  });

  group('capturePng — educational-licence mark', () {
    testWidgets('paints the mark bottom-right and nowhere else', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 400,
                height: 120,
                child: ColoredBox(color: Color(0xFF000000)),
              ),
            ),
          ),
        ),
      );

      final (plain, marked) = (await tester.runAsync(() async {
        final plain = await _service.capturePng(key, pixelRatio: 1);
        final marked = await _service.capturePng(
          key,
          pixelRatio: 1,
          eduMark: _mark,
        );
        return (plain, marked);
      }))!;

      expect(marked, isNot(plain));
      final cornerPlain = (await tester.runAsync(
        () => _pixel(plain, 390, 110),
      ))!;
      final cornerMarked = (await tester.runAsync(
        () => _pixel(marked, 390, 110),
      ))!;
      final originPlain = (await tester.runAsync(() => _pixel(plain, 2, 2)))!;
      final originMarked = (await tester.runAsync(
        () => _pixel(marked, 2, 2),
      ))!;

      // Black capture; the mark's light plate lands in the bottom-right
      // corner and leaves the top-left untouched.
      expect(cornerPlain, [0, 0, 0, 255]);
      expect(cornerMarked, isNot(cornerPlain));
      expect(originMarked, originPlain);
    });

    testWidgets('without a mark the capture is identical', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 200,
                height: 60,
                child: ColoredBox(color: Color(0xFF336699)),
              ),
            ),
          ),
        ),
      );

      final (a, b) = (await tester.runAsync(() async {
        final a = await _service.capturePng(key, pixelRatio: 1);
        final b = await _service.capturePng(key, pixelRatio: 1);
        return (a, b);
      }))!;

      expect(a, b);
    });
  });
}
