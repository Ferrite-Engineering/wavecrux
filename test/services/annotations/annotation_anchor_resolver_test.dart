// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/annotations/annotation_anchor_resolver.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../support/fake_waveform_source.dart';

/// Annotations — resolving a click to an anchor.
///
/// Edge snapping is the load-bearing behaviour here: an unsnapped anchor
/// captures the witness on the wrong side of the transition, so the note
/// records the value the signal held *before* the event it describes. That is
/// silent, and it poisons the one case the feature exists for.
const _resolver = AnnotationAnchorResolver();

/// 1000 ticks across 1000 px — one tick per pixel, so pixel distances in these
/// tests read directly as tick distances.
const _mapper = TimeMapper(
  startTime: 0,
  endTime: 1000,
  viewportWidth: 1000,
  ticksPerPixel: 1,
  panOffsetTicks: 0,
);

Variable _bus() => const Variable(
  name: 'bus',
  varType: VarType.wire,
  direction: VarDirection.input,
  signalRef: 'ref-bus',
  scopePath: 'top',
  bitWidth: 8,
);

/// Geometry with one 30 px signal lane at the top, then a comment row that is
/// deliberately not annotatable.
LaneGeometry _geometry() => LaneGeometry(
  entries: [
    SignalEntry.signal(
      signalRef: 'ref-bus',
      signalPath: 'top.bus',
      displayName: 'bus',
    ),
    const SignalEntry.comment(text: 'not annotatable'),
  ],
  metrics: const LaneMetrics(minLaneHeight: 16),
);

Future<FakeWaveformSource> _source(List<SignalChange> changes) async {
  final source = FakeWaveformSource(
    endTime: 1000,
    rootScopes: [
      Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        variables: [_bus()],
      ),
    ],
    changes: {'ref-bus': changes},
  );
  await source.loadSignal('ref-bus');
  return source;
}

void main() {
  group('row hit-testing', () {
    test('resolves a click inside the signal lane', () async {
      final resolved = _resolver.resolve(
        position: const Offsetish(300, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: await _source(const [SignalChange(time: 0, value: '0')]),
      );
      expect(resolved, isNotNull);
      expect(resolved!.rowId, 'top.bus');
      expect(resolved.signalRef, 'ref-bus');
    });

    test('returns null below every row', () async {
      final resolved = _resolver.resolve(
        position: const Offsetish(300, 5000),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: await _source(const [SignalChange(time: 0, value: '0')]),
      );
      expect(resolved, isNull);
    });

    test('a comment row is not annotatable', () async {
      // The comment sits directly below the 30 px signal lane.
      final resolved = _resolver.resolve(
        position: const Offsetish(300, 40),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: await _source(const [SignalChange(time: 0, value: '0')]),
      );
      expect(
        resolved,
        isNull,
        reason: 'no stable identity to anchor to and no value to witness',
      );
    });

    test('the scroll offset maps viewport y into content space', () async {
      final source = await _source(const [SignalChange(time: 0, value: '0')]);
      // Scrolled down 30 px, the signal lane's content band (0–30) now sits at
      // viewport y −30..0, so a click at viewport y 15 is past it.
      final scrolled = _resolver.resolve(
        position: const Offsetish(300, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 30,
        source: source,
      );
      expect(scrolled, isNull);
    });
  });

  group('edge snapping', () {
    test('snaps to a transition within the radius', () async {
      final source = await _source(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 500, value: '10100011'),
      ]);
      // Click three pixels shy of the edge at 500.
      final resolved = _resolver.resolve(
        position: const Offsetish(497, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: source,
      );
      expect(resolved!.time, 500);
      expect(resolved.snapped, isTrue);
    });

    test('does not snap beyond the radius', () async {
      final source = await _source(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 500, value: '10100011'),
      ]);
      final resolved = _resolver.resolve(
        position: const Offsetish(450, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: source,
      );
      expect(resolved!.time, 450);
      expect(resolved.snapped, isFalse);
    });

    test(
      'a click far from any edge stays put — snapping is not a magnet',
      () async {
        final source = await _source(const [
          SignalChange(time: 0, value: '00000000'),
          SignalChange(time: 500, value: '10100011'),
        ]);
        final resolved = _resolver.resolve(
          position: const Offsetish(250, 15),
          mapper: _mapper,
          geometry: _geometry(),
          scrollOffset: 0,
          source: source,
        );
        expect(
          resolved!.time,
          250,
          reason:
              'if valueAt were used as the exact-hit probe every click would '
              'report itself as an edge and snapping would be a no-op',
        );
        expect(resolved.snapped, isFalse);
      },
    );

    test('picks the nearer of two edges in range', () async {
      final source = await _source(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 498, value: '10100011'),
        SignalChange(time: 504, value: '00000000'),
      ]);
      final resolved = _resolver.resolve(
        position: const Offsetish(500, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: source,
      );
      expect(resolved!.time, 498);
    });

    test('a click exactly on an edge keeps that edge', () async {
      final source = await _source(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 500, value: '10100011'),
      ]);
      final resolved = _resolver.resolve(
        position: const Offsetish(500, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: source,
      );
      expect(resolved!.time, 500);
      expect(
        resolved.snapped,
        isTrue,
        reason:
            'prevTransition is strictly-before and nextTransition '
            'strictly-after, so the edge underfoot needs its own probe',
      );
    });

    test('the modifier override places freely', () async {
      final source = await _source(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 500, value: '10100011'),
      ]);
      final resolved = _resolver.resolve(
        position: const Offsetish(497, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
        source: source,
        snapToEdges: false,
      );
      expect(resolved!.time, 497);
      expect(resolved.snapped, isFalse);
    });

    test('no source means no snapping, not a crash', () {
      final resolved = _resolver.resolve(
        position: const Offsetish(497, 15),
        mapper: _mapper,
        geometry: _geometry(),
        scrollOffset: 0,
      );
      expect(resolved!.time, 497);
      expect(resolved.snapped, isFalse);
    });
  });

  group('the snap radius is measured in pixels, not ticks', () {
    test('the same tick gap snaps in at one zoom and not at another', () async {
      final source = await _source(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 500, value: '10100011'),
      ]);

      // Zoomed out: 10 ticks per pixel. A click 5 px away is 50 ticks away and
      // must still snap, because the user cannot aim finer than a pixel.
      const coarse = TimeMapper(
        startTime: 0,
        endTime: 10000,
        viewportWidth: 1000,
        ticksPerPixel: 10,
        panOffsetTicks: 0,
      );
      final zoomedOut = _resolver.resolve(
        position: const Offsetish(45, 15),
        mapper: coarse,
        geometry: _geometry(),
        scrollOffset: 0,
        source: source,
      );
      expect(zoomedOut!.time, 500);
      expect(zoomedOut.snapped, isTrue);

      // Zoomed in: 0.1 ticks per pixel. The same 50-tick gap is now 500 px
      // away and must NOT snap — at this zoom the user is aiming deliberately.
      const fine = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 1000,
        ticksPerPixel: 0.1,
        panOffsetTicks: 0,
      );
      final zoomedIn = _resolver.resolve(
        position: const Offsetish(4500, 15),
        mapper: fine,
        geometry: _geometry(),
        scrollOffset: 0,
        source: source,
      );
      expect(zoomedIn!.snapped, isFalse);
    });
  });
}
