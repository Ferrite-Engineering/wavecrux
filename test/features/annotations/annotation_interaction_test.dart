// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart'
    show kCruxInfoSnackDuration;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_overlay.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

/// Annotations — the authoring affordances on the balloon.
///
/// The invariant these guard is the model's central one: dragging the label
/// must not move the anchor. It is easy to wire a drag straight into the
/// anchor and have everything still look plausible until someone pans.

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: 8,
);

Annotation _callout({
  String id = 'a1',
  String text = 'look here',
  bool collapsed = false,
}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 300, rowId: 'top.data'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12),
  text: text,
  // Explicit, and below the anchor: the default places the balloon above,
  // which for a note on the first lane clamps against the top edge and makes
  // hit-test coordinates in this harness ambiguous.
  labelDx: 20,
  labelDy: 60,
  collapsed: collapsed,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Annotation> annotations,
  String? editingId,
  Map<String, AnnotationStatus>? statusOverride,
}) async {
  final container = ProviderContainer(
    overrides: [
      annotationStatusesProvider.overrideWithValue(
        statusOverride ??
            {for (final a in annotations) a.id: AnnotationStatus.resolved},
      ),
    ],
  );
  addTearDown(container.dispose);

  container
    ..listen(signalGroupsProvider, (_, _) {})
    ..listen(timeMapperProvider, (_, _) {})
    ..listen(annotationsProvider, (_, _) {});
  // Deliberately NO listener on annotationBeingEdited/GestureActive: they are
  // keepAlive precisely because production has nothing watching them at the
  // moment they are written, and a harness listener would hide that.

  container.read(signalGroupsProvider.notifier).addSignal(_v('data'));
  container
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 1000, viewportWidth: 800);
  annotations.forEach(container.read(annotationsProvider.notifier).add);
  if (editingId != null) {
    container.read(annotationBeingEditedProvider.notifier).editing = editingId;
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: _Surface(),
      ),
    ),
  );
  return container;
}

/// The overlay under a fixed-size surface, hoisted out so it can be `const` —
/// the analyzer objects to a non-const widget tree it can prove is constant.
class _Surface extends StatelessWidget {
  const _Surface();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SizedBox(
      width: 800,
      height: 500,
      child: Stack(
        children: [Positioned.fill(child: AnnotationOverlay(scrollOffset: 0))],
      ),
    ),
  );
}

void main() {
  group('dragging the label', () {
    testWidgets('moves the label and provably not the anchor', (tester) async {
      final container = await _pump(tester, annotations: [_callout()]);
      final before = container.read(annotationsProvider).single;

      await tester.drag(find.text('look here'), const Offset(40, -20));
      await tester.pump();

      final after = container.read(annotationsProvider).single;
      expect(after.labelDx, before.labelDx + 40);
      expect(after.labelDy, before.labelDy - 20);
      expect(
        after.anchor,
        before.anchor,
        reason: 'wiring a drag into the anchor looks fine until someone pans',
      );
    });

    testWidgets('a whole drag is one undo step', (tester) async {
      final container = await _pump(tester, annotations: [_callout()]);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('look here')),
      );
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(container.read(annotationsProvider).single.labelDx, 20 + 40);

      container.read(annotationsProvider.notifier).undo();
      expect(
        container.read(annotationsProvider).single.labelDx,
        20,
        reason: 'one press of undo returns to before the drag, not one frame',
      );
    });
  });

  group('the canvas gesture handler stands down', () {
    testWidgets('a pointer down on a balloon claims the sequence', (
      tester,
    ) async {
      final container = await _pump(tester, annotations: [_callout()]);
      expect(container.read(annotationGestureActiveProvider), isFalse);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('look here')),
      );
      await tester.pump();
      expect(
        container.read(annotationGestureActiveProvider),
        isTrue,
        reason:
            'WaveformGestureHandler wraps this overlay and drives the '
            'cursor from a raw Listener, which sees every pointer event in '
            'its subtree — without the claim, dragging a note also drags the '
            'primary cursor',
      );

      await gesture.up();
      await tester.pump();
      expect(container.read(annotationGestureActiveProvider), isFalse);
    });

    testWidgets('the claim outlives the up event that ends the drag', (
      tester,
    ) async {
      // Models production: WaveformGestureHandler is an ANCESTOR Listener, so it
      // sees the same up event after the balloon's, in one synchronous dispatch.
      // If the claim were cleared synchronously that handler would read false
      // and place the cursor at the release point — the "cursor jumps to the
      // pointer when I let go" report.
      final container = ProviderContainer(
        overrides: [
          annotationStatusesProvider.overrideWithValue({
            'a1': AnnotationStatus.resolved,
          }),
        ],
      );
      addTearDown(container.dispose);
      container
        ..listen(signalGroupsProvider, (_, _) {})
        ..listen(timeMapperProvider, (_, _) {})
        ..listen(annotationsProvider, (_, _) {});
      container.read(signalGroupsProvider.notifier).addSignal(_v('data'));
      container
          .read(timeMapperProvider.notifier)
          .initialize(startTime: 0, endTime: 1000, viewportWidth: 800);
      container.read(annotationsProvider.notifier).add(_callout());

      bool? claimSeenByAncestor;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Listener(
                onPointerUp: (_) => claimSeenByAncestor = container.read(
                  annotationGestureActiveProvider,
                ),
                child: const SizedBox(
                  width: 800,
                  height: 500,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnnotationOverlay(scrollOffset: 0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.text('look here'), const Offset(30, 20));
      await tester.pump();

      expect(
        claimSeenByAncestor,
        isTrue,
        reason:
            'the ancestor must still see the claim held on the up event, '
            'or it processes the release as an ordinary canvas click',
      );
      expect(
        container.read(annotationGestureActiveProvider),
        isFalse,
        reason: 'and it must be released once the dispatch is over',
      );
    });

    testWidgets('a cancelled gesture releases the claim', (tester) async {
      final container = await _pump(tester, annotations: [_callout()]);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('look here')),
      );
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      expect(
        container.read(annotationGestureActiveProvider),
        isFalse,
        reason: 'a stuck claim would leave the canvas permanently inert',
      );
    });
  });

  group('repeated drags', _repeatedDragTests);

  group('collapsing', () {
    testWidgets('tapping a collapsed dot expands it', (tester) async {
      final container = await _pump(
        tester,
        annotations: [_callout(collapsed: true)],
      );
      expect(find.text('look here'), findsNothing);

      await tester.tap(find.text('1'));
      await tester.pump();

      expect(container.read(annotationsProvider).single.collapsed, isFalse);
    });
  });

  group('deleting', () {
    testWidgets('removes the annotation and offers an undo', (tester) async {
      final container = await _pump(tester, annotations: [_callout()]);

      await tester.tap(find.byIcon(Icons.close));
      // Let the snackbar finish animating in, or its action sits below the
      // viewport and the tap lands on nothing. `pumpAndSettle` rather than a
      // fixed pair of pumps: the snack is now raised from a post-frame callback
      // (see `showUndoSnack`), so counting frames to its entrance is counting
      // an implementation detail.
      await tester.pumpAndSettle();

      expect(container.read(annotationsProvider), isEmpty);
      expect(find.text('Annotation deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(container.read(annotationsProvider), hasLength(1));

      // Past the undo offer, so its timer is not left pending at teardown.
      await tester.pump(kCruxInfoSnackDuration);
      await tester.pumpAndSettle();
    });
  });

  group('the inline editor', () {
    testWidgets('opens focused on the annotation being edited', (tester) async {
      await _pump(
        tester,
        annotations: [_callout(text: '')],
        editingId: 'a1',
      );
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Describe what happens here'), findsOneWidget);
    });

    testWidgets('committing stores the text and closes the editor', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        annotations: [_callout(text: '')],
        editingId: 'a1',
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'stale by one cycle');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
        container.read(annotationsProvider).single.text,
        'stale by one cycle',
      );
      expect(container.read(annotationBeingEditedProvider), isNull);
    });

    testWidgets('Enter commits rather than inserting a newline', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        annotations: [_callout(text: '')],
        editingId: 'a1',
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'one line');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(
        container.read(annotationsProvider).single.text,
        'one line',
        reason:
            'a multi-line TextField never fires onSubmitted, so Enter has '
            'to be bound explicitly or it just inserts a line break',
      );
      expect(container.read(annotationBeingEditedProvider), isNull);
    });

    testWidgets('an empty note committed with no text is discarded', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        annotations: [_callout(text: '')],
        editingId: 'a1',
      );
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
        container.read(annotationsProvider),
        isEmpty,
        reason: 'an accidental authoring gesture must leave nothing behind',
      );
    });

    testWidgets('whitespace alone counts as empty', (tester) async {
      final container = await _pump(
        tester,
        annotations: [_callout(text: '')],
        editingId: 'a1',
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(container.read(annotationsProvider), isEmpty);
    });

    testWidgets('a note that already had text survives an empty edit', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        annotations: [_callout()],
        editingId: 'a1',
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
        container.read(annotationsProvider),
        isEmpty,
        reason:
            'clearing a callout to nothing removes it — the note no '
            'longer says anything',
      );
    });
  });
}

// ── regression: repeated drags ────────────────────────────────────────────────

void _repeatedDragTests() {
  testWidgets('a balloon can be dragged again after the first drag', (
    tester,
  ) async {
    final container = await _pump(tester, annotations: [_callout()]);

    await tester.drag(find.text('look here'), const Offset(60, 40));
    await tester.pump();
    final afterFirst = container.read(annotationsProvider).single;
    expect(afterFirst.labelDx, 20 + 60);

    await tester.drag(find.text('look here'), const Offset(30, 20));
    await tester.pump();
    final afterSecond = container.read(annotationsProvider).single;
    expect(
      afterSecond.labelDx,
      afterFirst.labelDx + 30,
      reason: 'a balloon dragged away from its anchor must stay grabbable',
    );
  });

  testWidgets('an earlier balloon stays grabbable under later ones', (
    tester,
  ) async {
    // Later annotations paint on top and, being full-size Stacks, cover the
    // whole canvas. If they absorb hits anywhere but on their own balloon,
    // every note but the last becomes ungrabbable — which is what a user sees
    // as "I could move it once, then not".
    final container = await _pump(
      tester,
      annotations: [
        _callout(),
        _callout(id: 'a2', text: 'second').copyWith(labelDy: 160),
        _callout(id: 'a3', text: 'third').copyWith(labelDy: 260),
      ],
    );

    await tester.drag(find.text('look here'), const Offset(35, 0));
    await tester.pump();

    final first = container
        .read(annotationsProvider)
        .firstWhere((a) => a.id == 'a1');
    expect(
      first.labelDx,
      20 + 35,
      reason: 'the first note is under two later full-canvas markers',
    );
  });

  testWidgets('a balloon under a full-height band is still grabbable', (
    tester,
  ) async {
    // Reproduces the reported shape: the demo ships a band spanning most of
    // the canvas, and the balloons that would not move all sat inside its
    // horizontal range.
    final band = Annotation(
      id: 'band',
      shape: AnnotationShape.band,
      anchor: const RangeAnchor(startTime: 100, endTime: 900),
      authorName: 'M',
      createdAt: DateTime.utc(2026),
      text: 'handshake window',
    );
    final container = await _pump(
      tester,
      annotations: [band, _callout()],
      statusOverride: {
        'band': AnnotationStatus.unanchoredToRow,
        'a1': AnnotationStatus.resolved,
      },
    );

    await tester.drag(find.text('look here'), const Offset(35, 0));
    await tester.pump();

    expect(
      container
          .read(annotationsProvider)
          .firstWhere((a) => a.id == 'a1')
          .labelDx,
      20 + 35,
      reason:
          'the band paints across the balloon; if it also absorbs the '
          'pointer, every note inside its span becomes immovable',
    );
  });

  testWidgets('the claim is released after a drag, not just a tap', (
    tester,
  ) async {
    final container = await _pump(tester, annotations: [_callout()]);

    await tester.drag(find.text('look here'), const Offset(120, 90));
    await tester.pump();

    expect(
      container.read(annotationGestureActiveProvider),
      isFalse,
      reason: 'a stuck claim leaves the canvas permanently inert',
    );
  });
}
