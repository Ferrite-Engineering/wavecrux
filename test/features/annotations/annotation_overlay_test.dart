// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_overlay.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

/// Annotations — the canvas overlay.
///
/// The projection tests are the load-bearing ones: an annotation that stops
/// tracking its edge under pan/zoom has silently become the screenshot
/// workflow it exists to replace.

Variable _v(String name, {int width = 1}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: width,
);

Annotation _callout({
  String id = 'a1',
  int time = 500,
  String row = 'top.data',
  String text = 'look here',
  bool collapsed = false,
}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: row),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12),
  text: text,
  collapsed: collapsed,
);

/// Pumps the overlay inside a sized box with a container whose signal list and
/// time mapper are configured for a 0–1000 tick, 1000 px viewport.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Annotation> annotations,
  Map<String, AnnotationStatus> statuses = const {},
  List<String> displayed = const ['data'],
  List<WritingChip> chips = const [],
  double scrollOffset = 0,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (statuses.isNotEmpty)
        annotationStatusesProvider.overrideWithValue(statuses),
      // The chip set is overridden rather than driven through a fake session:
      // what it resolves from the room's state is `session_annotations_test`'s
      // subject, and what the canvas does with it is this file's.
      if (chips.isNotEmpty)
        writingAnnotationChipsProvider.overrideWithValue(chips),
    ],
  );
  addTearDown(container.dispose);

  // Hold the providers we are about to configure. Without a live dependent,
  // each `read` closes its external subscription, Riverpod schedules a
  // zero-duration dispose task, and the binding fails the test on a pending
  // timer that has nothing to do with the overlay.
  // No fireImmediately: the immediate read itself trips mayNeedDispose and
  // schedules the very timer we are avoiding. The subscription alone is what
  // keeps the element alive.
  container
    ..listen(signalGroupsProvider, (_, _) {})
    ..listen(timeMapperProvider, (_, _) {})
    ..listen(annotationsProvider, (_, _) {});

  final groups = container.read(signalGroupsProvider.notifier);
  for (final name in displayed) {
    groups.addSignal(_v(name, width: 8));
  }
  container
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 1000, viewportWidth: 1000);
  annotations.forEach(container.read(annotationsProvider.notifier).add);

  await tester.pumpWidget(_tree(container, scrollOffset));
  return container;
}

/// The widget tree, factored out so a test can re-pump with a different
/// [scrollOffset] against the **same** container. Handing
/// `UncontrolledProviderScope` a fresh container instead tears the consumer
/// down, and the unmount schedules a dispose timer the binding then fails on.
Widget _tree(ProviderContainer container, double scrollOffset) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // The balloon reads L10N for its delete tooltip and editor hint, so
        // the harness has to supply the delegates.
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 400,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnnotationOverlay(scrollOffset: scrollOffset),
                ),
              ],
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders nothing when there are no annotations', (tester) async {
    await _pump(tester, annotations: []);
    // The overlay collapses to SizedBox.shrink, so it contributes no Stack.
    // (Asserting on CustomPaint would catch Material's own chrome instead.)
    expect(
      find.descendant(
        of: find.byType(AnnotationOverlay),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
    expect(find.text('look here'), findsNothing);
  });

  testWidgets('draws a callout balloon with its text', (tester) async {
    await _pump(
      tester,
      annotations: [_callout()],
      statuses: {'a1': AnnotationStatus.resolved},
    );
    expect(find.text('look here'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'the number badge');
  });

  testWidgets('a collapsed annotation shows a dot, not its text', (
    tester,
  ) async {
    await _pump(
      tester,
      annotations: [_callout(collapsed: true)],
      statuses: {'a1': AnnotationStatus.resolved},
    );
    expect(find.text('look here'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an arrow never renders a balloon', (tester) async {
    final arrow = Annotation(
      id: 'arrow',
      shape: AnnotationShape.arrow,
      anchor: const PointAnchor(time: 500, rowId: 'top.data'),
      authorName: 'M',
      createdAt: DateTime.utc(2026),
      text: 'ignored for an arrow',
    );
    await _pump(
      tester,
      annotations: [arrow],
      statuses: {'arrow': AnnotationStatus.resolved},
    );
    expect(find.text('ignored for an arrow'), findsNothing);
  });

  group('orphans stay off the canvas', () {
    testWidgets('an orphaned annotation draws nothing', (tester) async {
      await _pump(
        tester,
        annotations: [_callout(row: 'top.hidden')],
        statuses: {'a1': AnnotationStatus.orphaned},
      );
      expect(
        find.text('look here'),
        findsNothing,
        reason:
            'the panel owns orphans; piling them at y=12 is the bug '
            'this avoids',
      );
    });

    testWidgets('an unresolved annotation draws nothing', (tester) async {
      await _pump(
        tester,
        annotations: [_callout(row: 'top.gone')],
        statuses: {'a1': AnnotationStatus.unresolved},
      );
      expect(find.text('look here'), findsNothing);
    });

    testWidgets('a row absent from the geometry is skipped safely', (
      tester,
    ) async {
      // Status says resolved but the row is not displayed — the projection
      // must return null rather than throwing or drawing at a bogus Y.
      await _pump(
        tester,
        annotations: [_callout(row: 'top.not_here')],
        statuses: {'a1': AnnotationStatus.resolved},
      );
      expect(find.text('look here'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('projection tracks the view', () {
    testWidgets('a balloon re-projects when the view changes', (tester) async {
      final container = await _pump(
        tester,
        annotations: [_callout()],
        statuses: {'a1': AnnotationStatus.resolved},
      );
      final before = tester.getTopLeft(find.text('look here'));

      // Zoom rather than pan: at fit-all the whole range is already visible,
      // so the mapper legitimately clamps a pan to no movement.
      container.read(timeMapperProvider.notifier).zoomToRange(400, 700);
      await tester.pump();

      final after = tester.getTopLeft(find.text('look here'));
      expect(
        after.dx,
        isNot(before.dx),
        reason:
            'the anchor is data-space; the view moving must move its '
            'projection',
      );
    });

    testWidgets('an off-screen point annotation is not drawn', (tester) async {
      final container = await _pump(
        tester,
        annotations: [_callout()],
        statuses: {'a1': AnnotationStatus.resolved},
      );
      expect(find.text('look here'), findsOneWidget);

      // Zoom to a window that excludes tick 500 entirely.
      container.read(timeMapperProvider.notifier).zoomToRange(700, 900);
      await tester.pump();

      expect(find.text('look here'), findsNothing);
    });

    testWidgets('scrolling shifts the anchor vertically', (tester) async {
      // An explicit positive offset keeps the label clear of the top-edge
      // clamp, which would otherwise pin both positions to the same y and
      // make the assertion vacuous.
      final container = await _pump(
        tester,
        annotations: [_callout().copyWith(labelDy: 80)],
        statuses: {'a1': AnnotationStatus.resolved},
      );
      final unscrolled = tester.getTopLeft(find.text('look here'));

      // Same container, new scroll offset — see _tree's doc comment for why
      // re-pumping with a fresh container would be the wrong instrument.
      await tester.pumpWidget(_tree(container, 40));
      final scrolled = tester.getTopLeft(find.text('look here'));

      expect(
        scrolled.dy,
        unscrolled.dy - 40,
        reason:
            'row tops are content-space; the overlay maps them into the '
            'viewport by subtracting the scroll offset',
      );
    });
  });

  group('crowding folds the excess', () {
    testWidgets('past the cap, later balloons render collapsed', (
      tester,
    ) async {
      final many = [
        for (var i = 0; i < kMaxExpandedBalloons + 3; i++)
          _callout(id: 'a$i', time: 100 + i * 20, text: 'note $i'),
      ];
      await _pump(
        tester,
        annotations: many,
        statuses: {
          for (final a in many) a.id: AnnotationStatus.resolved,
        },
      );

      var expanded = 0;
      for (var i = 0; i < many.length; i++) {
        if (find.text('note $i').evaluate().isNotEmpty) expanded++;
      }
      expect(expanded, kMaxExpandedBalloons);
    });
  });

  group('bands', () {
    testWidgets('a full-height band spans the canvas', (tester) async {
      final band = Annotation(
        id: 'band',
        shape: AnnotationShape.band,
        anchor: const RangeAnchor(startTime: 200, endTime: 400),
        authorName: 'M',
        createdAt: DateTime.utc(2026),
        text: '200 ticks',
      );
      await _pump(
        tester,
        annotations: [band],
        statuses: {'band': AnnotationStatus.unanchoredToRow},
      );
      expect(find.text('200 ticks'), findsOneWidget);
    });

    testWidgets('a band entirely off-screen is not drawn', (tester) async {
      final band = Annotation(
        id: 'band',
        shape: AnnotationShape.band,
        anchor: const RangeAnchor(startTime: 10, endTime: 40),
        authorName: 'M',
        createdAt: DateTime.utc(2026),
        text: 'early',
      );
      final container = await _pump(
        tester,
        annotations: [band],
        statuses: {'band': AnnotationStatus.unanchoredToRow},
      );
      expect(find.text('early'), findsOneWidget);

      container.read(timeMapperProvider.notifier).zoomToRange(600, 900);
      await tester.pump();
      expect(find.text('early'), findsNothing);
    });
  });

  group('drift is styled, not hidden', () {
    testWidgets('a drifted annotation still renders its text', (tester) async {
      await _pump(
        tester,
        annotations: [_callout()],
        statuses: {'a1': AnnotationStatus.drifted},
      );
      final text = tester.widget<Text>(find.text('look here'));
      expect(
        text.style?.fontStyle,
        FontStyle.italic,
        reason: 'drift is information, so the note stays legible and marked',
      );
    });
  });

  group('the "is writing a note" chip', () {
    // The whole of what replaces streaming keystrokes. It has to land at the
    // anchor: a chip floating anywhere else says "somebody, somewhere", which
    // is not worth interrupting a reader for.
    testWidgets('is drawn at its anchor, naming the author', (tester) async {
      await _pump(
        tester,
        annotations: [],
        chips: const [
          WritingChip(
            participantId: 'bob',
            name: 'Bob',
            colorIndex: 3,
            time: 500,
            rowId: 'top.data',
          ),
        ],
      );

      expect(find.textContaining('Bob'), findsOneWidget);
      final chip = tester.getTopLeft(
        find.byKey(const ValueKey('annotation-writing-bob')),
      );
      // 0–1000 ticks across 1000 px, so tick 500 is x=500, plus the 6 px
      // offset that keeps the chip off the anchor dot.
      expect(chip.dx, closeTo(506, 1));
    });

    testWidgets('draws nothing without an anchor', (tester) async {
      await _pump(
        tester,
        annotations: [],
        chips: const [
          WritingChip(
            participantId: 'bob',
            name: 'Bob',
            colorIndex: 3,
            time: null,
            rowId: null,
          ),
        ],
      );

      expect(find.textContaining('Bob'), findsNothing);
    });

    testWidgets('draws nothing for a row that is not displayed', (
      tester,
    ) async {
      await _pump(
        tester,
        annotations: [],
        chips: const [
          WritingChip(
            participantId: 'bob',
            name: 'Bob',
            colorIndex: 3,
            time: 500,
            rowId: 'top.nowhere',
          ),
        ],
      );

      expect(find.textContaining('Bob'), findsNothing);
    });

    testWidgets('draws nothing for a tick outside the viewport', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        annotations: [],
        chips: const [
          WritingChip(
            participantId: 'bob',
            name: 'Bob',
            colorIndex: 3,
            time: 900,
            rowId: 'top.data',
          ),
        ],
      );
      container.read(timeMapperProvider.notifier).zoomToRange(0, 400);
      await tester.pump();

      expect(find.textContaining('Bob'), findsNothing);
    });
  });
}
