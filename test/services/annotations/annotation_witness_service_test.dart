// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

import '../../support/fake_waveform_source.dart';

/// Annotations — the witness value.
///
/// These tests exist because the witness is the one thing a callout drawn on a
/// screenshot cannot do. If drift stops being detected, annotations quietly
/// degrade into decoration and nothing crashes to tell us. If drift starts
/// firing when it should not, users learn to ignore the badge, which costs
/// more than the feature is worth — so the false-positive cases are here too.
const _service = AnnotationWitnessService();

/// A one-signal source whose 8-bit `top.bus` takes the given [changes],
/// already loaded so value queries answer.
Future<FakeWaveformSource> _busSource(List<SignalChange> changes) async {
  final source = FakeWaveformSource(
    endTime: 1000,
    rootScopes: [
      const Scope(
        name: 'top',
        type: ScopeType.module,
        path: 'top',
        variables: [
          Variable(
            name: 'bus',
            varType: VarType.wire,
            direction: VarDirection.input,
            signalRef: 'ref-bus',
            scopePath: 'top',
            bitWidth: 8,
          ),
        ],
      ),
    ],
    changes: {'ref-bus': changes},
  );
  await source.loadSignal('ref-bus');
  return source;
}

Annotation _annotation({AnnotationWitness? witness, String row = 'top.bus'}) =>
    Annotation(
      id: 'a1',
      shape: AnnotationShape.callout,
      anchor: PointAnchor(time: 100, rowId: row),
      authorName: 'Martin',
      createdAt: DateTime.utc(2026, 8, 12),
      text: 'this should still be a3 here',
      witness: witness,
    );

void main() {
  group('capture', () {
    test('records canonical bits at the anchored tick', () async {
      final source = await _busSource(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 50, value: '10100011'),
      ]);

      final witness = _service.capture(
        source: source,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );

      expect(witness, isNotNull);
      expect(
        witness!.bits,
        '10100011',
        reason:
            'canonical bits rather than a formatted string; the '
            'format-independence group below explains why',
      );
      expect(witness.edgeOrdinal, 1, reason: 'the second transition');
    });

    test('pads to the declared width', () async {
      // VCD elides leading zeros: the reader hands back "0", not "00000000".
      final source = await _busSource(const [
        SignalChange(time: 0, value: '0'),
      ]);
      final witness = _service.capture(
        source: source,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );
      expect(witness!.bits, '00000000');
    });

    test('returns null before the signal has any recorded value', () async {
      final source = await _busSource(const [
        SignalChange(time: 500, value: '00000001'),
      ]);
      expect(
        _service.capture(
          source: source,
          signalRef: 'ref-bus',
          time: 100,
          bitWidth: 8,
        ),
        isNull,
      );
    });
  });

  group('describe — the reader sees their own radix', () {
    test('renders witness bits in the requested display format', () {
      expect(_service.describe('10100011', bitWidth: 8), 'a3');
      expect(
        _service.describe(
          '10100011',
          bitWidth: 8,
          format: DisplayFormat.unsignedDecimal,
        ),
        '163',
      );
      expect(
        _service.describe(
          '10100011',
          bitWidth: 8,
          format: DisplayFormat.binary,
        ),
        '10100011',
      );
    });
  });

  group('statusOf — the decision table', () {
    test('matching bits are resolved', () {
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: const AnnotationWitness(bits: '10100011')),
          isDisplayed: true,
          existsInFile: true,
          currentBits: '10100011',
        ),
        AnnotationStatus.resolved,
      );
    });

    test('changed bits are drifted', () {
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: const AnnotationWitness(bits: '10100011')),
          isDisplayed: true,
          existsInFile: true,
          currentBits: '00000000',
        ),
        AnnotationStatus.drifted,
      );
    });

    test('a signal present but not on screen is orphaned', () {
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: const AnnotationWitness(bits: '10100011')),
          isDisplayed: false,
          existsInFile: true,
          currentBits: '10100011',
        ),
        AnnotationStatus.orphaned,
      );
    });

    test('a signal absent from the file is unresolved', () {
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: const AnnotationWitness(bits: '10100011')),
          isDisplayed: false,
          existsInFile: false,
        ),
        AnnotationStatus.unresolved,
      );
    });

    test('unresolved outranks orphaned — absent beats merely hidden', () {
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(),
          isDisplayed: true,
          existsInFile: false,
        ),
        AnnotationStatus.unresolved,
      );
    });

    test('a full-height band is never drifted or orphaned', () {
      final band = Annotation(
        id: 'b',
        shape: AnnotationShape.band,
        anchor: const RangeAnchor(startTime: 0, endTime: 10),
        authorName: 'M',
        createdAt: DateTime.utc(2026),
      );
      expect(
        AnnotationWitnessService.statusOf(
          band,
          isDisplayed: false,
          existsInFile: false,
        ),
        AnnotationStatus.unanchoredToRow,
      );
    });

    test('no witness means nothing to drift against', () {
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(),
          isDisplayed: true,
          existsInFile: true,
          currentBits: '11111111',
        ),
        AnnotationStatus.resolved,
        reason: 'flagging drift with no baseline would be noise, not signal',
      );
    });

    test('unreadable current bits do not fake drift', () {
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: const AnnotationWitness(bits: '10100011')),
          isDisplayed: true,
          existsInFile: true,
        ),
        AnnotationStatus.resolved,
      );
    });
  });

  group('drift is independent of how the row is displayed', () {
    test(
      'changing the display format does not drift an unchanged note',
      () async {
        final source = await _busSource(const [
          SignalChange(time: 0, value: '10100011'),
        ]);
        final witness = _service.capture(
          source: source,
          signalRef: 'ref-bus',
          time: 100,
          bitWidth: 8,
        );

        // The same value, re-read after the user flips the row hex → decimal.
        // currentBits takes no format argument at all, which is the point:
        // there is no way for a display preference to reach this comparison.
        final now = _service.currentBits(
          source: source,
          signalRef: 'ref-bus',
          time: 100,
          bitWidth: 8,
        );

        expect(
          AnnotationWitnessService.statusOf(
            _annotation(witness: witness),
            isDisplayed: true,
            existsInFile: true,
            currentBits: now,
          ),
          AnnotationStatus.resolved,
          reason:
              'a badge that fires on a radix change is a badge users learn '
              'to ignore',
        );
      },
    );

    test('a compactly-written zero matches a padded one', () async {
      final compact = await _busSource(const [
        SignalChange(time: 0, value: '0'),
      ]);
      final padded = await _busSource(const [
        SignalChange(time: 0, value: '00000000'),
      ]);

      final witness = _service.capture(
        source: compact,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );
      final now = _service.currentBits(
        source: padded,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );

      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: witness),
          isDisplayed: true,
          existsInFile: true,
          currentBits: now,
        ),
        AnnotationStatus.resolved,
        reason:
            'VCD elides leading zeros; drifting on notation alone would '
            'flag half the notes in a re-exported dump',
      );
    });
  });

  group('the thesis: a re-simulated design flags its own stale notes', () {
    test('annotate, re-run with a different value, reload → drifted', () async {
      final originalRun = await _busSource(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 50, value: '10100011'),
      ]);
      final witness = _service.capture(
        source: originalRun,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );

      // The RTL is fixed and re-simulated: same signal, same tick, new value.
      final rerun = await _busSource(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 50, value: '00000000'),
      ]);
      final now = _service.currentBits(
        source: rerun,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );

      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: witness),
          isDisplayed: true,
          existsInFile: true,
          currentBits: now,
        ),
        AnnotationStatus.drifted,
        reason:
            'this is the entire differentiator over annotating a screenshot',
      );
    });

    test('an unchanged re-run leaves the note resolved', () async {
      final run = await _busSource(const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 50, value: '10100011'),
      ]);
      final witness = _service.capture(
        source: run,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );
      final now = _service.currentBits(
        source: run,
        signalRef: 'ref-bus',
        time: 100,
        bitWidth: 8,
      );
      expect(
        AnnotationWitnessService.statusOf(
          _annotation(witness: witness),
          isDisplayed: true,
          existsInFile: true,
          currentBits: now,
        ),
        AnnotationStatus.resolved,
      );
    });
  });
}
