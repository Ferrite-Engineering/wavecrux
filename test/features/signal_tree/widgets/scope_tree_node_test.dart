// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart' show AnnouncementRecorder;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/widgets/scope_tree_node.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Variable _makeVar(
  String name, {
  String scopePath = 'top',
  VarType varType = VarType.wire,
  int? bitWidth,
}) => Variable(
  name: name,
  varType: varType,
  direction: VarDirection.unknown,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: bitWidth ?? 1,
);

Scope _makeScope({
  String name = 'cpu',
  String path = 'top.cpu',
  ScopeType type = ScopeType.module,
  List<Variable> variables = const [],
  List<Scope> childScopes = const [],
}) => Scope(
  name: name,
  type: type,
  path: path,
  variables: variables,
  childScopes: childScopes,
);

Widget _buildApp(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Widget _buildAppLocale(Widget child, Locale locale) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('ScopeTreeNode', () {
    // ── Locale sweeps ────────────────────────────────────────────────────────
    testWidgets('renders in en locale without exceptions', (tester) async {
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: _makeScope())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('locale sweep ${locale.languageCode} — no exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildAppLocale(ScopeTreeNode(scope: _makeScope()), locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // ── Basic rendering ──────────────────────────────────────────────────────
    testWidgets('displays scope name', (tester) async {
      await tester.pumpWidget(
        _buildApp(ScopeTreeNode(scope: _makeScope(name: 'alu'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('alu'), findsOneWidget);
    });

    testWidgets('shows signal count badge when scope has variables', (
      tester,
    ) async {
      final scope = _makeScope(
        variables: [_makeVar('clk'), _makeVar('data')],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('no badge when scope has no variables', (tester) async {
      final scope = _makeScope(variables: [], childScopes: []);
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();
      // No count badge visible.
      expect(find.text('0'), findsNothing);
    });

    // ── Expand / collapse ────────────────────────────────────────────────────
    // ScopeTreeNode renders ONLY the header row; children are separate rows
    // of the panel's flat lazy list. Child-visibility behavior (expansion,
    // collapse, search filtering, alias twins) is covered by
    // signal_tree_panel_test.dart and signal_tree_rows_test.dart.

    // Latency contract: expansion must land on the FIRST frame after the
    // tap, with no artificial clock advance. Asserting after a
    // `pump(500ms)` would hide the defect these tests exist to catch —
    // that is exactly how a competing `onDoubleTap` recognizer used to
    // sit on the gesture arena for `kDoubleTapTimeout` while every single
    // click on a scope row did nothing visible for ~300 ms.
    testWidgets(
      'tap on scope header toggles expansion on the very next frame',
      (
        tester,
      ) async {
        final scope = _makeScope(
          path: 'top.tap',
          variables: [_makeVar('sig', scopePath: 'top.tap')],
        );
        await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ScopeTreeNode)),
        );
        final sub = container.listen(expandedScopesProvider, (_, _) {});
        addTearDown(sub.close);
        expect(
          container.read(expandedScopesProvider),
          isNot(contains('top.tap')),
        );

        // No clock advance — one bare frame.
        await tester.tap(find.text('cpu'));
        await tester.pump();
        expect(container.read(expandedScopesProvider), contains('top.tap'));
        expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

        // Tap again to collapse — also immediate.
        await tester.tap(find.text('cpu'));
        await tester.pump();
        expect(
          container.read(expandedScopesProvider),
          isNot(contains('top.tap')),
        );
        expect(find.byIcon(Icons.arrow_right), findsOneWidget);
      },
    );

    testWidgets('the row registers no double-tap recognizer', (tester) async {
      // Structural guard for the fix: a sibling `onDoubleTap` HOLDS the
      // gesture arena for kDoubleTapTimeout, which is what made `onTap`
      // fire ~300 ms late. The double-tap used to run the identical
      // toggle, so it bought nothing for that cost. If a double-tap
      // handler is ever added back here, it must come with a different
      // latency story than "onTap waits for the arena".
      await tester.pumpWidget(
        _buildApp(ScopeTreeNode(scope: _makeScope(variables: [_makeVar('a')]))),
      );
      await tester.pumpAndSettle();

      final detector = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byType(ScopeTreeNode),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(detector.onDoubleTap, isNull);
      expect(detector.onTap, isNotNull);
    });

    testWidgets('two taps inside the double-tap window both toggle', (
      tester,
    ) async {
      // Deliberate trade-off, pinned so it can't regress silently: with
      // the double-tap recognizer gone, a genuine double-click toggles
      // twice (expand + collapse) instead of once. That costs a rare
      // gesture instead of taxing every single click by ~300 ms, and it
      // matches how click-to-toggle trees (VS Code's explorer) behave.
      final scope = _makeScope(
        path: 'top.dbl',
        variables: [_makeVar('sig', scopePath: 'top.dbl')],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScopeTreeNode)),
      );
      final sub = container.listen(expandedScopesProvider, (_, _) {});
      addTearDown(sub.close);

      await tester.tap(find.text('cpu'));
      await tester.pump();
      await tester.tap(find.text('cpu'));
      await tester.pump();
      expect(
        container.read(expandedScopesProvider),
        isNot(contains('top.dbl')),
      );
    });

    testWidgets('tap on an empty scope does not expand it', (tester) async {
      final scope = _makeScope(
        path: 'top.empty',
        variables: [],
        childScopes: [],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScopeTreeNode)),
      );
      final sub = container.listen(expandedScopesProvider, (_, _) {});
      addTearDown(sub.close);

      await tester.tap(find.text('cpu'));
      await tester.pump();
      expect(
        container.read(expandedScopesProvider),
        isNot(contains('top.empty')),
      );
    });

    // ── Arrow icons ──────────────────────────────────────────────────────────
    testWidgets('scope with no content shows no expand arrow', (tester) async {
      final empty = _makeScope(variables: [], childScopes: []);
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: empty)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_right), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('collapsed scope with children shows right arrow', (
      tester,
    ) async {
      final scope = _makeScope(variables: [_makeVar('clk')]);
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_right), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('expanded scope with children shows down arrow', (
      tester,
    ) async {
      final scope = _makeScope(
        path: 'top.arrow',
        variables: [_makeVar('clk', scopePath: 'top.arrow')],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScopeTreeNode)),
      );
      container.read(expandedScopesProvider.notifier).toggle('top.arrow');
      await tester.pump();

      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
      expect(find.byIcon(Icons.arrow_right), findsNothing);
    });

    // ── Scope type icons ─────────────────────────────────────────────────────
    testWidgets('module scope shows memory icon', (tester) async {
      final scope = _makeScope();
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.memory), findsOneWidget);
    });

    testWidgets('task scope shows assignment icon', (tester) async {
      final scope = _makeScope(
        type: ScopeType.task,
        path: 'top.task1',
        variables: [],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.assignment), findsOneWidget);
    });

    testWidgets('function scope shows functions icon', (tester) async {
      final scope = _makeScope(
        type: ScopeType.function,
        path: 'top.fn1',
        variables: [],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.functions), findsOneWidget);
    });

    testWidgets('begin scope shows account_tree icon', (tester) async {
      final scope = _makeScope(
        type: ScopeType.begin,
        path: 'top.begin1',
        variables: [],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.account_tree), findsOneWidget);
    });

    // ── Add-all via notifier (bypasses context menu for testability) ─────────
    testWidgets('addSignals adds all variables in scope to signal group', (
      tester,
    ) async {
      final scope = _makeScope(
        path: 'top.addall',
        variables: [
          _makeVar('a', scopePath: 'top.addall'),
          _makeVar('b', scopePath: 'top.addall'),
        ],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScopeTreeNode)),
      );
      container.read(signalGroupsProvider.notifier).addSignals(scope.variables);

      final entries = container.read(signalGroupsProvider).entries;
      expect(entries.length, 2);
      expect(entries.map((e) => e.displayName), containsAll(['a', 'b']));
    });

    // ── Variable leaf rendering ──────────────────────────────────────────────
    // Leaf rendering (name, tap-adds, bit-width badge) is covered directly
    // in variable_tree_leaf_test.dart; leaves are no longer children of this
    // widget (flat lazy list — see signal_tree_panel_test.dart).

    // ── "Add All in Scope" ───────────────────────────────────────────────────
    testWidgets('small scope adds via the context menu, indicator armed', (
      tester,
    ) async {
      final recorder = AnnouncementRecorder.attach(tester);
      final scope = _makeScope(
        variables: [_makeVar('clk'), _makeVar('data')],
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
                home: Scaffold(body: ScopeTreeNode(scope: scope)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final seen = <SignalLoadProgressState>[];
      container.listen(signalLoadProgressProvider, (_, next) {
        if (next.active) seen.add(next);
      });

      await tester.tap(find.text('cpu'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      await tester.tap(find.text(l10n.signalTreeAddAllInScope));
      await tester.pumpAndSettle();

      expect(container.read(signalGroupsProvider).entries, hasLength(2));
      // Below the chunked threshold the entries still build synchronously,
      // but the indicator is armed — indeterminate for the walk, then held at
      // total/total for the canvas to take over — and released afterwards.
      expect(seen.map((s) => s.phase).toSet(), {SignalLoadPhase.adding});
      expect(seen.first.total, 0, reason: 'armed before the walk');
      expect(seen.last.loaded, 2);
      expect(seen.last.total, 2);
      expect(container.read(signalLoadProgressProvider).active, isFalse);
      // The new lanes appear away from the menu, so the add is spoken.
      expect(recorder.messages, ['2 signals added to the viewer']);
    });

    testWidgets(
      'large scope takes the chunked path: progress runs, all entries land, '
      'indicator returns to idle',
      (tester) async {
        // At/above the chunked-add threshold (5000).
        final recorder = AnnouncementRecorder.attach(tester);
        final scope = _makeScope(
          variables: [for (var i = 0; i < 6000; i++) _makeVar('s$i')],
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
                  home: Scaffold(body: ScopeTreeNode(scope: scope)),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final phases = <SignalLoadPhase>[];
        container.listen(signalLoadProgressProvider, (_, next) {
          if (next.active) phases.add(next.phase);
        });

        await tester.tap(find.text('cpu'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        final l10n = L10N.of(tester.element(find.byType(Scaffold)));
        await tester.tap(find.text(l10n.signalTreeAddAllInScope));
        await tester.pumpAndSettle();

        expect(container.read(signalGroupsProvider).entries, hasLength(6000));
        expect(phases, isNotEmpty);
        expect(phases.toSet(), {SignalLoadPhase.adding});
        expect(container.read(signalLoadProgressProvider).active, isFalse);
        expect(recorder.messages, ['6000 signals added to the viewer']);
      },
    );

    testWidgets('the walk keeps tree order across nested and large scopes', (
      tester,
    ) async {
      // Past the walk's yield interval (20000), so the walk crosses at least
      // one event-loop yield, with nesting on both sides of it.
      Scope leaf(String name, int count) => _makeScope(
        name: name,
        path: 'top.$name',
        variables: [
          for (var i = 0; i < count; i++)
            _makeVar('${name}_$i', scopePath: 'top.$name'),
        ],
      );
      final scope = _makeScope(
        variables: [_makeVar('own')],
        childScopes: [
          _makeScope(
            name: 'a',
            path: 'top.a',
            variables: [_makeVar('a_own', scopePath: 'top.a')],
            childScopes: [leaf('a1', 15000), leaf('a2', 3)],
          ),
          leaf('b', 15000),
        ],
      );
      final expected = [
        'own',
        'a_own',
        for (var i = 0; i < 15000; i++) 'a1_$i',
        for (var i = 0; i < 3; i++) 'a2_$i',
        for (var i = 0; i < 15000; i++) 'b_$i',
      ];
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(body: ScopeTreeNode(scope: scope)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('cpu'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      await tester.tap(find.text(l10n.signalTreeAddAllInScope));
      await tester.pumpAndSettle();

      final names = container
          .read(signalGroupsProvider)
          .entries
          .map((e) => e.displayName)
          .toList();
      expect(names, expected);
      expect(container.read(signalLoadProgressProvider).active, isFalse);
    });

    testWidgets('cancelling during the scope walk adds nothing', (
      tester,
    ) async {
      // Two big children: the walk yields between them, where it sees the
      // cancel requested while the indicator was still indeterminate.
      final scope = _makeScope(
        childScopes: [
          for (final name in ['x', 'y'])
            _makeScope(
              name: name,
              path: 'top.$name',
              variables: [
                for (var i = 0; i < 25000; i++)
                  _makeVar('$name$i', scopePath: 'top.$name'),
              ],
            ),
        ],
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
                home: Scaffold(body: ScopeTreeNode(scope: scope)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final totals = <int>[];
      container.listen(signalLoadProgressProvider, (_, next) {
        if (!next.active) return;
        totals.add(next.total);
        if (next.total == 0 && !next.cancelRequested) {
          container.read(signalLoadProgressProvider.notifier).requestCancel();
        }
      });

      await tester.tap(find.text('cpu'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      await tester.tap(find.text(l10n.signalTreeAddAllInScope));
      await tester.pumpAndSettle();

      expect(container.read(signalGroupsProvider).entries, isEmpty);
      // The walk never produced a sized batch.
      expect(totals.where((t) => t > 0), isEmpty);
      expect(container.read(signalLoadProgressProvider).active, isFalse);
    });

    testWidgets('cancelling the chunked add leaves the viewer unchanged', (
      tester,
    ) async {
      final scope = _makeScope(
        variables: [for (var i = 0; i < 60000; i++) _makeVar('s$i')],
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
                home: Scaffold(body: ScopeTreeNode(scope: scope)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cancel as soon as the adding phase begins (after the first chunk).
      container.listen(signalLoadProgressProvider, (_, next) {
        if (next.active && !next.cancelRequested) {
          container.read(signalLoadProgressProvider.notifier).requestCancel();
        }
      });

      await tester.tap(find.text('cpu'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      await tester.tap(find.text(l10n.signalTreeAddAllInScope));
      await tester.pumpAndSettle();

      // All-or-nothing: a cancelled bulk add applies nothing.
      expect(container.read(signalGroupsProvider).entries, isEmpty);
      expect(container.read(signalLoadProgressProvider).active, isFalse);
    });
  });

  group('ScopeTreeNode — screen reader and keyboard', () {
    testWidgets('is one button named after the scope, with state and count', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final scope = _makeScope(
        variables: [_makeVar('clk'), _makeVar('data')],
      );
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: scope)));
      await tester.pumpAndSettle();

      final row = find.byType(ScopeTreeNode);
      expect(
        tester.getSemantics(row),
        isSemantics(
          label: 'cpu',
          value: '2 signals',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text('cpu'));
      await tester.pump();
      expect(
        tester.getSemantics(row),
        isSemantics(label: 'cpu', isExpanded: true),
      );
      handle.dispose();
    });

    testWidgets('a scope with nothing in it has no expanded state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: _makeScope())));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(ScopeTreeNode)),
        isSemantics(label: 'cpu', hasExpandedState: false),
      );
      handle.dispose();
    });

    testWidgets('outside a tree the row is not a focus target', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildApp(ScopeTreeNode(scope: _makeScope())));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(ScopeTreeNode)),
        isSemantics(isFocusable: false, hasFocusAction: false),
      );
      handle.dispose();
    });

    testWidgets('inside a tree the row reports focus and draws a ring', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var focusRequests = 0;
      await tester.pumpWidget(
        _buildApp(
          ScopeTreeNode(
            scope: _makeScope(variables: [_makeVar('clk')]),
            keyboardFocused: true,
            onFocusRequested: () => focusRequests++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byType(ScopeTreeNode);
      expect(
        tester.getSemantics(row),
        isSemantics(
          isFocusable: true,
          isFocused: true,
          hasFocusAction: true,
        ),
      );
      tester.semantics.performAction(
        find.semantics.byLabel('cpu'),
        SemanticsAction.focus,
      );
      expect(focusRequests, 1);
      expect(
        tester
            .widgetList<Container>(
              find.descendant(of: row, matching: find.byType(Container)),
            )
            .where((c) => c.foregroundDecoration != null),
        hasLength(1),
      );
      handle.dispose();
    });

    testWidgets('a click reports the row to the tree before toggling', (
      tester,
    ) async {
      final order = <String>[];
      final scope = _makeScope(variables: [_makeVar('clk')]);
      await tester.pumpWidget(
        _buildApp(
          ScopeTreeNode(scope: scope, onTapped: () => order.add('tapped')),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScopeTreeNode)),
      )..listen(expandedScopesProvider, (_, _) => order.add('toggled'));

      await tester.tap(find.text('cpu'));
      await tester.pump();

      expect(order, ['tapped', 'toggled']);
      expect(container.read(expandedScopesProvider), {'top.cpu'});
    });
  });
}
