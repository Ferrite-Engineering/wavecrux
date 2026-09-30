// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/domain/models/fsm_state.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_annotate_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

class _FakeFsmNotifier extends FsmNotifier {
  @override
  FsmViewState build() => const FsmViewState();

  @override
  Future<void> refresh() async {}
}

const _range = TimeRange(start: 0, end: 100);

const _model = FsmModel(
  signalRef: 'r',
  signalPath: 'top.fsm',
  timeRange: _range,
  states: [
    FsmState(id: '0', label: '0', entryCount: 1, firstEntryTime: 0),
    FsmState(id: '1', label: '1', entryCount: 1, firstEntryTime: 10),
  ],
  transitions: [],
  totalTransitionCount: 0,
);

Widget _wrap({
  required Widget child,
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    fsmProvider.overrideWith(_FakeFsmNotifier.new),
    ...overrides,
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  Widget opener(BuildContext context, String signalRef, FsmModel? model) {
    return ElevatedButton(
      onPressed: () => FsmAnnotateDialog.show(
        context,
        signalRef: signalRef,
        model: model,
      ),
      child: const Text('open'),
    );
  }

  testWidgets('dialog opens and renders with state rows', (tester) async {
    await tester.pumpWidget(
      _wrap(
        child: Builder(
          builder: (context) => opener(context, 'r', _model),
        ),
      ),
    );
    await openDialog(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    // Two state rows.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('locale sweep — zh_CN', (tester) async {
    await tester.pumpWidget(
      _wrap(
        locale: const Locale('zh', 'CN'),
        child: Builder(
          builder: (context) => opener(context, 'r', _model),
        ),
      ),
    );
    await openDialog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locale sweep — ja', (tester) async {
    await tester.pumpWidget(
      _wrap(
        locale: const Locale('ja'),
        child: Builder(
          builder: (context) => opener(context, 'r', _model),
        ),
      ),
    );
    await openDialog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locale sweep — ko', (tester) async {
    await tester.pumpWidget(
      _wrap(
        locale: const Locale('ko'),
        child: Builder(
          builder: (context) => opener(context, 'r', _model),
        ),
      ),
    );
    await openDialog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save persists labels through FsmAnnotationNotifier', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fsmProvider.overrideWith(_FakeFsmNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return opener(context, 'r', _model);
              },
            ),
          ),
        ),
      ),
    );
    await openDialog(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'IDLE');
    await tester.enterText(fields.at(1), 'RUN');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final ann = container.read(fsmAnnotationProvider)['r']!;
    expect(ann.stateLabels, {'0': 'IDLE', '1': 'RUN'});
  });

  testWidgets('pre-fills existing annotation', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fsmProvider.overrideWith(_FakeFsmNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return opener(context, 'r', _model);
              },
            ),
          ),
        ),
      ),
    );
    container
        .read(fsmAnnotationProvider.notifier)
        .setAnnotation(
          'r',
          const FsmAnnotation(
            signalRef: 'r',
            stateLabels: {'0': 'IDLE'},
          ),
        );
    await openDialog(tester);
    expect(find.text('IDLE'), findsOneWidget);
  });

  testWidgets('Cancel does not save', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fsmProvider.overrideWith(_FakeFsmNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return opener(context, 'r', _model);
              },
            ),
          ),
        ),
      ),
    );
    await openDialog(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'IDLE');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    // Dirty form → the unsaved-changes prompt appears; confirm discarding.
    await tester.tap(
      find.byKey(const ValueKey('editorDiscardConfirmDiscard')),
    );
    await tester.pumpAndSettle();
    expect(container.read(fsmAnnotationProvider)['r'], isNull);
    expect(find.byType(FsmAnnotateDialog), findsNothing);
  });

  testWidgets('dirty cancel prompts to discard; keep editing stays open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        child: Builder(
          builder: (context) => opener(context, 'r', _model),
        ),
      ),
    );
    await openDialog(tester);

    await tester.enterText(find.byType(TextField).first, 'IDLE');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    // "Keep editing" returns to the editor with input intact.
    await tester.tap(
      find.byKey(const ValueKey('editorDiscardConfirmKeepEditing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(FsmAnnotateDialog), findsOneWidget);
    expect(find.text('IDLE'), findsOneWidget);
  });

  testWidgets('clean cancel closes without a prompt', (tester) async {
    await tester.pumpWidget(
      _wrap(
        child: Builder(
          builder: (context) => opener(context, 'r', _model),
        ),
      ),
    );
    await openDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(FsmAnnotateDialog), findsNothing);
  });
}
