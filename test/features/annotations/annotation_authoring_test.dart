// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

import '../../helpers/product_telemetry_config.dart';
import '../../helpers/wellen_ffi_library_gate.dart';

/// Annotations — the three creation entry points.
///
/// They exist separately in the UI but must not diverge in what they produce:
/// the same anchor semantics, and a witness captured at creation. A path that
/// forgets the witness yields a note that can never report drift, which fails
/// silently and forever.
const _demo = 'examples/annotations/annotations-demo.vcd';

void main() {
  if (!requireWellenFfiLibrary('annotation authoring')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer(overrides: [productTelemetryConfig])
      ..listen(annotationsProvider, (_, _) {})
      ..listen(waveformSourceProvider, (_, _) {})
      ..listen(signalGroupsProvider, (_, _) {})
      ..listen(cursorStateProvider, (_, _) {})
      ..listen(timeMapperProvider, (_, _) {})
      ..listen(annotationSnapEnabledProvider, (_, _) {})
      ..listen(annotationBeingEditedProvider, (_, _) {});

    final source = container.read(waveformSourceProvider.notifier);
    await source.openFile(_demo);

    final loaded = container.read(waveformSourceProvider).value!;
    final variables = loaded.findVariables(const SignalFilter());
    final bus = variables.firstWhere((v) => v.name == 'bus');
    container.read(signalGroupsProvider.notifier).addSignal(bus);
    await loaded.loadSignal(bus.signalRef);

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
  List<Annotation> annotations() => container.read(annotationsProvider);

  group('createAtPosition', () {
    test('creates a callout anchored to the row under the pointer', () {
      final id = authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      );

      expect(id, isNotNull);
      final created = annotations().single;
      expect(created.shape, AnnotationShape.callout);
      expect(created.rowId, 'top.bus');
    });

    test('captures a witness so the note can report drift later', () {
      authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      );
      expect(
        annotations().single.witness?.bits,
        '10100011',
        reason:
            'a creation path that forgets the witness yields a note that '
            'can never drift — silently, and forever',
      );
    });

    test('snaps the anchor onto the nearby edge', () {
      // The bus transitions at 400; click a few pixels short of it.
      final id = authoring().createAtPosition(
        dx: 397,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      );
      expect(id, isNotNull);
      expect((annotations().single.anchor as PointAnchor).time, 400);
    });

    test(
      'the per-call override places freely without changing the setting',
      () {
        authoring().createAtPosition(
          dx: 397,
          dy: 15,
          scrollOffset: 0,
          minLaneHeight: 16,
          snapOverride: false,
        );
        expect((annotations().single.anchor as PointAnchor).time, 397);
        expect(
          container.read(annotationSnapEnabledProvider),
          isTrue,
          reason: 'holding a modifier is not the same as changing a preference',
        );
      },
    );

    test('returns null off any annotatable row, creating nothing', () {
      final id = authoring().createAtPosition(
        dx: 500,
        dy: 5000,
        scrollOffset: 0,
        minLaneHeight: 16,
      );
      expect(id, isNull);
      expect(annotations(), isEmpty);
    });
  });

  group('createAtCursor', () {
    test('anchors at the primary cursor on the named row', () {
      container.read(cursorStateProvider.notifier).placePrimary(700);

      final id = authoring().createAtCursor(
        rowId: 'top.bus',
        minLaneHeight: 16,
      );

      expect(id, isNotNull);
      expect((annotations().single.anchor as PointAnchor).time, 700);
      expect(annotations().single.witness, isNotNull);
    });

    test('does nothing without a cursor', () {
      final id = authoring().createAtCursor(
        rowId: 'top.bus',
        minLaneHeight: 16,
      );
      expect(id, isNull);
      expect(annotations(), isEmpty);
    });

    test('does nothing for a row that is not displayed', () {
      container.read(cursorStateProvider.notifier).placePrimary(700);
      final id = authoring().createAtCursor(
        rowId: 'top.spare',
        minLaneHeight: 16,
      );
      expect(id, isNull);
      expect(annotations(), isEmpty);
    });
  });

  group('createRangeFromCursors', () {
    test('spans the two cursors as a full-height band', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(200)
        ..placeSecondary(700);

      final id = authoring().createRangeFromCursors(label: '500 ns');

      expect(id, isNotNull);
      final band = annotations().single;
      expect(band.shape, AnnotationShape.band);
      expect(band.text, '500 ns');
      final anchor = band.anchor as RangeAnchor;
      expect(anchor.earliest, 200);
      expect(anchor.latest, 700);
      expect(anchor.rowId, isNull, reason: 'full height');
    });

    test('needs both cursors, and needs them apart', () {
      container.read(cursorStateProvider.notifier).placePrimary(200);
      expect(authoring().createRangeFromCursors(), isNull);

      container.read(cursorStateProvider.notifier).placeSecondary(200);
      expect(
        authoring().createRangeFromCursors(),
        isNull,
        reason: 'a zero-width band marks nothing',
      );
      expect(annotations(), isEmpty);
    });
  });

  group('abandoning a new annotation', () {
    test('an empty callout is discarded', () {
      final id = authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;
      expect(annotations(), hasLength(1));

      authoring().discardIfEmpty(id);

      expect(
        annotations(),
        isEmpty,
        reason: 'an accidental right-click must leave nothing behind',
      );
    });

    test('a callout with text is kept', () {
      final id = authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;
      container.read(annotationsProvider.notifier).setText(id, 'keep me');

      authoring().discardIfEmpty(id);

      expect(annotations(), hasLength(1));
    });

    test('an arrow is kept even though it has no text', () {
      final id = authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
        shape: AnnotationShape.arrow,
      )!;

      authoring().discardIfEmpty(id);

      expect(
        annotations(),
        hasLength(1),
        reason: 'an arrow legitimately carries no body',
      );
    });
  });

  group('delete', () {
    test('reports whether it removed anything', () {
      final id = authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;

      expect(authoring().delete(id), isTrue);
      expect(annotations(), isEmpty);
      expect(
        authoring().delete(id),
        isFalse,
        reason: 'the caller uses this to decide whether to offer an undo',
      );
    });

    test('a delete is undoable', () {
      final id = authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      )!;
      authoring().delete(id);

      container.read(annotationsProvider.notifier).undo();

      expect(annotations().single.id, id);
    });
  });

  group('drift, end to end through the authoring path', () {
    test('a note created here reports resolved against its own file', () {
      authoring().createAtPosition(
        dx: 500,
        dy: 15,
        scrollOffset: 0,
        minLaneHeight: 16,
      );
      final id = annotations().single.id;

      expect(
        container.read(annotationStatusesProvider)[id],
        AnnotationStatus.resolved,
      );
    });
  });
}
