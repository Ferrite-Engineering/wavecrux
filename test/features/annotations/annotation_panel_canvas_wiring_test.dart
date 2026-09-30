// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The panel and the canvas, in one tree.
//
// **Why this file exists.** Every other annotation test mounts one or the
// other. But half the panel's actions are requests *to the canvas* — jump
// there, open that note's editor — and a request that is never received looks
// exactly like a button that does nothing. `annotationBeingEditedProvider` is
// the seam they meet at, and nothing pumped both sides of it until a user
// reported that "Edit text" did nothing.
//
// **This harness deliberately loads no waveform source**, which bounds what can
// be asserted here: `setAnchorTime` returns null without one, so anything about
// anchor *movement* would pass by doing nothing at all and must live in
// `annotation_shapes_test.dart`, which opens the real fixture.
//
// Measured, not assumed: giving this harness a real trace does not hang — it
// completes, takes about ten minutes per test, and fails all ten. (An earlier
// commit message, fa338ac2, called that a deadlock. It is not; the conclusion
// stands but the reason recorded there is wrong.) The cost is the widget
// binding driving FFI signal loads frame by frame, so the fix is not patience —
// it is keeping trace-backed assertions in a plain `flutter test`.

import 'package:flutter/gestures.dart'
    show kDoubleTapMinTime, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_overlay.dart';
import 'package:wavecrux/features/annotations/widgets/annotations_panel.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: 8,
);

Annotation _note({String id = 'a1', int time = 500}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: 'top.data'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 13),
  text: 'the note',
);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      annotationStatusesProvider.overrideWithValue(const {
        'a1': AnnotationStatus.resolved,
      }),
    ],
  );
  addTearDown(container.dispose);

  container
    ..listen(signalGroupsProvider, (_, _) {})
    ..listen(timeMapperProvider, (_, _) {})
    ..listen(annotationsProvider, (_, _) {})
    ..listen(annotationBeingEditedProvider, (_, _) {});

  container.read(signalGroupsProvider.notifier).addSignal(_v('data'));
  container
      .read(timeMapperProvider.notifier)
      .initialize(startTime: 0, endTime: 1000, viewportWidth: 800);
  container.read(annotationsProvider.notifier).add(_note());

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 800,
                height: 300,
                child: Stack(
                  children: [
                    Positioned.fill(child: AnnotationOverlay(scrollOffset: 0)),
                  ],
                ),
              ),
              SizedBox(width: 800, height: 260, child: AnnotationsPanel()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The inline editor specifically — scoped to the canvas, because the panel's
/// own filter box is a `TextField` too and an unscoped finder matches it.
final Finder _editor = find.descendant(
  of: find.byType(AnnotationOverlay),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('⋮ ▸ Edit text opens the note editor on the canvas', (
    tester,
  ) async {
    // The user-reported failure: the menu item ran, the provider was set, and
    // nothing appeared to happen.
    final container = await _pump(tester);
    expect(_editor, findsNothing);

    await tester.tap(find.byKey(const ValueKey('annotation-row-menu-a1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('annotation-row-action-edit-a1')),
    );
    await tester.pumpAndSettle();

    expect(container.read(annotationBeingEditedProvider), 'a1');
    expect(
      _editor,
      findsOneWidget,
      reason: 'the balloon must open its inline editor, not just record intent',
    );
  });

  testWidgets('the editor keeps focus after the menu route closes', (
    tester,
  ) async {
    // The specific trap: the inline editor commits on focus loss, and a route
    // popping restores focus to whatever had it before. If that restoration
    // lands after the editor requests focus, the editor commits and closes
    // itself in the same frame it opened — indistinguishable from "the button
    // did nothing".
    final container = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('annotation-row-menu-a1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('annotation-row-action-edit-a1')),
    );
    await tester.pumpAndSettle();

    // Several frames later it must still be open — the commit-on-blur path
    // fires a frame or two after the route settles.
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(annotationBeingEditedProvider), 'a1');
    expect(_editor, findsOneWidget);
  });

  testWidgets('double-tapping a row still opens the editor', (tester) async {
    // The pre-existing route to the same seam, kept working.
    final container = await _pump(tester);

    final row = find.byKey(const ValueKey('annotation-row-a1'));
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(container.read(annotationBeingEditedProvider), 'a1');
    expect(_editor, findsOneWidget);
  });

  testWidgets('committing text un-collapses the note', (tester) async {
    // The reported symptom: type into a note that was collapsed, press Enter,
    // and the text lands in the model and the panel while the canvas snaps
    // back to a numbered dot — which reads as the text having been discarded.
    final container = await _pump(tester);
    container.read(annotationsProvider.notifier)
      ..setText('a1', '')
      ..setCollapsed('a1', collapsed: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('annotation-row-menu-a1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('annotation-row-action-edit-a1')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editor, 'now it says something');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final note = container.read(annotationsProvider).single;
    expect(note.text, 'now it says something');
    expect(
      note.collapsed,
      isFalse,
      reason: 'somebody who just wrote words wants to see them',
    );
  });

  testWidgets('the balloon can be folded back from the canvas', (tester) async {
    // Tapping a dot has always expanded a note. Nothing folded one back, so
    // `collapsed: true` had exactly one writer in the app: the walkthrough.
    final container = await _pump(tester);
    expect(container.read(annotationsProvider).single.collapsed, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byType(AnnotationOverlay),
        matching: find.byIcon(Icons.unfold_less),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(annotationsProvider).single.collapsed, isTrue);
  });

  testWidgets('tapping a row marks it as the selected note', (tester) async {
    // The panel had no concept of selection at all, and row numbers are
    // positional — assigned over the full time-ordered set so a badge matches
    // the canvas dot. Move an anchor past its neighbours and every row
    // renumbers: the badge the user was following now belongs to a *different*
    // note, which in the shipped demo is the one that genuinely is not in the
    // file. Reported as "it moved to Not-in-this-file and the one I was
    // watching vanished"; nothing had moved groups and nothing had vanished.
    //
    // Marking the selected row is what makes that readable. `Set anchor time…`
    // selects the note it moved through this same provider, so the row it
    // landed on is findable however far the list reordered.
    final container = await _pump(tester);
    expect(container.read(annotationSelectedProvider), isNull);

    await tester.tap(find.byKey(const ValueKey('annotation-row-a1')));
    // The row carries onDoubleTap as well, so a single tap does not resolve
    // until that timeout expires — and a pending timer schedules no frames, so
    // `pumpAndSettle` alone returns before it fires.
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(container.read(annotationSelectedProvider), 'a1');
  });

  testWidgets('double-tapping a balloon opens its editor', (tester) async {
    // The canvas route to the same thing the panel's ⋮ ▸ Edit text does.
    // Double, not single: selection rides pointer-down and drives the ⌥-arrow
    // nudge, so one click opening the editor would swallow every subsequent
    // keystroke into a text field.
    final container = await _pump(tester);
    expect(_editor, findsNothing);

    await tester.tap(find.byKey(const ValueKey('annotation-balloon-text')));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.byKey(const ValueKey('annotation-balloon-text')));
    await tester.pumpAndSettle();

    expect(container.read(annotationBeingEditedProvider), 'a1');
    expect(_editor, findsOneWidget, reason: 'the editor must actually appear');
    expect(
      container.read(annotationSelectedProvider),
      'a1',
      reason: 'the note being edited is the one the keyboard acts on',
    );
  });

  testWidgets('a single tap selects without opening the editor', (
    tester,
  ) async {
    // The half that protects the nudge. If one tap opened the editor, ⌥-arrow
    // would move a text caret instead of the anchor and the nudge would be
    // unreachable without pressing Escape first.
    final container = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('annotation-balloon-text')));
    await tester.pumpAndSettle();

    expect(container.read(annotationSelectedProvider), 'a1');
    expect(container.read(annotationBeingEditedProvider), isNull);
    expect(_editor, findsNothing);
  });

  testWidgets('the fold button does not wait out the double-tap timeout', (
    tester,
  ) async {
    // The recognizer is scoped to the text, never to the whole balloon. Above
    // the collapse and delete buttons it would make each of their taps wait
    // out the double-tap timeout — the same ~300 ms lag an ancestor
    // `InkWell.onDoubleTap` once put on the panel's ⋮ menu.
    //
    // The assertion is the *absence* of a timed pump: `pumpAndSettle` alone
    // must be enough for the tap to have taken effect.
    final container = await _pump(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(AnnotationOverlay),
        matching: find.byIcon(Icons.unfold_less),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(annotationsProvider).single.collapsed, isTrue);
  });
}
