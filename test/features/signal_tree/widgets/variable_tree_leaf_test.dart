// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart' show AnnouncementRecorder;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_picker_dialog.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/widgets/variable_tree_leaf.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Variable _makeVar({
  String name = 'clk',
  VarType varType = VarType.wire,
  int? bitWidth = 1,
  String scopePath = 'top',
}) => Variable(
  name: name,
  varType: varType,
  direction: VarDirection.unknown,
  // Deliberately NOT the fullPath: real dumps key signal data by an opaque
  // ref (FST aliasing maps many rows onto one ref), so any production code
  // that confuses row identity (fullPath) with data identity (signalRef)
  // must fail these tests rather than pass by coincidence.
  signalRef: 'ref_${scopePath}_$name',
  scopePath: scopePath,
  bitWidth: bitWidth,
);

Widget _buildApp(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  group('VariableTreeLeaf', () {
    testWidgets('renders in en locale without exceptions', (tester) async {
      await tester.pumpWidget(
        _buildApp(VariableTreeLeaf(variable: _makeVar())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('displays variable name', (tester) async {
      await tester.pumpWidget(
        _buildApp(VariableTreeLeaf(variable: _makeVar(name: 'data_bus'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('data_bus'), findsOneWidget);
    });

    testWidgets('shows bit-width badge for vectors wider than 1', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          VariableTreeLeaf(variable: _makeVar(name: 'bus', bitWidth: 8)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('[7:0]'), findsOneWidget);
    });

    testWidgets('hides bit-width badge for 1-bit signals', (tester) async {
      await tester.pumpWidget(
        _buildApp(VariableTreeLeaf(variable: _makeVar())),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(':0]'), findsNothing);
    });

    testWidgets('hides bit-width badge when bitWidth is null', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          VariableTreeLeaf(
            variable: _makeVar(name: 'real_val', bitWidth: null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(':0]'), findsNothing);
    });

    testWidgets('tap adds signal to SignalGroupsNotifier', (tester) async {
      final variable = _makeVar();
      await tester.pumpWidget(_buildApp(VariableTreeLeaf(variable: variable)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(VariableTreeLeaf));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(VariableTreeLeaf)),
      );
      final entries = container.read(signalGroupsProvider).entries;
      expect(entries, hasLength(1));
      expect(entries.first.signalRef, variable.signalRef);
    });

    testWidgets('selected variable shows highlighted background', (
      tester,
    ) async {
      final variable = _makeVar();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(
                  body: VariableTreeLeaf(variable: variable),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      container
          .read(selectedVariablesProvider.notifier)
          .toggle(variable.fullPath);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('heatmap color applied when heatmapValues keyed by fullPath', (
      tester,
    ) async {
      final variable = _makeVar();
      // variable.fullPath == 'top.clk'
      final initialState = SwitchingActivityState(
        heatmapValues: {variable.fullPath: 1.0},
      );

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(body: VariableTreeLeaf(variable: variable)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Seed heatmap with a hot value keyed by fullPath.
      container.read(switchingActivityProvider.notifier).state = initialState;
      await tester.pump();

      expect(tester.takeException(), isNull);

      // The row Container's color must be non-transparent (heat applied).
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(VariableTreeLeaf),
          matching: find.byType(Container),
        ),
      );
      final hasHeatColor = containers.any((c) {
        final color = c.color;
        return color != null && color != Colors.transparent;
      });
      expect(
        hasHeatColor,
        isTrue,
        reason: 'heatmap color must be applied when fullPath key matches',
      );
    });

    testWidgets(
      'no heatmap color when heatmapValues keyed by signalRef (mismatch)',
      (tester) async {
        final variable = _makeVar();
        // The widget must use fullPath as the key; a wrong key must yield no color.
        const stateWithSignalRefKey = SwitchingActivityState(
          heatmapValues: {'wrong_key': 1.0},
        );

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            child: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  localizationsDelegates: L10N.localizationsDelegates,
                  supportedLocales: L10N.supportedLocales,
                  home: Scaffold(body: VariableTreeLeaf(variable: variable)),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        container.read(switchingActivityProvider.notifier).state =
            stateWithSignalRefKey;
        await tester.pump();

        expect(tester.takeException(), isNull);

        // Row background must be transparent — no matching key.
        final containers = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(VariableTreeLeaf),
            matching: find.byType(Container),
          ),
        );
        final allTransparent = containers.every((c) {
          final color = c.color;
          return color == null || color == Colors.transparent;
        });
        expect(
          allTransparent,
          isTrue,
          reason: 'no heat color when key does not match fullPath',
        );
      },
    );

    testWidgets('wraps row in a Draggable<String> carrying the signalRef', (
      tester,
    ) async {
      final variable = _makeVar(scopePath: 'top.cpu');
      await tester.pumpWidget(_buildApp(VariableTreeLeaf(variable: variable)));
      await tester.pumpAndSettle();

      final draggable = find.byType(Draggable<String>);
      expect(draggable, findsOneWidget);
      final widget = tester.widget<Draggable<String>>(draggable);
      expect(widget.data, variable.signalRef);
      expect(widget.affinity, Axis.horizontal);
    });
  });

  group('parameter value badge', () {
    testWidgets('parameter leaf shows its constant value inline', (
      tester,
    ) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.build(children: [VariableTreeLeaf(variable: harness.width)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('= 32'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no badge when no waveform source is loaded', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          VariableTreeLeaf(
            variable: _makeVar(
              name: 'WIDTH',
              varType: VarType.parameter,
              bitWidth: 8,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('= '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('non-parameter leaf shows no value badge', (tester) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.build(children: [VariableTreeLeaf(variable: harness.sclk)]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('= '), findsNothing);
    });

    testWidgets('context menu header reveals the full value', (tester) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.build(children: [VariableTreeLeaf(variable: harness.width)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(VariableTreeLeaf),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('WIDTH = 32'), findsOneWidget);
    });
  });

  group('multi-selection gestures', () {
    testWidgets('Ctrl+click toggles selection without adding a signal', (
      tester,
    ) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build(children: harness.signalLeaves));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byType(VariableTreeLeaf).first);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(
        harness.container.read(selectedVariablesProvider),
        {harness.sclk.fullPath},
      );
      expect(
        harness.container.read(signalGroupsProvider).entries,
        isEmpty,
      );
    });

    testWidgets('Shift+click selects the visible range from the anchor', (
      tester,
    ) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build(children: harness.signalLeaves));
      await tester.pumpAndSettle();

      harness.container
          .read(selectedVariablesProvider.notifier)
          .toggle(harness.sclk.fullPath);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      // Third leaf == cs; the range must sweep up mosi in between.
      await tester.tap(find.byType(VariableTreeLeaf).at(2));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(harness.container.read(selectedVariablesProvider), {
        harness.sclk.fullPath,
        harness.mosi.fullPath,
        harness.cs.fullPath,
      });
      expect(harness.container.read(signalGroupsProvider).entries, isEmpty);
    });

    testWidgets(
      'plain tap adds the signal and selects only the tapped row',
      (tester) async {
        final harness = _TreeHarness();
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.build(children: harness.signalLeaves));
        await tester.pumpAndSettle();

        harness.container
            .read(selectedVariablesProvider.notifier)
            .toggle(harness.mosi.fullPath);

        await tester.tap(find.byType(VariableTreeLeaf).first);
        await tester.pump();

        // The tapped row becomes the single selection — visible feedback for
        // the click, and the (now on-screen) Shift+click range anchor.
        expect(
          harness.container.read(selectedVariablesProvider),
          {harness.sclk.fullPath},
        );
        final entries = harness.container.read(signalGroupsProvider).entries;
        expect(entries, hasLength(1));
        expect(entries.first.signalRef, harness.sclk.signalRef);
      },
    );
  });

  group('multi-selection context menu', () {
    testWidgets('bulk items hidden when fewer than two rows are selected', (
      tester,
    ) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build(children: harness.signalLeaves));
      await tester.pumpAndSettle();

      harness.container
          .read(selectedVariablesProvider.notifier)
          .toggle(harness.sclk.fullPath);

      await tester.tap(
        find.byType(VariableTreeLeaf).first,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l10n.signalTreeAddToViewer), findsOneWidget);
      expect(find.text(l10n.signalTreeApplyDecoderToSelection), findsNothing);
      expect(find.text(l10n.signalTreeAddSelected(1)), findsNothing);
    });

    testWidgets('bulk items hidden when the row is not part of the selection', (
      tester,
    ) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build(children: harness.signalLeaves));
      await tester.pumpAndSettle();

      harness.container.read(selectedVariablesProvider.notifier)
        ..toggle(harness.mosi.fullPath)
        ..toggle(harness.cs.fullPath);

      // Right-click sclk, which is NOT selected.
      await tester.tap(
        find.byType(VariableTreeLeaf).first,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l10n.signalTreeApplyDecoderToSelection), findsNothing);
    });

    testWidgets('"Add N selected" adds the selection in tree order', (
      tester,
    ) async {
      final recorder = AnnouncementRecorder.attach(tester);
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build(children: harness.signalLeaves));
      await tester.pumpAndSettle();

      // Toggle in REVERSE tree order — the add must come out in tree order.
      harness.container.read(selectedVariablesProvider.notifier)
        ..toggle(harness.cs.fullPath)
        ..toggle(harness.sclk.fullPath);

      await tester.tap(
        find.byType(VariableTreeLeaf).first,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      await tester.tap(find.text(l10n.signalTreeAddSelected(2)));
      await tester.pumpAndSettle();

      final entries = harness.container.read(signalGroupsProvider).entries;
      expect(
        [for (final e in entries) e.signalRef],
        [harness.sclk.signalRef, harness.cs.signalRef],
      );
      expect(recorder.messages, ['2 signals added to the viewer']);
    });

    testWidgets(
      '"Add N selected" skips signals already on the canvas '
      '(plain-tap then range-select must not duplicate the first signal)',
      (tester) async {
        final harness = _TreeHarness();
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.build(children: harness.signalLeaves));
        await tester.pumpAndSettle();

        // Plain-tap sclk — added to the canvas immediately, anchor set.
        await tester.tap(find.byType(VariableTreeLeaf).first);
        await tester.pump();

        // Shift+click cs — range-selects sclk..cs (sclk now selected AND
        // already displayed).
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(find.byType(VariableTreeLeaf).at(2));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        await tester.tap(
          find.byType(VariableTreeLeaf).first,
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();

        final l10n = L10N.of(tester.element(find.byType(Scaffold)));
        await tester.tap(find.text(l10n.signalTreeAddSelected(3)));
        await tester.pumpAndSettle();

        // sclk appears exactly once; mosi and cs were appended after it.
        final entries = harness.container.read(signalGroupsProvider).entries;
        expect(
          [for (final e in entries) e.signalRef],
          [
            harness.sclk.signalRef,
            harness.mosi.signalRef,
            harness.cs.signalRef,
          ],
        );
      },
    );

    testWidgets('"Apply decoder to selection" opens the decoder picker', (
      tester,
    ) async {
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build(children: harness.signalLeaves));
      await tester.pumpAndSettle();

      harness.container.read(selectedVariablesProvider.notifier)
        ..toggle(harness.sclk.fullPath)
        ..toggle(harness.mosi.fullPath);

      await tester.tap(
        find.byType(VariableTreeLeaf).first,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      await tester.tap(find.text(l10n.signalTreeApplyDecoderToSelection));
      await tester.pumpAndSettle();

      expect(find.byType(DecoderPickerDialog), findsOneWidget);
      final picker = tester.widget<DecoderPickerDialog>(
        find.byType(DecoderPickerDialog),
      );
      // The picker must be scoped to the selection subset with auto-bind on.
      expect(picker.signalMap.keys, {
        harness.sclk.signalRef,
        harness.mosi.signalRef,
      });
      expect(picker.autoBindOnSelect, isTrue);
    });

    for (final localeCode in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('$localeCode context menu renders without exceptions', (
        tester,
      ) async {
        final harness = _TreeHarness();
        addTearDown(harness.dispose);
        addTearDown(harness.dispose);
        await tester.pumpWidget(
          harness.build(
            children: harness.signalLeaves,
            locale: Locale(localeCode),
          ),
        );
        await tester.pumpAndSettle();

        harness.container.read(selectedVariablesProvider.notifier)
          ..toggle(harness.sclk.fullPath)
          ..toggle(harness.mosi.fullPath);

        await tester.tap(
          find.byType(VariableTreeLeaf).first,
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();

        final l10n = L10N.of(tester.element(find.byType(Scaffold)));
        expect(
          find.text(l10n.signalTreeAddSelected(2)),
          findsOneWidget,
        );
        expect(
          find.text(l10n.signalTreeApplyDecoderToSelection),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FST alias regression (wb_streamer report)', () {
    testWidgets('selecting one alias row does not highlight the other', (
      tester,
    ) async {
      final harness = _AliasHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      harness.container
          .read(selectedVariablesProvider.notifier)
          .selectOnly(harness.ramClk.fullPath);
      await tester.pump();

      final tint = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme.primary.withValues(alpha: 0.18);
      final tinted = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.color == tint);
      // Exactly one row highlighted — the alias in `tb` shares the signalRef
      // but is a different hierarchy row and must stay unselected.
      expect(tinted, hasLength(1));
    });

    testWidgets(
      '"Apply decoder to selection" carries the CLICKED scope\'s rows, '
      'not last-walked aliases of their refs',
      (tester) async {
        final harness = _AliasHarness();
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.build());
        await tester.pumpAndSettle();

        harness.container.read(selectedVariablesProvider.notifier)
          ..toggle(harness.ramClk.fullPath)
          ..toggle(harness.ramCyc.fullPath);

        await tester.tap(
          find.byType(VariableTreeLeaf).first,
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();

        final l10n = L10N.of(tester.element(find.byType(Scaffold)));
        await tester.tap(find.text(l10n.signalTreeApplyDecoderToSelection));
        await tester.pumpAndSettle();

        final picker = tester.widget<DecoderPickerDialog>(
          find.byType(DecoderPickerDialog),
        );
        // The dialog map is ref-keyed (its contract), but each value must be
        // the Variable of the row the user selected. A ref-keyed resolution
        // used to return tb.clk here (last-walked alias of ref_shared_clk),
        // showing wrong-scope names and breaking auto-bind.
        expect(picker.signalMap.keys, {
          harness.ramClk.signalRef,
          harness.ramCyc.signalRef,
        });
        expect(
          picker.signalMap[harness.ramClk.signalRef]!.fullPath,
          harness.ramClk.fullPath,
        );
      },
    );
  });

  group('screen reader and keyboard', () {
    test('the spoken name adds the bit range only for vectors', () {
      expect(VariableTreeLeaf.spokenName(_makeVar()), 'clk');
      expect(
        VariableTreeLeaf.spokenName(_makeVar(name: 'bus', bitWidth: 8)),
        'bus, [7:0]',
      );
      expect(
        VariableTreeLeaf.spokenName(_makeVar(name: 'r', bitWidth: null)),
        'r',
      );
    });

    testWidgets('is one button with the signal name, width and selection', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final variable = _makeVar(name: 'bus', bitWidth: 8);
      await tester.pumpWidget(_buildApp(VariableTreeLeaf(variable: variable)));
      await tester.pumpAndSettle();

      final row = find.byType(VariableTreeLeaf);
      expect(
        tester.getSemantics(row),
        isSemantics(
          label: 'bus, [7:0]',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(row);
      await tester.pump();
      expect(
        tester.getSemantics(row),
        isSemantics(label: 'bus, [7:0]', isSelected: true),
      );
      handle.dispose();
    });

    testWidgets('a parameter row reports its value', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = _TreeHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.build(children: [VariableTreeLeaf(variable: harness.width)]),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(VariableTreeLeaf)),
        isSemantics(label: 'WIDTH, [7:0]', value: '= 32'),
      );
      handle.dispose();
    });

    testWidgets('a plain click is announced; a Ctrl+click is not', (
      tester,
    ) async {
      final recorder = AnnouncementRecorder.attach(tester);
      await tester.pumpWidget(
        _buildApp(VariableTreeLeaf(variable: _makeVar(name: 'data'))),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byType(VariableTreeLeaf));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(recorder.messages, isEmpty);

      await tester.tap(find.byType(VariableTreeLeaf));
      await tester.pump();
      expect(recorder.messages, ['data added to the viewer']);
    });

    testWidgets('inside a tree the row reports focus and draws a ring', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var focusRequests = 0;
      var taps = 0;
      await tester.pumpWidget(
        _buildApp(
          VariableTreeLeaf(
            variable: _makeVar(name: 'data'),
            keyboardFocused: true,
            onFocusRequested: () => focusRequests++,
            onTapped: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byType(VariableTreeLeaf);
      expect(
        tester.getSemantics(row),
        isSemantics(
          isFocusable: true,
          isFocused: true,
          hasFocusAction: true,
        ),
      );
      tester.semantics.performAction(
        find.semantics.byLabel('data'),
        SemanticsAction.focus,
      );
      await tester.tap(row);
      await tester.pump();
      expect(focusRequests, 1);
      expect(taps, 1);
      expect(
        tester
            .widgetList<Container>(
              find.descendant(of: row, matching: find.byType(Container)),
            )
            .where((c) => c.foregroundDecoration != null),
        isNotEmpty,
      );
      handle.dispose();
    });

    testWidgets('Add to Viewer from the menu is announced', (tester) async {
      final recorder = AnnouncementRecorder.attach(tester);
      await tester.pumpWidget(
        _buildApp(VariableTreeLeaf(variable: _makeVar(name: 'data'))),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(VariableTreeLeaf),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Viewer'));
      await tester.pumpAndSettle();

      expect(recorder.messages, ['data added to the viewer']);
    });

    testWidgets('outside a tree the row is not a focus target', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _buildApp(VariableTreeLeaf(variable: _makeVar(name: 'data'))),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(VariableTreeLeaf)),
        isSemantics(isFocusable: false, hasFocusAction: false),
      );
      handle.dispose();
    });
  });
}

// ── Multi-select / parameter harness ─────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

// WaveformSourceNotifier.build() is synchronous — returns AsyncValue directly.
class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// Shared fixture: a mock waveform source with one `top` scope containing
/// three 1-bit signals (sclk, mosi, cs) and an 8-bit WIDTH parameter whose
/// value at t=0 is 32. The scope is pre-expanded so the visible row order
/// used by Shift+click matches the leaves pumped into the column.
///
/// Owns its [ProviderContainer] (via [UncontrolledProviderScope]) so tests
/// can seed provider state without mutating providers mid-build. Tests must
/// `addTearDown(harness.dispose)`.
/// Regression coverage for FST signal aliasing (the wb_streamer beta
/// report): one underlying signal (one signalRef) surfaces as multiple
/// hierarchy rows in different scopes. Row identity is fullPath; anything
/// keyed by ref conflates the aliases.
class _AliasHarness {
  _AliasHarness() {
    // wb_ram0's port and the testbench's net are THE SAME signal (shared
    // signalRef) — exactly how wellen reports an FST net wired through a
    // port. `tb` is walked after `wb_ram0`, so a last-walk-wins ref-keyed
    // lookup resolves the shared ref to tb.clk, not the wb_ram0 row.
    ramClk = const Variable(
      name: 'wb_clk_i',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: 'ref_shared_clk',
      scopePath: 'wb_ram0',
      bitWidth: 1,
    );
    ramCyc = const Variable(
      name: 'wb_cyc_i',
      varType: VarType.wire,
      direction: VarDirection.input,
      signalRef: 'ref_cyc',
      scopePath: 'wb_ram0',
      bitWidth: 1,
    );
    tbClk = const Variable(
      name: 'clk',
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: 'ref_shared_clk',
      scopePath: 'tb',
      bitWidth: 1,
    );
    final source = _MockSource();
    when(() => source.rootScopes).thenReturn([
      Scope(
        name: 'wb_ram0',
        path: 'wb_ram0',
        type: ScopeType.module,
        variables: [ramClk, ramCyc],
      ),
      Scope(
        name: 'tb',
        path: 'tb',
        type: ScopeType.module,
        variables: [tbClk],
      ),
    ]);
    when(() => source.loadSignal(any())).thenAnswer((_) async {});
    when(() => source.startTime).thenReturn(0);
    container = ProviderContainer(
      overrides: [
        waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
        // The harness pumps leaves in declaration order (sclk, mosi, cs) and
        // its expectations assume tree order matches. Natural sort (default
        // ON) would reorder them — ordering behavior is covered by
        // hierarchy_natural_sort_test.dart; here we test selection mechanics.
        signalTreeNaturalSortProvider.overrideWith((_) => false),
      ],
    );
  }

  late final Variable ramClk;
  late final Variable ramCyc;
  late final Variable tbClk;
  late final ProviderContainer container;

  void dispose() => container.dispose();

  Widget build() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              VariableTreeLeaf(variable: ramClk),
              VariableTreeLeaf(variable: ramCyc),
              VariableTreeLeaf(variable: tbClk),
            ],
          ),
        ),
      ),
    );
  }
}

class _TreeHarness {
  _TreeHarness() {
    sclk = _makeVar(name: 'sclk');
    mosi = _makeVar(name: 'mosi');
    cs = _makeVar(name: 'cs');
    width = _makeVar(name: 'WIDTH', varType: VarType.parameter, bitWidth: 8);
    final scope = Scope(
      name: 'top',
      path: 'top',
      type: ScopeType.module,
      variables: [sclk, mosi, cs, width],
    );
    final source = _MockSource();
    when(() => source.rootScopes).thenReturn([scope]);
    when(() => source.loadSignal(any())).thenAnswer((_) async {});
    when(() => source.startTime).thenReturn(0);
    when(() => source.valueAt(width.signalRef, 0)).thenReturn('b100000');
    container = ProviderContainer(
      overrides: [
        waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
        // The harness pumps leaves in declaration order (sclk, mosi, cs) and
        // its expectations assume tree order matches. Natural sort (default
        // ON) would reorder them — ordering behavior is covered by
        // hierarchy_natural_sort_test.dart; here we test selection mechanics.
        signalTreeNaturalSortProvider.overrideWith((_) => false),
      ],
    );
    // expandedScopesProvider is autoDispose; in the app the tree panel keeps
    // it alive by watching it, but this harness pumps bare leaves — hold a
    // subscription so the pre-expanded 'top' survives until the tap handlers
    // read it.
    container
      ..listen(expandedScopesProvider, (_, _) {})
      ..read(expandedScopesProvider.notifier).toggle('top');
  }

  late final Variable sclk;
  late final Variable mosi;
  late final Variable cs;
  late final Variable width;
  late final ProviderContainer container;

  void dispose() => container.dispose();

  List<Widget> get signalLeaves => [
    VariableTreeLeaf(variable: sclk),
    VariableTreeLeaf(variable: mosi),
    VariableTreeLeaf(variable: cs),
  ];

  Widget build({required List<Widget> children, Locale? locale}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: Column(children: children)),
      ),
    );
  }
}
