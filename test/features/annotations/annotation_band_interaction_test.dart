// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Annotation bands — the band's own affordances on the canvas.
//
// A band shipped in 5.9.1 as a read-only shaded region. These are the three
// things that make it editable in place: two edge handles, a live span readout
// while one is held, and a scope toggle between one lane and the whole canvas.
//
// The harness caveat from §22.28 applies here too and is why the assertions
// stay on state rather than on pixels: this tree has no `Listener` ancestor and
// no gesture arena, so a green run here is evidence the wiring is right, not
// that the handle is grabbable on a real canvas.

import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
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
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
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

Annotation _band({
  String id = 'b1',
  int start = 200,
  int end = 600,
  String? rowId,
  String text = '',
}) => Annotation(
  id: id,
  shape: AnnotationShape.band,
  anchor: RangeAnchor(startTime: start, endTime: end, rowId: rowId),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 13),
  text: text,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Annotation> annotations,
  Set<String> selectedSignals = const {},
  Locale? locale,
}) async {
  final container = ProviderContainer(
    overrides: [
      annotationStatusesProvider.overrideWithValue({
        for (final a in annotations) a.id: AnnotationStatus.resolved,
      }),
    ],
  );
  addTearDown(container.dispose);

  container
    ..listen(signalGroupsProvider, (_, _) {})
    ..listen(timeMapperProvider, (_, _) {})
    ..listen(annotationsProvider, (_, _) {})
    ..listen(selectedVariablesProvider, (_, _) {});

  container.read(signalGroupsProvider.notifier).addSignal(_v('data'));
  container
      .read(timeMapperProvider.notifier)
      // 1000 ticks across 800 px — 1.25 ticks per pixel, so a pixel of drag is
      // more than a tick and the rounding in the handler is exercised.
      .initialize(startTime: 0, endTime: 1000, viewportWidth: 800);
  annotations.forEach(container.read(annotationsProvider.notifier).add);
  if (selectedSignals.isNotEmpty) {
    container
        .read(selectedVariablesProvider.notifier)
        .applySelection(selectedSignals);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const _Surface(),
      ),
    ),
  );
  return container;
}

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

RangeAnchor _anchorOf(ProviderContainer c, String id) =>
    c.read(annotationsProvider).firstWhere((a) => a.id == id).anchor
        as RangeAnchor;

void main() {
  group('edge handles', () {
    testWidgets('dragging the left handle moves only the start', (
      tester,
    ) async {
      final container = await _pump(tester, annotations: [_band()]);

      // The left handle sits at the band's left edge; the right one at its
      // right. Both are inside the band's own Positioned box.
      final handles = find.byType(MouseRegion, skipOffstage: false);
      expect(handles, findsWidgets);

      final band = find.byKey(const ValueKey('annotation-band-b1'));
      final rect = tester.getRect(band);
      await tester.dragFrom(
        Offset(rect.left, rect.center.dy),
        const Offset(40, 0),
      );
      await tester.pump();

      final anchor = _anchorOf(container, 'b1');
      // 40 px at 1.25 ticks/px.
      expect(anchor.startTime, 250);
      expect(anchor.endTime, 600, reason: 'the far edge must not move');
    });

    testWidgets('dragging the right handle moves only the end', (tester) async {
      final container = await _pump(tester, annotations: [_band()]);

      final rect = tester.getRect(
        find.byKey(const ValueKey('annotation-band-b1')),
      );
      // Just inside the right edge: the band clips hit testing to its own
      // bounds, so `rect.right` itself is the exclusive boundary.
      await tester.dragFrom(
        Offset(rect.right - 2, rect.center.dy),
        const Offset(-40, 0),
      );
      await tester.pump();

      final anchor = _anchorOf(container, 'b1');
      expect(anchor.startTime, 200, reason: 'the far edge must not move');
      expect(anchor.endTime, 550);
    });

    testWidgets('a whole edge drag is one undo step', (tester) async {
      final container = await _pump(tester, annotations: [_band()]);

      final rect = tester.getRect(
        find.byKey(const ValueKey('annotation-band-b1')),
      );
      // Many small moves, as a real drag produces.
      final gesture = await tester.startGesture(
        Offset(rect.left, rect.center.dy),
      );
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(_anchorOf(container, 'b1').startTime, isNot(200));
      container.read(annotationsProvider.notifier).undo();
      expect(_anchorOf(container, 'b1').startTime, 200);
    });

    testWidgets('a many-move drag lands where the pointer did', (tester) async {
      // The assertion the "one undo step" test above is missing: it checks
      // that the start MOVED, not where it moved to, so an edge that flew off
      // under the pointer passed it.
      //
      // A real drag emits dozens of move events with a rebuild between each;
      // `tester.dragFrom` emits ONE, which is why the single-move tests cannot
      // see this. 48 px of travel at 1.25 ticks/px is 60 ticks, so the start
      // belongs at 260 — not at some multiple of it.
      final container = await _pump(tester, annotations: [_band()]);

      final rect = tester.getRect(
        find.byKey(const ValueKey('annotation-band-b1')),
      );
      final gesture = await tester.startGesture(
        Offset(rect.left, rect.center.dy),
      );
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(_anchorOf(container, 'b1').startTime, 260);
      expect(
        _anchorOf(container, 'b1').endTime,
        600,
        reason: 'the opposite edge never moves',
      );
    });

    testWidgets('holding an edge selects the band', (tester) async {
      final container = await _pump(tester, annotations: [_band()]);
      expect(container.read(annotationSelectedProvider), isNull);

      final rect = tester.getRect(
        find.byKey(const ValueKey('annotation-band-b1')),
      );
      await tester.dragFrom(
        Offset(rect.left, rect.center.dy),
        const Offset(10, 0),
      );
      await tester.pump();

      expect(container.read(annotationSelectedProvider), 'b1');
    });
  });

  group('the live span readout', () {
    testWidgets('appears only while an edge is held', (tester) async {
      await _pump(tester, annotations: [_band()]);

      // 400 ticks with no timescale on the fake source formats as ticks.
      expect(find.textContaining('400'), findsNothing);

      final rect = tester.getRect(
        find.byKey(const ValueKey('annotation-band-b1')),
      );
      final gesture = await tester.startGesture(
        Offset(rect.left, rect.center.dy),
      );
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump();

      // Live: the readout reflects the span as dragged, not as authored.
      expect(find.textContaining('ticks'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(find.textContaining('ticks'), findsNothing);
    });
  });

  group('the lane / full-height toggle', () {
    testWidgets('confines a full-height band to the one selected lane', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        annotations: [_band()],
        // The **fullPath**, which is what `selectedVariablesProvider` really
        // holds. This said `'ref_data'` — a signalRef — until 2026-08-13, and
        // because the widget compared against `signalRef` too, the test and
        // the code agreed with each other and both disagreed with the app. The
        // confine control never appeared for a real user.
        selectedSignals: {'top.data'},
      );
      expect(_anchorOf(container, 'b1').rowId, isNull);

      await tester.tap(find.byIcon(Icons.unfold_less));
      await tester.pump();

      expect(_anchorOf(container, 'b1').rowId, 'top.data');
      // The span is presentation-independent: re-scoping must not move it.
      expect(_anchorOf(container, 'b1').startTime, 200);
      expect(_anchorOf(container, 'b1').endTime, 600);
    });

    testWidgets('sends a lane band back to full height', (tester) async {
      final container = await _pump(
        tester,
        annotations: [_band(rowId: 'top.data')],
      );

      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pump();

      expect(_anchorOf(container, 'b1').rowId, isNull);
    });

    testWidgets('offers no confine control when no single lane is selected', (
      tester,
    ) async {
      // "Confine to the selected lane" has no answer with zero or several
      // selected, and picking one for the user would attach the band to a
      // signal they never named.
      await _pump(tester, annotations: [_band()]);

      expect(find.byIcon(Icons.unfold_less), findsNothing);
      expect(find.byIcon(Icons.unfold_more), findsNothing);
    });
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('the band and its controls render in $locale', (
        tester,
      ) async {
        await _pump(
          tester,
          annotations: [_band(text: 'burst window')],
          selectedSignals: {'top.data'},
          locale: locale,
        );

        expect(find.text('burst window'), findsOneWidget);
        expect(find.byIcon(Icons.unfold_less), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('a band as a thing you can read and edit', () {
    testWidgets('carries its panel number as a badge', (tester) async {
      // Two overlapping full-height bands were indistinguishable on the canvas
      // — no badge, and a label that may be empty — so a panel row could not
      // be matched to the region it describes.
      await _pump(
        tester,
        annotations: [
          _band(text: 'handshake window'),
          _band(id: 'b2', start: 300, end: 800, text: 'bus driven'),
        ],
      );

      final band = find.byKey(const ValueKey('annotation-band-b1'));
      expect(
        find.descendant(of: band, matching: find.text('1')),
        findsOneWidget,
      );
      final second = find.byKey(const ValueKey('annotation-band-b2'));
      expect(
        find.descendant(of: second, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('its text can actually be edited', (tester) async {
      // Bands never received `isEditing`, so a band's label had no editor at
      // all — including at creation, where the measured delta is pre-filled
      // precisely so the author can replace it with what it means.
      final container = await _pump(
        tester,
        annotations: [_band(text: '400 ns')],
      );
      container.read(annotationBeingEditedProvider.notifier).editing = 'b1';
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byKey(const ValueKey('annotation-band-b1')),
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget, reason: 'the band must offer an editor');

      await tester.enterText(field, 'handshake window');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        container.read(annotationsProvider).single.text,
        'handshake window',
      );
      expect(container.read(annotationBeingEditedProvider), isNull);
    });

    testWidgets('its label is drawn on a ground of its own', (tester) async {
      // The label used to be bare 10px text in the annotation colour, painted
      // straight onto the lanes — and a band's default colour is the theme
      // primary, the same hue a trace is commonly drawn in. On the shipped
      // demo the words were green-on-green and could not be read at all.
      //
      // Asserting the *decoration* rather than a colour value: what makes the
      // text legible is having an opaque ground, and pinning the exact surface
      // colour would break on every theme without saying anything about
      // readability.
      await _pump(tester, annotations: [_band(text: 'handshake window')]);

      final chip = find.descendant(
        of: find.byKey(const ValueKey('annotation-band-b1')),
        matching: find.byKey(const ValueKey('annotation-band-label-chip')),
      );
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('handshake window')),
        findsOneWidget,
        reason: 'the words must be inside the ground, not beside it',
      );

      final decoration = tester.widget<DecoratedBox>(chip).decoration;
      expect(
        (decoration as BoxDecoration).color?.a,
        greaterThan(0.5),
        reason:
            'a band label must sit on a near-opaque ground, or it is unreadable '
            'over a trace drawn in its own colour',
      );
    });

    testWidgets('double-tapping its label opens the editor', (tester) async {
      // Same gesture as the balloon and the panel's rows. The chip is the only
      // part of a band that answers a pointer: the shaded body stays inert so
      // pan, zoom and cursor placement still reach the canvas through a band
      // that may span the whole viewport.
      final container = await _pump(
        tester,
        annotations: [_band(text: 'handshake window')],
      );
      expect(container.read(annotationBeingEditedProvider), isNull);

      final chip = find.byKey(const ValueKey('annotation-band-label-chip'));
      await tester.tap(chip);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(container.read(annotationBeingEditedProvider), 'b1');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('annotation-band-b1')),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
        reason: 'the editor must actually appear, not just the provider flip',
      );
    });

    testWidgets('an untexted band draws no empty chip', (tester) async {
      // The ground has to be conditional. A band with no words yet — every band
      // between creation and the first commit — would otherwise render the
      // chrome of a label around nothing, which reads as a rendering fault.
      await _pump(tester, annotations: [_band()]);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('annotation-band-b1')),
          matching: find.byKey(const ValueKey('annotation-band-label-chip')),
        ),
        findsNothing,
        reason: 'no words, no ground to put them on',
      );
    });
  });
}
