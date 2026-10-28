// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/inspector_openers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_state_names_section.dart';
import 'package:wavecrux/features/viewer/widgets/signal_format_section.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/inspector_test_host.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// The FSM on show, for `tb.state`, with states 0 to 2.
const _model = FsmModel(
  signalRef: 'tb.state',
  signalPath: 'tb.state',
  timeRange: TimeRange(start: 0, end: 100),
  states: [
    FsmState(id: '0', label: '0', entryCount: 1, firstEntryTime: 0),
    FsmState(id: '1', label: '1', entryCount: 1, firstEntryTime: 10),
    FsmState(id: '2', label: '2', entryCount: 1, firstEntryTime: 20),
  ],
  transitions: [],
  totalTransitionCount: 0,
);

/// Shows [_model] without a waveform; refresh is a no-op.
class _ShowingFsm extends FsmNotifier {
  @override
  FsmViewState build() =>
      const FsmViewState(signalRef: 'tb.state', model: _model);

  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;
}

/// Adds a 3-bit row for [path] and returns its id.
String _addRow(ProviderContainer container, String path) {
  container
      .read(signalGroupsProvider.notifier)
      .addSignal(inspectorTestVar(path, bitWidth: 3));
  return container.read(signalGroupsProvider).entries.last.id;
}

Future<ProviderContainer> _host(WidgetTester tester, {Locale? locale}) =>
    pumpInspectorHost(
      tester,
      locale: locale,
      overrides: [fsmProvider.overrideWith(_ShowingFsm.new)],
    );

Future<void> _inspect(
  WidgetTester tester,
  ProviderContainer container,
  String id,
) async {
  openWaveCruxInspector(
    tester.element(find.byType(Scaffold)),
    container,
    InspectedSignal(id),
  );
  await tester.pumpAndSettle();
}

Finder get _fields => find.descendant(
  of: find.byType(FsmStateNamesSection),
  matching: find.byType(TextField),
);

Finder get _apply => find.descendant(
  of: find.byType(FsmStateNamesSection),
  matching: find.descendant(
    of: find.byType(CruxInspectorApplyBar),
    matching: find.byType(FilledButton),
  ),
);

Finder get _revert => find.descendant(
  of: find.byType(FsmStateNamesSection),
  matching: find.descendant(
    of: find.byType(CruxInspectorApplyBar),
    matching: find.byType(TextButton),
  ),
);

void main() {
  for (final locale in _locales) {
    testWidgets('renders in ${locale.toLanguageTag()}', (tester) async {
      final container = await _host(tester, locale: locale);
      final id = _addRow(container, 'tb.state');
      await _inspect(tester, container, id);
      expect(tester.takeException(), isNull);
      expect(find.byType(FsmStateNamesSection), findsOneWidget);
      expect(_fields, findsNWidgets(3));
    });
  }

  testWidgets('a row whose signal has no known states shows no FSM section', (
    tester,
  ) async {
    final container = await _host(tester);
    final id = _addRow(container, 'tb.data');
    await _inspect(tester, container, id);
    expect(find.byType(SignalFormatSection), findsOneWidget);
    expect(find.byType(FsmStateNamesSection), findsNothing);
  });

  testWidgets('names apply together on Apply and refresh the FSM on show', (
    tester,
  ) async {
    final container = await _host(tester);
    final id = _addRow(container, 'tb.state');
    await _inspect(tester, container, id);
    final l10n = L10N.of(tester.element(find.byType(FsmStateNamesSection)));
    expect(find.text(l10n.inspectorFsmStateNamesSection), findsOneWidget);
    expect(find.text(l10n.fsmAnnotateStateLabel('2')), findsOneWidget);
    expect(tester.widget<FilledButton>(_apply).onPressed, isNull);

    await tester.enterText(_fields.at(0), 'IDLE');
    await tester.enterText(_fields.at(2), ' DONE ');
    await tester.pumpAndSettle();
    // Nothing written until Apply.
    expect(container.read(fsmAnnotationProvider), isEmpty);
    await tester.tap(_apply);
    await tester.pumpAndSettle();

    expect(container.read(fsmAnnotationProvider)['tb.state']?.stateLabels, {
      '0': 'IDLE',
      '2': 'DONE',
    });
    expect(container.read(fsmStateNameDraftsProvider), isEmpty);
    expect(
      (container.read(fsmProvider.notifier) as _ShowingFsm).refreshes,
      1,
    );
    expect(tester.widget<FilledButton>(_apply).onPressed, isNull);
  });

  testWidgets('shows the names in use; Revert puts them back', (tester) async {
    final container = await _host(tester);
    container
        .read(fsmAnnotationProvider.notifier)
        .setAnnotation(
          'tb.state',
          const FsmAnnotation(signalRef: 'tb.state', stateLabels: {'1': 'RUN'}),
        );
    final id = _addRow(container, 'tb.state');
    await _inspect(tester, container, id);
    expect(find.text('RUN'), findsOneWidget);

    await tester.enterText(_fields.at(1), 'GO');
    await tester.pumpAndSettle();
    expect(container.read(fsmStateNameDraftsProvider), contains('tb.state'));
    await tester.tap(_revert);
    await tester.pumpAndSettle();
    expect(find.text('RUN'), findsOneWidget);
    expect(find.text('GO'), findsNothing);
    expect(container.read(fsmStateNameDraftsProvider), isEmpty);
    expect(container.read(fsmAnnotationProvider)['tb.state']?.stateLabels, {
      '1': 'RUN',
    });
  });

  testWidgets('clearing every name removes the annotation', (tester) async {
    final container = await _host(tester);
    container
        .read(fsmAnnotationProvider.notifier)
        .setAnnotation(
          'tb.state',
          const FsmAnnotation(signalRef: 'tb.state', stateLabels: {'1': 'RUN'}),
        );
    final id = _addRow(container, 'tb.state');
    await _inspect(tester, container, id);
    await tester.enterText(_fields.at(1), '');
    await tester.pumpAndSettle();
    await tester.tap(_apply);
    await tester.pumpAndSettle();
    expect(container.read(fsmAnnotationProvider), isEmpty);
  });

  testWidgets('an unapplied name holds the row when another is chosen', (
    tester,
  ) async {
    final container = await _host(tester);
    final first = _addRow(container, 'tb.state');
    final second = _addRow(container, 'tb.data');
    await _inspect(tester, container, first);
    await tester.enterText(_fields.at(0), 'IDLE');
    await tester.pumpAndSettle();

    container
        .read(inspectedObjectProvider.notifier)
        .select(InspectedSignal(second));
    await tester.pumpAndSettle();
    final l10n = L10N.of(tester.element(find.byType(FsmStateNamesSection)));
    expect(find.text(l10n.inspectorHeldMessage('state')), findsOneWidget);
    expect(find.text('IDLE'), findsOneWidget);
  });

  testWidgets('Annotate FSM states on a signal whose FSM is not on show '
      'lists the states found, and keeps the FSM on show', (tester) async {
    final container = await _host(tester);
    final id = _addRow(container, 'tb.other');
    // No waveform is loaded, so the states come from the ids recorded for
    // the signal, as discovery would leave them.
    container.read(fsmKnownStateIdsProvider.notifier).put('tb.other', [
      '10',
      '2',
    ]);
    await annotateFsmStatesInInspector(
      tester.element(find.byType(Scaffold)),
      container,
      entryId: id,
      signalRef: 'tb.other',
    );
    await tester.pumpAndSettle();
    expect(container.read(inspectedObjectProvider), InspectedSignal(id));
    // With no waveform, discovery finds nothing and replaces the record.
    expect(container.read(fsmKnownStateIdsProvider)['tb.other'], isEmpty);
    expect(container.read(fsmProvider).signalRef, 'tb.state');
  });

  testWidgets('Annotate FSM states on the signal on show opens its states', (
    tester,
  ) async {
    final container = await _host(tester);
    final id = _addRow(container, 'tb.state');
    await annotateFsmStatesInInspector(
      tester.element(find.byType(Scaffold)),
      container,
      entryId: id,
      signalRef: 'tb.state',
    );
    await tester.pumpAndSettle();
    expect(container.read(inspectedObjectProvider), InspectedSignal(id));
    expect(_fields, findsNWidgets(3));
    expect(container.read(fsmKnownStateIdsProvider), isEmpty);
  });

  test('state ids sort numerically, merging every source', () {
    expect(
      fsmStateIdsOf(
        'tb.state',
        model: _model,
        named: const {
          'tb.state': FsmAnnotation(
            signalRef: 'tb.state',
            stateLabels: {'12': 'X'},
          ),
        },
        found: const {
          'tb.state': ['3'],
        },
      ),
      ['0', '1', '2', '3', '12'],
    );
    expect(
      fsmStateIdsOf(
        'tb.other',
        model: _model,
        named: const {},
        found: const {},
      ),
      isEmpty,
    );
  });
}
