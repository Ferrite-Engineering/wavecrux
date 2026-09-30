// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Annotation shapes — arrow and band authoring.
//
// 5.9.1 built all three shapes in the model but the authoring UX assumed
// callout. These are the behaviours that make the other two first-class:
// bands you can resize and re-scope, and an anchor you can move by keyboard
// without the note lying about it afterwards.
//
// The nudge tests are the load-bearing ones. A nudge that moved the anchor and
// left the witness alone would make every adjusted note report drift — which
// would quietly turn the drift badge from "the design changed" into "somebody
// touched this", and the drift badge is the whole feature.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/time_selection.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

import '../../helpers/product_telemetry_config.dart';
import '../../helpers/wellen_ffi_library_gate.dart';

const _demo = 'examples/annotations/annotations-demo.vcd';

void main() {
  if (!requireWellenFfiLibrary('annotation shapes')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late String busPath;

  setUp(() async {
    container = ProviderContainer(overrides: [productTelemetryConfig])
      ..listen(annotationsProvider, (_, _) {})
      ..listen(waveformSourceProvider, (_, _) {})
      ..listen(signalGroupsProvider, (_, _) {})
      ..listen(cursorStateProvider, (_, _) {})
      ..listen(timeMapperProvider, (_, _) {})
      ..listen(annotationSnapEnabledProvider, (_, _) {})
      ..listen(annotationSelectedProvider, (_, _) {});

    final source = container.read(waveformSourceProvider.notifier);
    await source.openFile(_demo);

    final loaded = container.read(waveformSourceProvider).value!;
    final variables = loaded.findVariables(const SignalFilter());
    final bus = variables.firstWhere((v) => v.name == 'bus');
    container.read(signalGroupsProvider.notifier).addSignal(bus);
    await loaded.loadSignal(bus.signalRef);
    busPath = bus.fullPath;

    container
        .read(timeMapperProvider.notifier)
        .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);
  });

  tearDown(() async {
    await container.read(waveformSourceProvider.notifier).close();
    container.dispose();
  });

  AnnotationAuthoring authoring() =>
      container.read(annotationAuthoringProvider.notifier);
  AnnotationsNotifier notes() => container.read(annotationsProvider.notifier);
  List<Annotation> annotations() => container.read(annotationsProvider);
  Annotation only() => annotations().single;

  String createBand({String? rowId}) {
    container.read(cursorStateProvider.notifier)
      ..placePrimary(200)
      ..placeSecondary(600);
    final id = authoring().createRangeFromCursors(rowId: rowId);
    expect(id, isNotNull);
    return id!;
  }

  group('arrow authoring', () {
    test('an arrow is created through the same anchor path as a callout', () {
      final id = authoring().createAtPosition(
        dx: 400,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
        shape: AnnotationShape.arrow,
      );

      expect(id, isNotNull);
      final arrow = only();
      expect(arrow.shape, AnnotationShape.arrow);
      expect(arrow.anchor, isA<PointAnchor>());
      // The witness is captured for an arrow too. An arrow says "this edge" —
      // exactly the claim the witness exists to keep honest.
      expect(arrow.witness, isNotNull);
    });

    test('an arrow with no text survives the discard-if-empty sweep', () {
      // A callout with no body is an accident; an arrow with no body is the
      // shape working as designed.
      final id = authoring().createAtPosition(
        dx: 400,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
        shape: AnnotationShape.arrow,
      )!;

      authoring().discardIfEmpty(id);
      expect(annotations(), hasLength(1));
    });

    test('the whole draw — create plus drag — is one undo step', () {
      // This is what the canvas does: open a transaction, create, drag, close.
      notes().beginTransaction();
      final id = authoring().createAtPosition(
        dx: 400,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
        shape: AnnotationShape.arrow,
      )!;
      notes().setLabelOffset(id, 0, 0);
      for (var i = 0; i < 20; i++) {
        notes().nudgeLabel(id, 3, 1);
      }
      notes().endTransaction();

      expect(annotations(), hasLength(1));
      expect(only().labelDx, 60);

      notes().undo();
      expect(annotations(), isEmpty, reason: 'one undo removes the whole draw');
    });

    test('an abandoned draw leaves the undo stack where it started', () {
      // The too-short-arrow path: remove inside the open transaction, then
      // cancel. Anything else leaves a ⌘Z that resurrects a note the user
      // never wanted.
      notes().beginTransaction();
      final id = authoring().createAtPosition(
        dx: 400,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
        shape: AnnotationShape.arrow,
      )!;
      notes()
        ..remove(id)
        ..cancelTransaction();

      expect(annotations(), isEmpty);
      expect(notes().canUndo, isFalse);
    });
  });

  group('band authoring', () {
    test('defaults to full height, spanning no single lane', () {
      createBand();
      expect((only().anchor as RangeAnchor).rowId, isNull);
    });

    test('can be confined to a lane at creation', () {
      createBand(rowId: busPath);
      expect((only().anchor as RangeAnchor).rowId, busPath);
    });

    test('either edge moves without disturbing the other', () {
      final id = createBand();

      notes().setRangeEnd(id, isStart: true, time: 250);
      var band = only().anchor as RangeAnchor;
      expect(band.startTime, 250);
      expect(band.endTime, 600);

      notes().setRangeEnd(id, isStart: false, time: 900);
      band = only().anchor as RangeAnchor;
      expect(band.startTime, 250);
      expect(band.endTime, 900);
    });

    test('dragging an edge past the other does not swap the handles', () {
      // Mid-gesture inversion is legitimate; re-ordering the ends under the
      // pointer would make the handle being held jump to the other side.
      final id = createBand();
      notes().setRangeEnd(id, isStart: true, time: 800);

      final band = only().anchor as RangeAnchor;
      expect(band.startTime, 800);
      expect(band.endTime, 600);
      // Every reader still sees a normalised span.
      expect(band.earliest, 600);
      expect(band.latest, 800);
      expect(band.durationTicks, 200);
    });

    test('scope toggles both ways without moving the span', () {
      final id = createBand();

      notes().setRangeRow(id, busPath);
      var band = only().anchor as RangeAnchor;
      expect(band.rowId, busPath);
      expect(band.startTime, 200);
      expect(band.endTime, 600);

      notes().setRangeRow(id, null);
      band = only().anchor as RangeAnchor;
      expect(band.rowId, isNull);
      expect(band.startTime, 200);
      expect(band.endTime, 600);
    });

    test('a whole edge drag collapses to one undo step', () {
      final id = createBand();
      final before = (only().anchor as RangeAnchor).startTime;

      notes().beginTransaction();
      for (var t = before; t < before + 40; t++) {
        notes().setRangeEnd(id, isStart: true, time: t);
      }
      notes().endTransaction();

      expect((only().anchor as RangeAnchor).startTime, before + 39);
      notes().undo();
      expect((only().anchor as RangeAnchor).startTime, before);
    });

    test('the range mutators ignore a point-anchored annotation', () {
      final id = authoring().createAtPosition(
        dx: 400,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;
      final before = only();

      notes()
        ..setRangeEnd(id, isStart: true, time: 999)
        ..setRangeRow(id, null);

      expect(only(), before);
    });
  });

  group('keyboard nudge', () {
    String pointNote() => authoring().createAtPosition(
      dx: 400,
      dy: 15,
      scrollOffset: 0,
      minLaneHeight: 16,
    )!;

    test('moves the anchor one tick and reports that it moved', () {
      final id = pointNote();
      final before = (only().anchor as PointAnchor).time;

      expect(authoring().nudgeAnchor(id, direction: 1, toEdge: false), isTrue);
      expect((only().anchor as PointAnchor).time, before + 1);

      expect(authoring().nudgeAnchor(id, direction: -1, toEdge: false), isTrue);
      expect((only().anchor as PointAnchor).time, before);
    });

    test(
      're-captures the witness, so a nudged note does not read as drifted',
      () {
        // THE test for this feature. Without the re-capture the note reports
        // drift the instant it is adjusted, and the badge stops meaning "the
        // design changed".
        final id = pointNote();
        authoring().nudgeAnchor(id, direction: 1, toEdge: false);

        final statuses = container.read(annotationStatusesProvider);
        expect(statuses[id], AnnotationStatus.resolved);
      },
    );

    test('a band spans the Shift-drag selection when there is one', () {
      // WaveCrux already has a region gesture — Shift+drag paints a grey zone
      // and feeds zoom-to-selection. "Annotate this region" is the same
      // question about the same shape, so reading it from somewhere else would
      // give the app two answers to "which range do you mean", one invisible.
      container
          .read(navigationProvider.notifier)
          .setSelection(const TimeSelection(startTime: 150, endTime: 450));

      final id = authoring().createRangeFromCursors()!;
      final range = only().anchor as RangeAnchor;
      expect(range.startTime, 150);
      expect(range.endTime, 450);
      expect(id, isNotEmpty);
    });

    test('a backwards drag selection is normalised', () {
      container
          .read(navigationProvider.notifier)
          .setSelection(const TimeSelection(startTime: 450, endTime: 150));

      authoring().createRangeFromCursors();
      final range = only().anchor as RangeAnchor;
      expect(range.startTime, 150);
      expect(range.endTime, 450);
    });

    test('the selection wins over the cursors', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(800)
        ..placeSecondary(900);
      container
          .read(navigationProvider.notifier)
          .setSelection(const TimeSelection(startTime: 150, endTime: 450));

      authoring().createRangeFromCursors();
      final range = only().anchor as RangeAnchor;
      expect(range.startTime, 150, reason: 'the visible region, not a cursor');
    });

    test('the cursors remain the fallback', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(200)
        ..placeSecondary(600);

      authoring().createRangeFromCursors();
      final range = only().anchor as RangeAnchor;
      expect(range.startTime, 200);
      expect(range.endTime, 600);
    });

    test('an empty selection falls through rather than making a zero band', () {
      container
          .read(navigationProvider.notifier)
          .setSelection(const TimeSelection(startTime: 300, endTime: 300));

      expect(authoring().bandRange(), isNull);
      expect(authoring().createRangeFromCursors(), isNull);
    });

    test('setAnchorTime moves to an exact tick and re-captures', () {
      // The precision affordance the arrow nudge cannot be: at a zoom where a
      // tick is a fraction of a pixel, typing the number is the only way to
      // land on a known one. Same witness trap as the nudge above — a note that
      // reported drifted the moment you corrected its tick would make the
      // badge mean "somebody touched this".
      final id = pointNote();

      expect(authoring().setAnchorTime(id, 700), 700);
      expect((only().anchor as PointAnchor).time, 700);
      expect(
        container.read(annotationStatusesProvider)[id],
        AnnotationStatus.resolved,
      );
    });

    test('setAnchorTime clamps out-of-range rather than refusing', () {
      // A tick past the end of the trace is a typo. Silently doing nothing
      // reads as a broken field.
      final id = pointNote();

      // Returns where the anchor LANDED, not what was typed. The panel jumps
      // the viewport to this tick, and jumping to 999999 instead parks it in
      // empty space with the note nowhere in view — which reads as the note
      // having been destroyed rather than clamped.
      final landed = authoring().setAnchorTime(id, 999999);
      expect(landed, isNotNull);
      expect(landed, lessThanOrEqualTo(1000));
      expect((only().anchor as PointAnchor).time, landed);
      expect(
        container.read(annotationStatusesProvider)[id],
        AnnotationStatus.resolved,
      );
    });

    test('setAnchorTime still reports the tick when nothing moves', () {
      // Asking for the position the anchor already holds is the *clamped* case
      // in disguise: type 999999 twice and the second call moves nothing. A
      // null here would leave the caller with no tick to show, so the second
      // attempt would produce no response at all and read as a dead field.
      final id = pointNote();
      final current = (only().anchor as PointAnchor).time;
      expect(authoring().setAnchorTime(id, current), current);
    });

    test('setAnchorTime translates a band, keeping its width', () {
      // A band's anchor is the window; dragging an edge is what changes width.
      container.read(cursorStateProvider.notifier)
        ..placePrimary(200)
        ..placeSecondary(600);
      final id = authoring().createRangeFromCursors()!;

      expect(authoring().setAnchorTime(id, 300), 300);
      final range = only().anchor as RangeAnchor;
      expect(range.startTime, 300);
      expect(range.endTime, 700, reason: 'width preserved');
    });

    test('steps to the adjacent transition when asked for an edge', () {
      // Anchored on the plateau after `bus`'s last transition (at t=400), so
      // stepping back lands on that edge rather than one tick earlier.
      final id = authoring().createAtPosition(
        dx: 700,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;
      expect((only().anchor as PointAnchor).time, 700);

      expect(authoring().nudgeAnchor(id, direction: -1, toEdge: true), isTrue);
      expect(
        (only().anchor as PointAnchor).time,
        400,
        reason: 'an edge, not a tick',
      );

      final statuses = container.read(annotationStatusesProvider);
      expect(statuses[id], AnnotationStatus.resolved);
    });

    test('holds position rather than stepping when there is no next edge', () {
      // Past the signal's last transition, "next edge" has no answer. Holding
      // is right; silently falling back to a one-tick step would make the key
      // do something other than what it says.
      final id = authoring().createAtPosition(
        dx: 700,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;

      expect(authoring().nudgeAnchor(id, direction: 1, toEdge: true), isFalse);
      expect((only().anchor as PointAnchor).time, 700);
    });

    test('translates a band, keeping its width', () {
      final id = createBand();

      expect(authoring().nudgeAnchor(id, direction: 1, toEdge: false), isTrue);
      final band = only().anchor as RangeAnchor;
      expect(band.startTime, 201);
      expect(band.endTime, 601);
      expect(band.durationTicks, 400);
    });

    test('an unknown id or a zero direction does nothing', () {
      final id = pointNote();
      final before = only();

      expect(
        authoring().nudgeAnchor('nope', direction: 1, toEdge: false),
        isFalse,
      );
      expect(authoring().nudgeAnchor(id, direction: 0, toEdge: false), isFalse);
      expect(only(), before);
    });
  });

  group('selection', () {
    test('starts empty and holds what was last set', () {
      expect(container.read(annotationSelectedProvider), isNull);

      final id = authoring().createAtPosition(
        dx: 400,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;
      container.read(annotationSelectedProvider.notifier).selected = id;
      expect(container.read(annotationSelectedProvider), id);

      container.read(annotationSelectedProvider.notifier).clear();
      expect(container.read(annotationSelectedProvider), isNull);
    });
  });
}
