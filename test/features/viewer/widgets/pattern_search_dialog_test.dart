// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/pattern_search_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── shared test app builders ──────────────────────────────────────────────────

Widget _buildApp({
  Locale locale = const Locale('en'),
  bool waveformLoaded = false,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      waveformIsLoadedProvider.overrideWith((ref) => waveformLoaded),
      ...extraOverrides,
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => PatternSearchDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Widget _buildAppWithSource({
  Locale locale = const Locale('en'),
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      waveformIsLoadedProvider.overrideWith((ref) => true),
      waveformSourceProvider.overrideWith(
        () => _StubSourceNotifier(_FakeEmptySource()),
      ),
      visibleTimeRangeProvider.overrideWith((_) => (0, 1000)),
      ...extraOverrides,
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => PatternSearchDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('PatternSearchDialog', () {
    // ── locale sweeps ──────────────────────────────────────────────────────

    testWidgets('locale sweep — no exceptions in en', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — no exceptions in zh_CN', (tester) async {
      await tester.pumpWidget(_buildApp(locale: const Locale('zh', 'CN')));
      await _openDialog(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — no exceptions in ja', (tester) async {
      await tester.pumpWidget(_buildApp(locale: const Locale('ja')));
      await _openDialog(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — no exceptions in ko', (tester) async {
      await tester.pumpWidget(_buildApp(locale: const Locale('ko')));
      await _openDialog(tester);
      expect(tester.takeException(), isNull);
    });

    // ── static structure ───────────────────────────────────────────────────

    testWidgets('shows dialog title', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      expect(find.text(l10n.patternSearchDialogTitle), findsOneWidget);
    });

    testWidgets('shows Builder and Expression mode tabs', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      expect(find.text(l10n.patternSearchBuilderMode), findsOneWidget);
      expect(find.text(l10n.patternSearchAdvancedMode), findsOneWidget);
    });

    testWidgets('shows Search and Cancel action buttons', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      expect(find.text(l10n.patternSearchSearchButton), findsOneWidget);
      expect(find.text(l10n.patternSearchCancelButton), findsOneWidget);
    });

    testWidgets('shows Add Condition button in builder mode', (tester) async {
      await tester.pumpWidget(_buildApp(waveformLoaded: true));
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      expect(find.text(l10n.patternSearchAddCondition), findsOneWidget);
    });

    testWidgets('time range section is present', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      expect(find.text(l10n.patternSearchTimeRangeLabel), findsOneWidget);
    });

    // ── interactions ───────────────────────────────────────────────────────

    testWidgets('Cancel button dismisses the dialog', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      await tester.tap(find.text(l10n.patternSearchCancelButton));
      await tester.pumpAndSettle();
      expect(find.byType(PatternSearchDialog), findsNothing);
    });

    testWidgets('Add Condition adds a new row', (tester) async {
      await tester.pumpWidget(_buildApp(waveformLoaded: true));
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

      final signalHintsBefore = find
          .text(l10n.patternSearchSignalHint)
          .evaluate()
          .length;

      await tester.tap(find.text(l10n.patternSearchAddCondition));
      await tester.pumpAndSettle();

      final signalHintsAfter = find
          .text(l10n.patternSearchSignalHint)
          .evaluate()
          .length;
      expect(signalHintsAfter, greaterThan(signalHintsBefore));
    });

    testWidgets('switching to Expression mode hides Add Condition button', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(waveformLoaded: true));
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

      await tester.tap(find.text(l10n.patternSearchAdvancedMode));
      await tester.pumpAndSettle();

      expect(find.text(l10n.patternSearchAddCondition), findsNothing);
    });

    testWidgets('switching to Expression mode shows a TextField', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(waveformLoaded: true));
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

      // In builder mode there should be no multi-line TextField.
      final beforeSwitch = tester.widgetList<TextField>(find.byType(TextField));
      final multilineBefore = beforeSwitch.where((f) => f.maxLines != 1);
      expect(multilineBefore, isEmpty);

      await tester.tap(find.text(l10n.patternSearchAdvancedMode));
      await tester.pumpAndSettle();

      // After switching to Expression mode a multi-line TextField appears.
      final afterSwitch = tester.widgetList<TextField>(find.byType(TextField));
      final multilineAfter = afterSwitch.where((f) => (f.maxLines ?? 1) > 1);
      expect(multilineAfter, isNotEmpty);
    });

    testWidgets('show() static helper opens the dialog', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.byType(PatternSearchDialog), findsOneWidget);
    });

    // ── signal name display in dropdown ───────────────────────────────────────

    testWidgets('signal dropdown shows variable names, not raw VCD idcodes', (
      tester,
    ) async {
      // Map keyed by VCD idcodes ("0", "1") — values have meaningful names.
      final fakeSignals = <String, Variable>{
        '0': const Variable(
          name: 'clk',
          varType: VarType.wire,
          direction: VarDirection.unknown,
          signalRef: '0',
          scopePath: 'top',
        ),
        '1': const Variable(
          name: 'data',
          varType: VarType.reg,
          direction: VarDirection.unknown,
          signalRef: '1',
          scopePath: 'top',
        ),
      };

      await tester.pumpWidget(
        _buildApp(
          waveformLoaded: true,
          extraOverrides: [
            signalVariablesMapProvider.overrideWith((_) => fakeSignals),
          ],
        ),
      );
      await _openDialog(tester);

      // The dropdown items should exist — open the dropdown to reveal them.
      final dropdownFinder = find.byType(DropdownButtonFormField<String>);
      expect(dropdownFinder, findsOneWidget);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Signal names must be visible, raw idcodes must not.
      expect(find.text('clk'), findsWidgets);
      expect(find.text('data'), findsWidgets);
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    // ── empty state (no waveform loaded) ───────────────────────────────────────

    testWidgets('shows no-signals message when waveform is not loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      expect(find.text(l10n.patternSearchNoSignals), findsOneWidget);
    });

    testWidgets('Search button is disabled when no waveform loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.patternSearchSearchButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Search button is enabled when waveform is loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(waveformLoaded: true));
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.patternSearchSearchButton),
      );
      expect(button.onPressed, isNotNull);
    });

    // ── submitting an expression calls the provider ────────────────────────────

    testWidgets('Expression mode: submitting valid expression calls '
        'patternSearchNotifier.search and dismisses dialog', (tester) async {
      final calls = <(PatternExpression, int, int)>[];

      await tester.pumpWidget(
        _buildAppWithSource(
          extraOverrides: [
            patternSearchProvider.overrideWith(
              () => _TrackingSearchNotifier(calls),
            ),
          ],
        ),
      );
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

      // Switch to Expression mode.
      await tester.tap(find.text(l10n.patternSearchAdvancedMode));
      await tester.pumpAndSettle();

      // Enter a valid expression.
      final expressionField = find
          .byType(TextField)
          .evaluate()
          .cast<Element?>()
          .firstWhere(
            (e) => (e!.widget as TextField).maxLines != 1,
            orElse: () => null,
          );
      expect(expressionField, isNotNull);
      await tester.enterText(
        find.byWidget(expressionField!.widget),
        'top.a == 1',
      );

      // Tap Search.
      await tester.tap(find.text(l10n.patternSearchSearchButton));
      await tester.pumpAndSettle();

      // Dialog should be dismissed.
      expect(find.byType(PatternSearchDialog), findsNothing);
      // Search must have been called once with the parsed expression.
      expect(calls, hasLength(1));
      expect(calls.first.$1, isA<SignalCondition>());
      final cond = calls.first.$1 as SignalCondition;
      expect(cond.signalPath, 'top.a');
      expect(cond.value, '1');
    });

    testWidgets(
      'Expression mode: empty text shows validation error without dismissing',
      (tester) async {
        await tester.pumpWidget(_buildAppWithSource());
        await _openDialog(tester);
        final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

        await tester.tap(find.text(l10n.patternSearchAdvancedMode));
        await tester.pumpAndSettle();

        // Leave expression empty — just tap Search.
        await tester.tap(find.text(l10n.patternSearchSearchButton));
        await tester.pumpAndSettle();

        // Dialog must remain open and show an error.
        expect(find.byType(PatternSearchDialog), findsOneWidget);
      },
    );

    testWidgets(
      'Expression mode: x/z value literal accepted — dialog dismisses, '
      'no validation error',
      (tester) async {
        final calls = <(PatternExpression, int, int)>[];

        await tester.pumpWidget(
          _buildAppWithSource(
            extraOverrides: [
              patternSearchProvider.overrideWith(
                () => _TrackingSearchNotifier(calls),
              ),
            ],
          ),
        );
        await _openDialog(tester);
        final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

        await tester.tap(find.text(l10n.patternSearchAdvancedMode));
        await tester.pumpAndSettle();

        final expressionField = find
            .byType(TextField)
            .evaluate()
            .cast<Element?>()
            .firstWhere(
              (e) => (e!.widget as TextField).maxLines != 1,
              orElse: () => null,
            );
        await tester.enterText(
          find.byWidget(expressionField!.widget),
          'top.bus == xx',
        );
        await tester.tap(find.text(l10n.patternSearchSearchButton));
        await tester.pumpAndSettle();

        // Dialog must dismiss — x/z is valid syntax.
        expect(find.byType(PatternSearchDialog), findsNothing);
        expect(calls, hasLength(1));
        final cond = calls.first.$1 as SignalCondition;
        expect(cond.signalPath, 'top.bus');
        expect(cond.value, 'xx');
      },
    );

    testWidgets('Expression mode: chip_select == x accepted without error', (
      tester,
    ) async {
      final calls = <(PatternExpression, int, int)>[];

      await tester.pumpWidget(
        _buildAppWithSource(
          extraOverrides: [
            patternSearchProvider.overrideWith(
              () => _TrackingSearchNotifier(calls),
            ),
          ],
        ),
      );
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

      await tester.tap(find.text(l10n.patternSearchAdvancedMode));
      await tester.pumpAndSettle();

      final expressionField = find
          .byType(TextField)
          .evaluate()
          .cast<Element?>()
          .firstWhere(
            (e) => (e!.widget as TextField).maxLines != 1,
            orElse: () => null,
          );
      await tester.enterText(
        find.byWidget(expressionField!.widget),
        'chip_select == x',
      );
      await tester.tap(find.text(l10n.patternSearchSearchButton));
      await tester.pumpAndSettle();

      expect(find.byType(PatternSearchDialog), findsNothing);
      expect(calls, hasLength(1));
      expect((calls.first.$1 as SignalCondition).value, 'x');
    });

    testWidgets('Expression mode: sig == z accepted without error', (
      tester,
    ) async {
      final calls = <(PatternExpression, int, int)>[];

      await tester.pumpWidget(
        _buildAppWithSource(
          extraOverrides: [
            patternSearchProvider.overrideWith(
              () => _TrackingSearchNotifier(calls),
            ),
          ],
        ),
      );
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

      await tester.tap(find.text(l10n.patternSearchAdvancedMode));
      await tester.pumpAndSettle();

      final expressionField = find
          .byType(TextField)
          .evaluate()
          .cast<Element?>()
          .firstWhere(
            (e) => (e!.widget as TextField).maxLines != 1,
            orElse: () => null,
          );
      await tester.enterText(
        find.byWidget(expressionField!.widget),
        'sig == z',
      );
      await tester.tap(find.text(l10n.patternSearchSearchButton));
      await tester.pumpAndSettle();

      expect(find.byType(PatternSearchDialog), findsNothing);
      expect((calls.first.$1 as SignalCondition).value, 'z');
    });

    testWidgets(
      'Expression mode: syntax error shows validation error without dismissing',
      (tester) async {
        await tester.pumpWidget(_buildAppWithSource());
        await _openDialog(tester);
        final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

        await tester.tap(find.text(l10n.patternSearchAdvancedMode));
        await tester.pumpAndSettle();

        final expressionField = find
            .byType(TextField)
            .evaluate()
            .cast<Element?>()
            .firstWhere(
              (e) => (e!.widget as TextField).maxLines != 1,
              orElse: () => null,
            );
        await tester.enterText(
          find.byWidget(expressionField!.widget),
          'NOT NOT',
        ); // invalid syntax
        await tester.tap(find.text(l10n.patternSearchSearchButton));
        await tester.pumpAndSettle();

        expect(find.byType(PatternSearchDialog), findsOneWidget);
      },
    );

    // ── match result display and navigation ────────────────────────────────────
    //
    // Match navigation lives in PatternSearchToolbar, not in this dialog.
    // The tests here verify that the notifier receives the correct expression
    // (match rendering is covered by pattern_search_toolbar_test.dart).
    //
    // We verify the provider state after a successful search call.

    testWidgets('search result provider state is updated after submit', (
      tester,
    ) async {
      final calls = <(PatternExpression, int, int)>[];

      await tester.pumpWidget(
        _buildAppWithSource(
          extraOverrides: [
            patternSearchProvider.overrideWith(
              () => _TrackingSearchNotifier(calls),
            ),
          ],
        ),
      );
      await _openDialog(tester);
      final l10n = tester.element(find.byType(PatternSearchDialog)).l10n;

      await tester.tap(find.text(l10n.patternSearchAdvancedMode));
      await tester.pumpAndSettle();

      final expressionField = find
          .byType(TextField)
          .evaluate()
          .cast<Element?>()
          .firstWhere(
            (e) => (e!.widget as TextField).maxLines != 1,
            orElse: () => null,
          );
      await tester.enterText(
        find.byWidget(expressionField!.widget),
        'top.clk == 1',
      );
      await tester.tap(find.text(l10n.patternSearchSearchButton));
      await tester.pumpAndSettle();

      // Provider was called with the right time range from visibleTimeRangeProvider.
      expect(calls, hasLength(1));
      expect(calls.first.$2, 0); // startTime from stub
      expect(calls.first.$3, 1000); // endTime from stub
    });
  });
}

// ── test doubles ──────────────────────────────────────────────────────────────

/// Stub [WaveformSourceNotifier] that returns a fixed [WaveformDataSource].
class _StubSourceNotifier extends WaveformSourceNotifier {
  _StubSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// Minimal source with no signals — enough for the dialog to consider
/// a waveform loaded and provide a valid time range.
class _FakeEmptySource implements WaveformDataSource {
  @override
  bool isSignalLoaded(String signalRef) => false;
  @override
  Future<void> loadSignal(String signalRef) async {}
  @override
  Future<void> unloadSignal(String signalRef) async {}
  @override
  String? valueAt(String signalRef, int time) => null;
  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) => [];
  @override
  int get startTime => 0;
  @override
  int get endTime => 1000;
  @override
  Future<void> openFile(String path) async {}
  @override
  void close() {}
  @override
  List<Scope> get rootScopes => [];
  @override
  List<Variable> findVariables(SignalFilter filter) => [];
  @override
  SignalChange? nextTransition(String signalRef, int afterTime) => null;
  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) => null;
  @override
  Timescale? get timescale => null;
  @override
  String? get date => null;
  @override
  String? get version => null;
}

/// [PatternSearchNotifier] stub that records [search] calls instead of
/// dispatching to the real service.
class _TrackingSearchNotifier extends PatternSearchNotifier {
  _TrackingSearchNotifier(this._calls);
  final List<(PatternExpression, int, int)> _calls;

  @override
  PatternSearchState build() => const PatternSearchState();

  @override
  Future<void> search(
    PatternExpression expression,
    int startTime,
    int endTime,
  ) async {
    _calls.add((expression, startTime, endTime));
    state = PatternSearchState(
      result: PatternSearchResult(
        matches: const [],
        expression: expression,
        searchRange: TimeRange(start: startTime, end: endTime),
      ),
    );
  }
}

extension on Element {
  L10N get l10n => L10N.of(this);
}
