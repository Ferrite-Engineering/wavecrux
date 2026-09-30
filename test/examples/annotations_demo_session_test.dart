// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/session/session_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../helpers/wellen_ffi_library_gate.dart';

/// Guards the annotation demo fixture (`examples/annotations/`).
///
/// The fixture is hand-authored JSON, which is exactly the kind of artifact
/// that rots silently: a schema change or a renamed field would leave it
/// loading with zero annotations and the demo quietly showing nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = SessionService();
  const path = 'examples/annotations/annotations-demo.wavecrux';

  test('the demo session loads with every annotation intact', () async {
    final session = await service.loadSession(path);

    expect(session.annotations.length, 8);
    expect(
      session.annotations.map((a) => a.id),
      containsAll([
        'demo-req-rise',
        'demo-bus-value',
        'demo-ack-arrow',
        'demo-handshake-band',
        'demo-lane-band',
        'demo-orphan',
        'demo-unresolved',
        'demo-collapsed',
      ]),
    );
  });

  test('it covers every shape and both anchor kinds', () async {
    final session = await service.loadSession(path);
    final shapes = session.annotations.map((a) => a.shape).toSet();
    expect(shapes, containsAll(AnnotationShape.values));

    expect(
      session.annotations.any((a) => a.anchor is PointAnchor),
      isTrue,
    );
    expect(
      session.annotations.whereType<Annotation>().any(
        (a) =>
            a.anchor is RangeAnchor && (a.anchor as RangeAnchor).rowId == null,
      ),
      isTrue,
      reason: 'a full-height band must be represented',
    );
    expect(
      session.annotations.any(
        (a) =>
            a.anchor is RangeAnchor && (a.anchor as RangeAnchor).rowId != null,
      ),
      isTrue,
      reason: 'a lane-confined band must be represented',
    );
  });

  test('the drift demo carries the witness it advertises', () async {
    final session = await service.loadSession(path);
    final bus = session.annotations.firstWhere((a) => a.id == 'demo-bus-value');
    expect(bus.witness, isNotNull);
    expect(
      bus.witness!.bits,
      '10100011',
      reason:
          'the README tells the reader to edit the VCD away from this value '
          'to see drift, so it must match what the committed trace holds at '
          'tick 500. Canonical bits, not a formatted string — a formatted '
          'witness would drift on a display-format change alone.',
    );
  });

  test(
    'the orphan and unresolved cases point away from displayed rows',
    () async {
      final session = await service.loadSession(path);
      final displayed = {'top.clk', 'top.req', 'top.ack', 'top.bus'};

      final orphan = session.annotations.firstWhere(
        (a) => a.id == 'demo-orphan',
      );
      expect(displayed.contains(orphan.rowId), isFalse);

      final unresolved = session.annotations.firstWhere(
        (a) => a.id == 'demo-unresolved',
      );
      expect(displayed.contains(unresolved.rowId), isFalse);
    },
  );

  if (requireWellenFfiLibrary('annotations demo witnesses against the trace')) {
    test('the shipped example opens NOT drifted', () async {
      // The regression this catches: the fixture's witness was authored as
      // the *formatted* value ("0xa3") while the service compares canonical
      // bits, so the demo opened permanently drifted and the README's drift
      // walkthrough was a no-op. Reading the witness back out of the JSON —
      // which is all the assertion above does — cannot catch that. Only
      // re-deriving it from the trace the example actually ships can.
      final session = await service.loadSession(path);
      final provider = WellenProvider();
      addTearDown(provider.close);
      await provider.openFile(session.sourceFilePath!);

      final byPath = <String, Variable>{
        for (final v in provider.findVariables(const SignalFilter()))
          v.fullPath: v,
      };

      const witnessService = AnnotationWitnessService();
      for (final annotation in session.annotations) {
        final witness = annotation.witness;
        if (witness == null) continue;

        final variable = byPath[annotation.rowId];
        expect(
          variable,
          isNotNull,
          reason: '${annotation.id} names a real row',
        );
        await provider.loadSignal(variable!.signalRef);

        final now = witnessService.currentBits(
          source: provider,
          signalRef: variable.signalRef,
          time: annotation.sortTime,
          bitWidth: variable.bitWidth ?? 0,
        );

        expect(
          AnnotationWitnessService.statusOf(
            annotation,
            isDisplayed: true,
            existsInFile: true,
            currentBits: now,
          ),
          AnnotationStatus.resolved,
          reason:
              '${annotation.id} ships drifted against its own committed trace',
        );
      }
    });
  }

  test(
    'the source waveform is referenced relatively so the pair travels',
    () async {
      // loadSession resolves a relative sourceFilePath against the session
      // file's own directory, so the resolved path must land next to it.
      final session = await service.loadSession(path);
      expect(session.sourceFilePath, isNotNull);
      expect(
        session.sourceFilePath!.replaceAll(r'\', '/'),
        endsWith('examples/annotations/annotations-demo.vcd'),
      );
    },
  );
}
