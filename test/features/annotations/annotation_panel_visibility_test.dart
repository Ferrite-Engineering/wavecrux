// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Annotations panel's presence rule, and the visibility toggle that
// shipped without a control.
//
// Two defects are pinned here, both found by using the app rather than by
// reading it:
//
// 1. **The panel's empty state was unreachable.** Presence was derived from
//    `annotations.isNotEmpty` alone, so the one place in the app that names the
//    Option-click authoring gesture rendered only for users who already knew
//    it. A discovery surface gated on having already discovered.
// 2. **`annotationsVisibleProvider` had no writer.** It was read by the canvas
//    overlay, the export dialog, the pack builder and the session codec, and
//    written only by session restore — so the export dialog honoured a setting
//    the user could not reach, and the verification guide instructed a step
//    with no button.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';

Annotation _note({String id = 'n1'}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 100, rowId: 'top.bus'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 13),
  text: 'note $id',
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer()
      ..listen(annotationsProvider, (_, _) {})
      ..listen(panelLayoutProvider, (_, _) {})
      ..listen(annotationsVisibleProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  PanelLayoutNotifier panels() => container.read(panelLayoutProvider.notifier);

  /// The rule the dock applies: explicit override, else "has annotations".
  bool panelShows() =>
      container.read(panelLayoutProvider).annotationsPanelVisible ??
      container.read(annotationsProvider).isNotEmpty;

  group('the panel presence rule', () {
    test('defaults to automatic — absent empty, present with a note', () {
      expect(
        container.read(panelLayoutProvider).annotationsPanelVisible,
        isNull,
      );
      expect(panelShows(), isFalse);

      container.read(annotationsProvider.notifier).add(_note());
      expect(panelShows(), isTrue);
    });

    test('opens with NO annotations, which is the point', () {
      // The empty state is where the authoring gesture is explained. If this
      // regresses to "only when annotations exist", the explanation becomes
      // unreachable again and nothing else in the app names the gesture.
      panels().toggleAnnotationsPanel(annotationsPresent: false);

      expect(container.read(annotationsProvider), isEmpty);
      expect(panelShows(), isTrue);
    });

    test('closing sticks even as notes are added', () {
      // The failure a single boolean would produce: close the panel, write a
      // note, and the panel reappears — undoing an explicit decision.
      container.read(annotationsProvider.notifier).add(_note());
      panels().setAnnotationsPanelVisible(visible: false);
      expect(panelShows(), isFalse);

      container.read(annotationsProvider.notifier).add(_note(id: 'n2'));
      expect(panelShows(), isFalse);
    });

    test('the toggle resolves "auto" against what is on screen now', () {
      container.read(annotationsProvider.notifier).add(_note());
      // Auto + notes = showing, so the first toggle must CLOSE rather than
      // set true and appear to do nothing.
      panels().toggleAnnotationsPanel(annotationsPresent: true);
      expect(panelShows(), isFalse);

      panels().toggleAnnotationsPanel(annotationsPresent: true);
      expect(panelShows(), isTrue);
    });

    test('null hands it back to the automatic rule', () {
      panels().setAnnotationsPanelVisible(visible: false);
      expect(panelShows(), isFalse);

      panels().setAnnotationsPanelVisible(visible: null);
      expect(
        container.read(panelLayoutProvider).annotationsPanelVisible,
        isNull,
      );
      expect(panelShows(), isFalse);

      container.read(annotationsProvider.notifier).add(_note());
      expect(panelShows(), isTrue);
    });
  });

  group('canvas visibility', () {
    test('toggles, and defaults to shown', () {
      expect(container.read(annotationsVisibleProvider), isTrue);

      container.read(annotationsVisibleProvider.notifier).toggle();
      expect(container.read(annotationsVisibleProvider), isFalse);

      container.read(annotationsVisibleProvider.notifier).toggle();
      expect(container.read(annotationsVisibleProvider), isTrue);
    });

    test('is independent of the panel', () {
      // Hiding your notes and hiding the list of them are different
      // intentions, and conflating them would make "let me read the raw trace
      // for a second" also lose the index of what you had written.
      container.read(annotationsProvider.notifier).add(_note());
      container.read(annotationsVisibleProvider.notifier).toggle();

      expect(container.read(annotationsVisibleProvider), isFalse);
      expect(panelShows(), isTrue);
    });
  });
}
