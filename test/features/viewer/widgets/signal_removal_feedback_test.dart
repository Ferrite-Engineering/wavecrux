// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart' show AnnouncementRecorder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/widgets/signal_removal_feedback.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

SignalGroup _three() => SignalGroup(
  entries: [
    for (final n in ['a', 'b', 'c'])
      SignalEntry.signal(id: 'id_$n', signalRef: 'ref_$n', displayName: n),
  ],
);

/// Pumps a button that runs [remove] against [container]'s list and reports
/// it through [showSignalRemovalUndo].
Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required SignalRemoval? Function(SignalGroupsNotifier n) remove,
  bool clearedCanvas = false,
  Locale? locale,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                final notifier = container.read(signalGroupsProvider.notifier);
                final removal = remove(notifier);
                if (removal == null) return;
                showSignalRemovalUndo(
                  context,
                  removal: removal,
                  notifier: notifier,
                  clearedCanvas: clearedCanvas,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late L10N l10n;
  setUpAll(() async => l10n = await L10N.delegate.load(const Locale('en')));

  testWidgets('a bulk removal shows a counted snackbar whose Undo restores '
      'the rows, and is announced', (tester) async {
    final recorder = AnnouncementRecorder.attach(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(signalGroupsProvider.notifier).restoreFromSession(_three());

    await _pump(
      tester,
      container,
      remove: (n) => n.removeSignalsWhere((e) => e.displayName != 'b'),
    );
    await tester.tap(find.text('go'));
    // The snack is raised from a post-frame callback and must finish its
    // entrance before its action is on screen to tap.
    await tester.pumpAndSettle();

    expect(find.text('Removed 2 signals'), findsOneWidget);
    expect(recorder.messages, ['Removed 2 signals']);
    expect(container.read(signalGroupsProvider).signalCount, 1);

    await tester.tap(find.text(l10n.signalRemovalUndo));
    await tester.pumpAndSettle();
    expect(container.read(signalGroupsProvider), _three());
  });

  testWidgets('a single removed signal reads in the singular', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(signalGroupsProvider.notifier).restoreFromSession(_three());

    await _pump(
      tester,
      container,
      remove: (n) => n.removeSignalsWhere((e) => e.displayName == 'a'),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Removed 1 signal'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('Clear Canvas says so, and the snackbar expires on its own', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(signalGroupsProvider.notifier).restoreFromSession(_three());

    await _pump(
      tester,
      container,
      remove: (n) => n.clearCanvas(),
      clearedCanvas: true,
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.canvasClearedToast), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text(l10n.canvasClearedToast), findsNothing);
    expect(container.read(signalGroupsProvider).entries, isEmpty);
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('locale sweep ${locale.toLanguageTag()} — no exceptions', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(signalGroupsProvider.notifier)
          .restoreFromSession(_three());
      await _pump(
        tester,
        container,
        remove: (n) => n.removeSignalsWhere((_) => true),
        locale: locale,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  }
}
