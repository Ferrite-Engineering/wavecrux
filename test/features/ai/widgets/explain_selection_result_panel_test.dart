// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/ai/providers/explain_selection_provider.dart';
import 'package:wavecrux/features/ai/widgets/explain_selection_result_panel.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/ai/explain_selection.dart';

import '../../../support/fake_waveform_source.dart';

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _FixedExplainNotifier extends ExplainSelection {
  _FixedExplainNotifier(this._initial);
  final ExplainSelectionState _initial;
  @override
  ExplainSelectionState build() => _initial;
}

/// A ready result with one resolvable citation (top.clk @ 10) and one that
/// cannot be located (top.ghost @ 9999).
ExplainSelectionState _readyState() => const ExplainSelectionState(
  phase: ExplainSelectionPhase.ready,
  rawText: 'x',
  segments: [
    ExplainText('Reset deasserts at '),
    ExplainCitation(
      raw: '[[cite:signal=top.clk,time=10]]',
      signal: 'top.clk',
      time: 10,
    ),
    ExplainText(' but the unknown net '),
    ExplainCitation(
      raw: '[[cite:signal=top.ghost,time=9999]]',
      signal: 'top.ghost',
      time: 9999,
    ),
    ExplainText(' is bogus.'),
  ],
);

ProviderContainer _container(ExplainSelectionState state) {
  final container = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(
        () => _FakeSourceNotifier(FakeWaveformSource.reference()),
      ),
      explainSelectionProvider.overrideWith(() => _FixedExplainNotifier(state)),
    ],
  );
  return container;
}

Widget _wrap(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: SizedBox(
          width: 700,
          height: 320,
          child: ExplainSelectionResultPanel(),
        ),
      ),
    ),
  );
}

void main() {
  final resolved = find.byKey(const Key('explainCitationResolved'));
  final unresolved = find.byKey(const Key('explainCitationUnresolved'));

  testWidgets('renders resolvable + unresolvable citations distinctly', (
    tester,
  ) async {
    final c = _container(_readyState());
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(resolved, findsOneWidget);
    expect(unresolved, findsOneWidget);
    expect(
      find.text(
        L10N.of(tester.element(resolved)).explainSelectionCouldNotLocate,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a resolved citation jumps the cursor + selects the signal', (
    tester,
  ) async {
    final c = _container(_readyState());
    addTearDown(c.dispose);
    // Keep the autoDispose cursor/selection providers alive for the duration of
    // the test (in the app, the canvas and signal tree listen to them).
    c
      ..listen(cursorStateProvider, (_, _) {})
      ..listen(selectedVariablesProvider, (_, _) {});
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    // Nothing jumped yet.
    expect(c.read(cursorStateProvider).primaryCursorTime, isNull);

    // The resolved citation is an InkWell; invoking its handler exercises the
    // grounding jump (WidgetSpan-hosted gesture is awkward to drive via tap).
    final inkWell = tester.widget<InkWell>(resolved);
    expect(inkWell.onTap, isNotNull);
    inkWell.onTap!();
    await tester.pump();

    // The citation grounds to top.clk @ 10 — the jump lands there exactly.
    // Selection is keyed by fullPath (row identity), not signalRef.
    expect(c.read(cursorStateProvider).primaryCursorTime, 10);
    expect(c.read(selectedVariablesProvider), contains('top.clk'));
  });

  testWidgets('an unresolved citation is inert — never a silent wrong jump', (
    tester,
  ) async {
    final c = _container(_readyState());
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    // The "could not locate" affordance is not an InkWell — there is no jump
    // handler at all, so it cannot land anywhere wrong.
    expect(
      find.descendant(of: unresolved, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(c.read(cursorStateProvider).primaryCursorTime, isNull);
  });

  testWidgets('renders NO close of its own — the dock tab owns closing', (
    tester,
  ) async {
    // The header × was removed in the panel-chrome dedup: the panel is a
    // bottom-dock tab, and the tab's × calls the same notifier.close() the
    // button used to. Two closes one centimetre apart were the duplicated
    // chrome the dock model exists to remove (bottom_dock_test covers the
    // tab-× path).
    final c = _container(_readyState());
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explainSelectionClose')), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('non-ready phases render a message without exceptions', (
    tester,
  ) async {
    for (final phase in [
      ExplainSelectionPhase.notConfigured,
      ExplainSelectionPhase.error,
      ExplainSelectionPhase.emptySelection,
    ]) {
      final c = _container(ExplainSelectionState(phase: phase));
      await tester.pumpWidget(_wrap(c));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$phase');
      c.dispose();
    }
  });

  testWidgets('the loading phase shows a spinner', (tester) async {
    final c = _container(
      const ExplainSelectionState(phase: ExplainSelectionPhase.loading),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Replace the infinite-spinner tree so no ticker is left pending at teardown.
    c.read(explainSelectionProvider.notifier).close();
    await tester.pumpAndSettle();
  });

  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('renders without exception in $locale', (tester) async {
      final c = _container(_readyState());
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrap(c, locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
