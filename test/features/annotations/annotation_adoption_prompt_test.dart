// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The end-of-session adoption prompt.
//
// The assertion that matters most here is that **dismissing keeps everything**.
// Silently discarding destroys a meeting's output; silently keeping merely
// surprises somebody; so a closed prompt takes the branch that does not lose
// work irreversibly. It is a one-line behaviour that a well-meaning refactor
// would invert without noticing, which is why it has a test of its own.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_adoption_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_adoption_prompt.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Annotation _note({String id = 'n1', String author = 'Bob'}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 100, rowId: 'top.bus'),
  authorName: author,
  createdAt: DateTime.utc(2026, 8, 13),
  text: 'note $id',
);

PendingAdoption _mixed() => PendingAdoption(
  candidates: [
    AdoptableAnnotation(annotation: _note(), isMine: false, colorIndex: 2),
    AdoptableAnnotation(
      annotation: _note(id: 'n2', author: 'Me'),
      isMine: true,
      colorIndex: 0,
    ),
  ],
  participantCount: 3,
  endedAt: DateTime.utc(2026, 8, 13, 14, 30),
  sessionId: 'S1',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  PendingAdoption? pending,
}) async {
  final container = ProviderContainer()
    ..listen(annotationsProvider, (_, _) {})
    ..listen(annotationLayersProvider, (_, _) {});
  addTearDown(container.dispose);

  if (pending != null) {
    container.read(annotationAdoptionProvider.notifier).offer(pending);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: AnnotationAdoptionPrompt()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('draws nothing with no pending decision', (tester) async {
    await _pump(tester);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('names the count and the participants', (tester) async {
    await _pump(tester, pending: _mixed());
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
  });

  testWidgets('Keep all adopts everything as one layer', (tester) async {
    final container = await _pump(tester, pending: _mixed());
    await tester.tap(find.byKey(const ValueKey('annotation-adopt-keep-all')));
    await tester.pump();

    expect(container.read(annotationsProvider), hasLength(2));
    expect(container.read(annotationLayersProvider), hasLength(1));
    // The label is written into a document that travels, so it is not
    // localized — a group named in the author's locale is one nobody else can
    // search for.
    expect(
      container.read(annotationLayersProvider).single.label,
      contains('2026-08-13'),
    );
  });

  testWidgets('Keep only mine keeps just the local notes', (tester) async {
    final container = await _pump(tester, pending: _mixed());
    await tester.tap(find.byKey(const ValueKey('annotation-adopt-keep-mine')));
    await tester.pump();

    expect(container.read(annotationsProvider).map((a) => a.id), ['n2']);
  });

  testWidgets('Keep only mine is absent when every note is yours', (
    tester,
  ) async {
    // It would be Keep all pressed twice.
    await _pump(
      tester,
      pending: PendingAdoption(
        candidates: [
          AdoptableAnnotation(annotation: _note(), isMine: true, colorIndex: 0),
        ],
        participantCount: 1,
        endedAt: DateTime.utc(2026, 8, 13),
      ),
    );
    expect(
      find.byKey(const ValueKey('annotation-adopt-keep-mine')),
      findsNothing,
    );
  });

  testWidgets('Discard keeps nothing', (tester) async {
    final container = await _pump(tester, pending: _mixed());
    await tester.tap(find.byKey(const ValueKey('annotation-adopt-discard')));
    await tester.pump();

    expect(container.read(annotationsProvider), isEmpty);
    expect(container.read(annotationLayersProvider), isEmpty);
  });

  testWidgets('**dismissing the prompt keeps everything**', (tester) async {
    // The branch a closed prompt takes. Inverting this line would make
    // "discard" the outcome of every meeting somebody closed a strip on.
    final container = await _pump(tester, pending: _mixed());
    await tester.tap(find.byKey(const ValueKey('annotation-adopt-dismiss')));
    await tester.pump();

    expect(container.read(annotationsProvider), hasLength(2));
    expect(container.read(annotationLayersProvider), hasLength(1));
  });

  testWidgets('the prompt clears once answered', (tester) async {
    final container = await _pump(tester, pending: _mixed());
    await tester.tap(find.byKey(const ValueKey('annotation-adopt-keep-all')));
    await tester.pump();

    expect(container.read(annotationAdoptionProvider), isNull);
    expect(
      find.byKey(const ValueKey('annotation-adopt-keep-all')),
      findsNothing,
    );
  });

  testWidgets('"don\'t ask again" keeps, and can only ever keep', (
    tester,
  ) async {
    final container = await _pump(tester, pending: _mixed());
    await tester.tap(find.byKey(const ValueKey('annotation-adopt-dont-ask')));
    await tester.pump();

    expect(container.read(annotationsProvider), hasLength(2));
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingsProvider).value?.alwaysKeepSessionAnnotations,
      isTrue,
    );
  });

  testWidgets('with the preference set the prompt never appears', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.alwaysKeepSessionAnnotations': true,
    });
    final container = await _pump(tester, pending: _mixed());
    // Settings load asynchronously; the strip is drawn until they arrive and
    // then resolves itself on the next frame.
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('annotation-adopt-keep-all')),
      findsNothing,
    );
    expect(container.read(annotationsProvider), hasLength(2));
  });
}
