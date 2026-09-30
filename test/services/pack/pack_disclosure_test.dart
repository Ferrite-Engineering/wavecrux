// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The two guards the share bundle is required to have: how much of the trace
// leaves, and how big that is before anything is written.
//
// Both are pure functions on purpose. The span rule ("the annotated window,
// padded") and the size prediction are the things a user is asked to approve,
// and a number that is only correct in the app is a number nobody can check.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/pack/pack_disclosure.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';
import 'package:wavecrux/services/vcd_writer/vcd_writer_service.dart';

import '../../helpers/fake_waveform_data_source.dart';

Annotation _point(int time, {String id = 'a', String rowId = 'top.bus'}) =>
    Annotation(
      id: id,
      shape: AnnotationShape.callout,
      anchor: PointAnchor(time: time, rowId: rowId),
      authorName: '',
      createdAt: DateTime.utc(2026, 8, 13),
    );

Annotation _band(int start, int end, {String id = 'b'}) => Annotation(
  id: id,
  shape: AnnotationShape.band,
  anchor: RangeAnchor(startTime: start, endTime: end),
  authorName: '',
  createdAt: DateTime.utc(2026, 8, 13),
);

void main() {
  const resolver = PackSpanResolver();
  const estimator = PackSizeEstimator();

  group('span resolution', () {
    test('takes the annotated span and pads it by 20% either side', () {
      final span = resolver.resolve(
        annotations: [
          _point(1000, id: 'a1'),
          _point(2000, id: 'a2'),
        ],
        sourceStart: 0,
        sourceEnd: 10000,
        fallbackStart: 0,
        fallbackEnd: 10000,
      );

      expect(span.derivedFromAnnotations, isTrue);
      expect(span.startTime, 800);
      expect(span.endTime, 2200);
    });

    test('a band contributes both of its ends', () {
      final span = resolver.resolve(
        annotations: [_band(3000, 5000)],
        sourceStart: 0,
        sourceEnd: 10000,
        fallbackStart: 4000,
        fallbackEnd: 4100,
      );

      expect(span.startTime, 2600);
      expect(span.endTime, 5400);
    });

    test('a reversed band is handled from its earlier end', () {
      final span = resolver.resolve(
        annotations: [_band(5000, 3000)],
        sourceStart: 0,
        sourceEnd: 10000,
        fallbackStart: 0,
        fallbackEnd: 10000,
      );

      expect(span.startTime, 2600);
      expect(span.endTime, 5400);
    });

    test('clamps to the source range rather than exporting past the trace', () {
      final span = resolver.resolve(
        annotations: [
          _point(100, id: 'a1'),
          _point(900, id: 'a2'),
        ],
        sourceStart: 0,
        sourceEnd: 1000,
        fallbackStart: 0,
        fallbackEnd: 1000,
      );

      expect(span.startTime, 0);
      expect(span.endTime, 1000);
    });

    test(
      'a single note pads from the viewport, not from a zero-width span',
      () {
        // 20% of nothing is nothing, and a pack containing one tick carries no
        // context at all — the note would arrive describing an edge the
        // recipient cannot see.
        final span = resolver.resolve(
          annotations: [_point(5000)],
          sourceStart: 0,
          sourceEnd: 10000,
          fallbackStart: 4000,
          fallbackEnd: 6000,
        );

        expect(span.startTime, 4600);
        expect(span.endTime, 5400);
        expect(span.durationTicks, greaterThan(0));
      },
    );

    test('falls back to the visible range when nothing is annotated', () {
      final span = resolver.resolve(
        annotations: const [],
        sourceStart: 0,
        sourceEnd: 10000,
        fallbackStart: 1200,
        fallbackEnd: 3400,
      );

      expect(span.derivedFromAnnotations, isFalse);
      expect(span.startTime, 1200);
      expect(span.endTime, 3400);
    });
  });

  group('size estimation', () {
    FakeWaveformDataSource sourceWith(int changesPerSignal, int signals) {
      final map = <String, List<SignalChange>>{};
      for (var s = 0; s < signals; s++) {
        map['ref$s'] = [
          for (var i = 0; i < changesPerSignal; i++)
            SignalChange(time: i * 10, value: i.isEven ? '0' : '1'),
        ];
      }
      return FakeWaveformDataSource(signals: map, endTime: 100000);
    }

    VcdExportConfig configFor(int signals, {int bitWidth = 1}) =>
        VcdExportConfig(
          signalRefs: [for (var s = 0; s < signals; s++) 'ref$s'],
          signalMap: {
            for (var s = 0; s < signals; s++)
              'ref$s': Variable(
                name: 'sig$s',
                varType: VarType.wire,
                direction: VarDirection.unknown,
                signalRef: 'ref$s',
                scopePath: 'top',
                bitWidth: bitWidth,
              ),
          },
          startTime: 0,
          endTime: 100000,
        );

    test('scales with the number of value changes', () {
      final small = estimator.estimateBytes(
        source: sourceWith(10, 1),
        config: configFor(1),
      );
      final large = estimator.estimateBytes(
        source: sourceWith(1000, 1),
        config: configFor(1),
      );
      expect(large, greaterThan(small * 10));
    });

    test('scales with the number of signals', () {
      final one = estimator.estimateBytes(
        source: sourceWith(100, 4),
        config: configFor(1),
      );
      final four = estimator.estimateBytes(
        source: sourceWith(100, 4),
        config: configFor(4),
      );
      expect(four, greaterThan(one * 3));
    });

    test('a wide bus costs more per change than a scalar', () {
      final scalar = estimator.estimateBytes(
        source: sourceWith(100, 1),
        config: configFor(1),
      );
      final bus = estimator.estimateBytes(
        source: sourceWith(100, 1),
        config: configFor(1, bitWidth: 64),
      );
      expect(bus, greaterThan(scalar));
    });

    test('counts the session, preview and README the caller passes in', () {
      final base = estimator.estimateBytes(
        source: sourceWith(10, 1),
        config: configFor(1),
      );
      final withExtras = estimator.estimateBytes(
        source: sourceWith(10, 1),
        config: configFor(1),
        sessionBytes: 4096,
        previewBytes: 65536,
        readmeBytes: 512,
      );
      expect(withExtras - base, 4096 + 65536 + 512);
    });
  });

  group('thresholds', () {
    PackDisclosure disclosureOf(int bytes) => PackDisclosure(
      signalPaths: const ['top.bus'],
      span: const PackSpan(
        startTime: 0,
        endTime: 100,
        derivedFromAnnotations: true,
      ),
      authorNames: const [],
      annotationCount: 1,
      estimatedBytes: bytes,
    );

    test('a small bundle trips neither guard', () {
      final small = disclosureOf(1024);
      expect(small.exceedsWarnThreshold, isFalse);
      expect(small.exceedsRefuseThreshold, isFalse);
    });

    test('an email-sized bundle warns but is still allowed', () {
      final warned = disclosureOf(WaveCruxPackSpec.warnAboveBytes + 1);
      expect(warned.exceedsWarnThreshold, isTrue);
      expect(warned.exceedsRefuseThreshold, isFalse);
    });

    test('a bundle past the hard ceiling is refused', () {
      final refused = disclosureOf(WaveCruxPackSpec.refuseAboveBytes + 1);
      expect(refused.exceedsWarnThreshold, isTrue);
      expect(refused.exceedsRefuseThreshold, isTrue);
    });

    test('the warn threshold sits below the refuse threshold', () {
      // Otherwise the warning would be unreachable — every bundle that could
      // warn would already have been refused, and the size guard would be a
      // hard stop with no gradient.
      expect(
        WaveCruxPackSpec.warnAboveBytes,
        lessThan(WaveCruxPackSpec.refuseAboveBytes),
      );
    });
  });
}
