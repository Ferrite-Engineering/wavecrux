// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Annotation walkthrough mode.
//
// This is what turns an annotated waveform into a document somebody else can
// drive: the notes in the order they happened, each centred and expanded in
// turn. Two behaviours here are easy to get subtly wrong and hard to notice —
// the WRAP (silence at the end reads as a broken key) and the UNDO STACK
// (folding a balloon per step would put twenty entries between the reader and
// the author's last real edit).

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/annotation_walkthrough_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../../helpers/product_telemetry_config.dart';
import '../../helpers/wellen_ffi_library_gate.dart';

const _demo = 'examples/annotations/annotations-demo.vcd';
const _lane = 24.0;

void main() {
  if (!requireWellenFfiLibrary('annotation walkthrough')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late String busPath;

  setUp(() async {
    container = ProviderContainer(overrides: [productTelemetryConfig])
      ..listen(annotationsProvider, (_, _) {})
      ..listen(waveformSourceProvider, (_, _) {})
      ..listen(signalGroupsProvider, (_, _) {})
      ..listen(timeMapperProvider, (_, _) {})
      ..listen(waveformScrollProvider, (_, _) {})
      ..listen(annotationWalkthroughProvider, (_, _) {});

    await container.read(waveformSourceProvider.notifier).openFile(_demo);
    final loaded = container.read(waveformSourceProvider).value!;
    final bus = loaded
        .findVariables(const SignalFilter())
        .firstWhere((v) => v.name == 'bus');
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

  AnnotationWalkthrough tour() =>
      container.read(annotationWalkthroughProvider.notifier);
  WalkthroughState state() => container.read(annotationWalkthroughProvider);
  AnnotationsNotifier notes() => container.read(annotationsProvider.notifier);

  /// Three notes, deliberately added out of time order so the tour has to sort
  /// rather than follow insertion.
  void seed() {
    for (final (id, time) in const [
      ('mid', 400),
      ('last', 800),
      ('first', 100),
    ]) {
      notes().add(
        Annotation(
          id: id,
          shape: AnnotationShape.callout,
          anchor: PointAnchor(time: time, rowId: busPath),
          authorName: '',
          createdAt: DateTime.utc(2026, 8, 13),
          text: 'note $id',
        ),
      );
    }
  }

  group('ordering', () {
    test('steps in time order, not insertion order', () {
      seed();

      expect(tour().next(minLaneHeight: _lane), isTrue);
      expect(state().focusedId, 'first');
      tour().next(minLaneHeight: _lane);
      expect(state().focusedId, 'mid');
      tour().next(minLaneHeight: _lane);
      expect(state().focusedId, 'last');
    });

    test('the first backward step opens at the end', () {
      // `[` with no tour in progress should land on the last note, so either
      // key opens the tour from the end it points away from.
      seed();
      expect(tour().previous(minLaneHeight: _lane), isTrue);
      expect(state().focusedId, 'last');
    });

    test('does nothing, and says so, when there is nothing to step', () {
      expect(tour().next(minLaneHeight: _lane), isFalse);
      expect(state().focusedId, isNull);
    });
  });

  group('wrapping', () {
    test('past the end comes back to the start and flags the wrap', () {
      seed();
      tour()
        ..next(minLaneHeight: _lane)
        ..next(minLaneHeight: _lane)
        ..next(minLaneHeight: _lane);
      expect(state().focusedId, 'last');
      expect(state().wrapped, isFalse);

      tour().next(minLaneHeight: _lane);
      expect(state().focusedId, 'first');
      expect(
        state().wrapped,
        isTrue,
        reason: 'silence at the wrap reads as a key that did nothing',
      );
    });

    test('past the start comes back to the end and flags the wrap', () {
      seed();
      tour().next(minLaneHeight: _lane);
      expect(state().focusedId, 'first');

      tour().previous(minLaneHeight: _lane);
      expect(state().focusedId, 'last');
      expect(state().wrapped, isTrue);
    });

    test('an ordinary step does not flag a wrap', () {
      seed();
      tour()
        ..next(minLaneHeight: _lane)
        ..next(minLaneHeight: _lane);
      expect(state().wrapped, isFalse);
    });
  });

  group('the expand / collapse handoff', () {
    Annotation byId(String id) =>
        container.read(annotationsProvider).firstWhere((a) => a.id == id);

    test('expands the focused note and folds the one it came from', () {
      seed();
      tour().next(minLaneHeight: _lane);
      expect(byId('first').collapsed, isFalse);

      tour().next(minLaneHeight: _lane);
      expect(byId('first').collapsed, isTrue);
      expect(byId('mid').collapsed, isFalse);
    });

    test('leaves the undo stack untouched across a whole tour', () {
      // THE one that matters for a reader. Stepping is reading, not editing:
      // three steps must not put six entries between them and the author's
      // last real change.
      seed();
      expect(notes().canUndo, isTrue, reason: 'the three adds are undoable');
      final before = container.read(annotationsProvider);

      tour()
        ..next(minLaneHeight: _lane)
        ..next(minLaneHeight: _lane)
        ..next(minLaneHeight: _lane)
        ..previous(minLaneHeight: _lane);

      notes().undo();
      // One undo lands on the state before the last *edit* — the third add —
      // rather than on some intermediate collapse bookkeeping.
      expect(container.read(annotationsProvider).length, before.length - 1);
    });
  });

  group('view movement', () {
    test('centres the focused note at the current zoom', () {
      seed();
      // Zoom to a window narrower than the trace. At fit-all there is nowhere
      // to centre *to* — the viewport already spans everything and the pan
      // clamps — so the assertion would be about the clamp, not the feature.
      container.read(timeMapperProvider.notifier).zoomToRange(0, 200);
      final zoomBefore = container.read(timeMapperProvider).ticksPerPixel;

      tour()
        ..next(minLaneHeight: _lane)
        ..next(minLaneHeight: _lane);

      final mapper = container.read(timeMapperProvider);
      final centre = (mapper.visibleStartTime + mapper.visibleEndTime) / 2;
      expect(centre, closeTo(400, mapper.visibleRange * 0.05));
      expect(
        mapper.ticksPerPixel,
        closeTo(zoomBefore, zoomBefore * 0.01),
        reason: 'centring must not change the zoom',
      );
    });

    test('scrolls the annotated row into view', () {
      seed();
      tour().next(minLaneHeight: _lane);
      // The bus row is the only lane, so its top is 0 — the assertion is that
      // the offset was set at all rather than left untouched at its default.
      expect(container.read(waveformScrollProvider), isNotNull);
    });

    test('selects the focused note so the keyboard agrees with the tour', () {
      seed();
      tour().next(minLaneHeight: _lane);
      expect(container.read(annotationSelectedProvider), 'first');
    });
  });

  group('playback', () {
    test('steps immediately rather than waiting out the first dwell', () {
      seed();
      tour().play(minLaneHeight: _lane);

      expect(state().playing, isTrue);
      expect(
        state().focusedId,
        'first',
        reason: 'a control that does nothing for four seconds reads as broken',
      );
      tour().pause();
    });

    test('pause stops the ticker but keeps the position', () {
      seed();
      tour()
        ..play(minLaneHeight: _lane)
        ..pause();

      expect(state().playing, isFalse);
      expect(state().focusedId, 'first');
    });

    test('stop clears the position too', () {
      seed();
      tour()
        ..play(minLaneHeight: _lane)
        ..stop();

      expect(state().playing, isFalse);
      expect(state().focusedId, isNull);
    });

    test('toggle flips both ways', () {
      seed();
      tour().toggle(minLaneHeight: _lane);
      expect(state().playing, isTrue);
      tour().toggle(minLaneHeight: _lane);
      expect(state().playing, isFalse);
    });

    test('advances on the dwell', () {
      fakeAsync((async) {
        seed();
        tour().play(minLaneHeight: _lane);
        expect(state().focusedId, 'first');

        async.elapse(kWalkthroughDefaultDwell);
        expect(state().focusedId, 'mid');

        async.elapse(kWalkthroughDefaultDwell);
        expect(state().focusedId, 'last');

        tour().pause();
      });
    });

    test('a changed dwell takes effect immediately, not after the old one', () {
      fakeAsync((async) {
        seed();
        tour()
          ..play(minLaneHeight: _lane)
          ..setDwell(const Duration(seconds: 1));

        expect(state().dwell, const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        expect(state().focusedId, 'mid');

        tour().pause();
      });
    });

    test('a rejected dwell leaves the old one alone', () {
      tour().setDwell(Duration.zero);
      expect(state().dwell, kWalkthroughDefaultDwell);
    });
  });
}
