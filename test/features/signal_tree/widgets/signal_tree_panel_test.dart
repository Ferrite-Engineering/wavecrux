// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/signal_tree/widgets/variable_tree_leaf.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Variable _makeVar(String name, {String scopePath = 'top'}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: 1,
);

Scope _makeScope({
  String name = 'cpu',
  List<Variable> variables = const [],
  List<Scope> childScopes = const [],
}) => Scope(
  name: name,
  type: ScopeType.module,
  path: 'top.$name',
  variables: variables,
  childScopes: childScopes,
);

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

/// Builds the app with [hierarchyProvider] optionally overridden.
Widget _buildApp({
  List<Override> overrides = const [],
  Locale? locale,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    locale: locale,
    home: const Scaffold(body: SignalTreePanel()),
  ),
);

void main() {
  group('SignalTreePanel', () {
    // ── locale sweep ─────────────────────────────────────────────────────────

    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await tester.pumpWidget(_buildApp(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // ── empty state ───────────────────────────────────────────────────────────

    testWidgets('shows panel title', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Signal Tree'), findsOneWidget);
    });

    testWidgets('shows empty-state message when no waveform is loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      // hierarchyProvider returns AsyncData([]) by default (no source).
      expect(
        find.text('Open a waveform file to browse signals'),
        findsOneWidget,
      );
    });

    // ── with hierarchy ────────────────────────────────────────────────────────

    testWidgets('shows scope nodes when hierarchy is populated', (
      tester,
    ) async {
      final scopes = [_makeScope(name: 'alu'), _makeScope(name: 'mmu')];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('alu'), findsOneWidget);
      expect(find.text('mmu'), findsOneWidget);
    });

    // ── search ────────────────────────────────────────────────────────────────

    testWidgets('search box filters scopes to matching ones', (tester) async {
      final scopes = [
        _makeScope(
          name: 'alu',
          variables: [_makeVar('clk', scopePath: 'top.alu')],
        ),
        _makeScope(name: 'mmu'),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'clk');
      await tester.pumpAndSettle();

      // alu matches (has 'clk' variable), mmu does not.
      expect(find.text('alu'), findsOneWidget);
      expect(find.text('mmu'), findsNothing);
    });

    testWidgets('clearing search restores all scopes', (tester) async {
      final scopes = [
        _makeScope(
          name: 'alu',
          variables: [_makeVar('clk', scopePath: 'top.alu')],
        ),
        _makeScope(name: 'mmu'),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'clk');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.text('alu'), findsOneWidget);
      expect(find.text('mmu'), findsOneWidget);
    });

    testWidgets('shows no-results message when search matches nothing', (
      tester,
    ) async {
      final scopes = [_makeScope(name: 'alu')];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz_no_match');
      await tester.pumpAndSettle();

      expect(find.text('No signals found'), findsOneWidget);
    });

    // ── search cost: debounce and one walk per query ─────────────────────────
    //
    // Filtering walks the whole hierarchy. It used to run on every keystroke,
    // and twice per keystroke: once to expand the matching scopes, once more
    // to flatten the rows. The query now reaches the tree once typing pauses,
    // and each query is walked once.

    List<Scope> searchable() => [
      _makeScope(
        name: 'alu',
        variables: [_makeVar('clk', scopePath: 'top.alu')],
      ),
      _makeScope(name: 'mmu'),
    ];

    testWidgets('a burst of keystrokes walks the hierarchy once', (
      tester,
    ) async {
      final scopes = searchable();
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final before = ScopeMatchIndex.debugTraversals;

      for (final typed in ['c', 'cl', 'clk']) {
        await tester.enterText(find.byType(TextField), typed);
        await tester.pump(const Duration(milliseconds: 40));
      }
      // Still typing: nothing filtered yet.
      expect(find.text('mmu'), findsOneWidget);
      expect(ScopeMatchIndex.debugTraversals - before, 0);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.text('alu'), findsOneWidget);
      expect(find.text('mmu'), findsNothing);
      expect(
        ScopeMatchIndex.debugTraversals - before,
        1,
        reason:
            'one walk for the settled query, shared by the scope '
            'expansion and the row list',
      );
    });

    testWidgets(
      'the clear button applies at once and drops a pending keystroke',
      (tester) async {
        final scopes = searchable();
        final container = ProviderContainer(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: SignalTreePanel()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'clk');
        await tester.pumpAndSettle();
        expect(find.text('mmu'), findsNothing);

        // Another keystroke, then clear before its debounce elapses.
        await tester.enterText(find.byType(TextField), 'clkx');
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pump();
        expect(container.read(signalSearchQueryProvider), isEmpty);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();

        expect(container.read(signalSearchQueryProvider), isEmpty);
        expect(find.text('alu'), findsOneWidget);
        expect(find.text('mmu'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
      },
    );

    // ── expand/collapse ───────────────────────────────────────────────────────

    testWidgets('expand-all button is disabled when no hierarchy', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.unfold_more),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('expand-all button is enabled when hierarchy is loaded', (
      tester,
    ) async {
      final scopes = [_makeScope()];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.unfold_more),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('expand-all expands all scope nodes', (tester) async {
      final scopes = [
        _makeScope(
          variables: [_makeVar('clk', scopePath: 'top.cpu')],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify clk is initially hidden (collapsed).
      expect(find.text('clk'), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.unfold_more));
      await tester.pumpAndSettle();

      expect(find.text('clk'), findsOneWidget);
    });

    testWidgets('loading state shows progress indicator', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => const AsyncLoading()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ── auto-expand on search ─────────────────────────────────────────────────

    // Finds [text] among ListView descendants only, excluding the EditableText
    // search field which also contains the typed query string.
    Finder inTree(String text) =>
        find.descendant(of: find.byType(ListView), matching: find.text(text));

    testWidgets(
      'typing a query auto-expands scopes containing matching variables',
      (tester) async {
        final scopes = [
          _makeScope(
            variables: [_makeVar('clk', scopePath: 'top.cpu')],
          ),
          _makeScope(name: 'mmu'),
        ];
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // 'clk' is hidden because 'cpu' scope starts collapsed.
        expect(inTree('clk'), findsNothing);

        await tester.enterText(find.byType(TextField), 'clk');
        await tester.pumpAndSettle();

        // Auto-expand should have opened 'cpu', making 'clk' visible.
        expect(inTree('clk'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'scopes without matching variables are not auto-expanded on search',
      (tester) async {
        final scopes = [
          _makeScope(
            name: 'alu',
            variables: [_makeVar('clk', scopePath: 'top.alu')],
          ),
          _makeScope(
            name: 'mmu',
            variables: [_makeVar('addr', scopePath: 'top.mmu')],
          ),
        ];
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'clk');
        await tester.pumpAndSettle();

        // 'alu' scope is expanded and shows 'clk'.
        expect(inTree('clk'), findsOneWidget);
        // 'addr' is not visible because 'mmu' was not expanded.
        expect(inTree('addr'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('clearing the search restores the prior expansion state', (
      tester,
    ) async {
      final scopes = [
        _makeScope(
          variables: [_makeVar('clk', scopePath: 'top.cpu')],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Pre-search: 'cpu' is collapsed so 'clk' is hidden.
      expect(inTree('clk'), findsNothing);

      // Type query → auto-expand reveals 'clk'.
      await tester.enterText(find.byType(TextField), 'clk');
      await tester.pumpAndSettle();
      expect(inTree('clk'), findsOneWidget);

      // Clear the search field via the ✕ button.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Expansion state is restored: 'cpu' is collapsed again.
      expect(inTree('clk'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'auto-expand works for deeply nested variables (all ancestors expanded)',
      (tester) async {
        final leaf = Scope(
          name: 'alu',
          type: ScopeType.module,
          path: 'top.cpu.alu',
          variables: [_makeVar('result', scopePath: 'top.cpu.alu')],
        );
        final mid = Scope(
          name: 'cpu',
          type: ScopeType.module,
          path: 'top.cpu',
          childScopes: [leaf],
        );
        final root = Scope(
          name: 'top',
          type: ScopeType.module,
          path: 'top',
          childScopes: [mid],
        );

        await tester.pumpWidget(
          _buildApp(
            overrides: [
              hierarchyProvider.overrideWith((_) => AsyncData([root])),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(inTree('result'), findsNothing);

        await tester.enterText(find.byType(TextField), 'result');
        await tester.pumpAndSettle();

        // 'top', 'cpu', and 'alu' must all be expanded for 'result' to appear.
        expect(inTree('result'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── session-restore seeding / write-back ─────────────────────────────────────
  group('SignalTreePanel — flat lazy tree', () {
    // The tree renders as ONE ListView.builder over signalTreeRowsInOrder
    // with a fixed itemExtent — children are rows of the flat list, never
    // inline children of ScopeTreeNode. These tests own the child-visibility
    // behavior that used to live in scope_tree_node_test.dart.

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(SignalTreePanel)),
        );

    testWidgets('expanding a scope reveals its rows; collapsing hides them', (
      tester,
    ) async {
      final scopes = [
        _makeScope(variables: [_makeVar('clk', scopePath: 'top.cpu')]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('clk'), findsNothing);

      final container = containerOf(tester);
      final notifier = container.read(expandedScopesProvider.notifier)
        ..toggle('top.cpu');
      await tester.pump();
      expect(find.text('clk'), findsOneWidget);

      notifier.toggle('top.cpu');
      await tester.pump();
      expect(find.text('clk'), findsNothing);
    });

    testWidgets('nested child scope appears when its parent is expanded', (
      tester,
    ) async {
      final scopes = [
        _makeScope(
          childScopes: [
            const Scope(
              name: 'alu',
              type: ScopeType.module,
              path: 'top.cpu.alu',
            ),
          ],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('alu'), findsNothing);

      containerOf(
        tester,
      ).read(expandedScopesProvider.notifier).toggle('top.cpu');
      await tester.pump();
      expect(find.text('alu'), findsOneWidget);
    });

    testWidgets(
      'a cross-probe reveal expands the ancestor scopes and surfaces the leaf',
      (tester) async {
        // top.cpu → top.cpu.alu → variable `sum`; both scopes start collapsed.
        final scopes = [
          _makeScope(
            childScopes: [
              Scope(
                name: 'alu',
                type: ScopeType.module,
                path: 'top.cpu.alu',
                variables: [_makeVar('sum', scopePath: 'top.cpu.alu')],
              ),
            ],
          ),
        ];
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // Collapsed: the deep leaf is not rendered.
        expect(find.widgetWithText(VariableTreeLeaf, 'sum'), findsNothing);

        // Simulate the inbound cross-probe reveal request (per-tab provider the
        // CXP handler writes). The panel must expand top.cpu + top.cpu.alu and
        // bring `sum` into the row list.
        containerOf(
          tester,
        ).read(revealSignalRequestProvider.notifier).request('top.cpu.alu.sum');
        await tester.pumpAndSettle();

        expect(find.widgetWithText(VariableTreeLeaf, 'sum'), findsOneWidget);
      },
    );

    testWidgets(
      'a programmatic cross-probe selection in a collapsed scope expands it '
      'and scrolls the leaf into view',
      (tester) async {
        // 40 collapsed sibling scopes; the target leaf lives in the LAST one,
        // far below the fold. Revealing it must therefore BOTH expand the
        // ancestor scope and scroll the list down to it — not just one or the
        // other. (The prior fixed frame-budget retry never got that far on a
        // freshly-opened waveform, so the tree stayed collapsed in the app.)
        final scopes = [
          for (var i = 0; i < 40; i++)
            _makeScope(
              name: 'mod$i',
              variables: i == 39
                  ? [_makeVar('target', scopePath: 'top.mod39')]
                  : const [],
            ),
        ];
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Collapsed + below the fold: the leaf is not rendered and the list has
        // not scrolled.
        expect(find.widgetWithText(VariableTreeLeaf, 'target'), findsNothing);
        final controller = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        expect(controller.offset, 0);

        // Programmatic reveal. Only the CXP inbound handler writes this
        // provider; manual row taps never do — so this path is gated to
        // cross-probe (programmatic) selection, not clicks.
        containerOf(tester)
            .read(revealSignalRequestProvider.notifier)
            .request('top.mod39.target');
        await tester.pumpAndSettle();

        // Ancestor scope expanded, leaf materialized, and the list scrolled
        // down to bring it into view.
        expect(
          containerOf(tester).read(expandedScopesProvider),
          contains('top.mod39'),
        );
        expect(find.widgetWithText(VariableTreeLeaf, 'target'), findsOneWidget);
        expect(controller.offset, greaterThan(0));
      },
    );

    testWidgets('search shows only matching variables inside a scope', (
      tester,
    ) async {
      final scopes = [
        _makeScope(
          variables: [
            _makeVar('clk', scopePath: 'top.cpu'),
            _makeVar('reset', scopePath: 'top.cpu'),
          ],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'clk');
      await tester.pumpAndSettle();

      // Search auto-expands matching scopes; only the match renders. (The
      // search TextField also contains the literal "clk", so scope the text
      // finder to leaf rows.)
      expect(find.widgetWithText(VariableTreeLeaf, 'clk'), findsOneWidget);
      expect(find.widgetWithText(VariableTreeLeaf, 'reset'), findsNothing);
    });

    testWidgets('sibling variables sharing a signalRef — or an entire '
        'name — render without duplicate-key crashes', (tester) async {
      // Gate-level FSTs defeat every value key: a net tied to two ports of
      // one scope shares a signalRef across distinct names, and (seen in a
      // real GF180 netlist) an escaped identifier can be dumped TWICE with
      // the identical name, so even fullPath is not sibling-unique. Row
      // keys must be instance identity (ObjectKey).
      const shared = Variable(
        name: 'clk_i',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'ref_shared',
        scopePath: 'top.cpu',
        bitWidth: 1,
      );
      const alias = Variable(
        name: 'clk_buf',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: 'ref_shared',
        scopePath: 'top.cpu',
        bitWidth: 1,
      );
      // Two distinct instances, byte-identical fields. Deliberately NOT
      // const: const canonicalizes equal instances into one object, which
      // would defeat the ObjectKey-distinctness this test exists to prove.
      // ignore: prefer_const_constructors
      final twinA = Variable(
        name: r'\core.u_fifo.valid',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: 'ref_twin',
        scopePath: 'top.cpu',
        bitWidth: 1,
      );
      // Non-const for the same instance-distinctness reason as twinA.
      // ignore: prefer_const_constructors
      final twinB = Variable(
        name: r'\core.u_fifo.valid',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: 'ref_twin',
        scopePath: 'top.cpu',
        bitWidth: 1,
      );
      final scopes = [
        _makeScope(variables: [shared, alias, twinA, twinB]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      containerOf(
        tester,
      ).read(expandedScopesProvider.notifier).toggle('top.cpu');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('clk_i'), findsOneWidget);
      expect(find.text('clk_buf'), findsOneWidget);
      expect(find.text(r'\core.u_fifo.valid'), findsNWidgets(2));
    });

    testWidgets('expanding a 64k-variable scope builds only viewport rows', (
      tester,
    ) async {
      // THE gate-level requirement (tb.chip_u in the GF180 reference
      // netlist has 64,265 direct variables): expansion must build O(30)
      // row widgets, not 64k, and complete within one interactive frame.
      // The eager-recursion implementation this replaced took >12 minutes
      // in this harness.
      final scopes = [
        _makeScope(
          name: 'chip',
          variables: [
            for (var i = 0; i < 64000; i++)
              _makeVar('net_$i', scopePath: 'top.chip'),
          ],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(scopes)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      containerOf(
        tester,
      ).read(expandedScopesProvider.notifier).toggle('top.chip');
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();

      final builtLeaves = find.byType(VariableTreeLeaf).evaluate().length;
      expect(
        builtLeaves,
        lessThan(100),
        reason:
            'lazy list must materialize only ~viewport rows, '
            'built $builtLeaves',
      );
      expect(find.text('net_0'), findsOneWidget);
      // Generous CI headroom; the eager version took minutes.
      expect(
        sw.elapsedMilliseconds,
        lessThan(3000),
        reason: '64k expansion frame took ${sw.elapsedMilliseconds} ms',
      );
    });
  });

  group('SignalTreePanel — session-restore seeding', () {
    // A tall hierarchy so the ListView actually scrolls.
    List<Scope> tallHierarchy() => [
      for (var i = 0; i < 40; i++) _makeScope(name: 'mod$i'),
    ];

    // The ListView's vertical ScrollController. (A TextField hosts its own
    // inner Scrollable, so we read the controller off the ListView directly
    // rather than via find.byType(Scrollable).)
    ScrollController? listController(WidgetTester tester) =>
        tester.widget<ListView>(find.byType(ListView)).controller;

    Widget app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(height: 300, child: SignalTreePanel()),
        ),
      ),
    );

    testWidgets('seeds the search box from the restored search query', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          hierarchyProvider.overrideWith((_) => AsyncData(tallHierarchy())),
        ],
      );
      addTearDown(container.dispose);
      // Simulate a session restore having populated the per-tab provider
      // before the panel mounts.
      container.read(signalSearchQueryProvider.notifier).setQuery(query: 'clk');

      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'clk');
    });

    testWidgets(
      'writes the scroll offset back to the provider as the list scrolls',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(tallHierarchy())),
          ],
        );
        addTearDown(container.dispose);
        // Keep the autoDispose scroll provider alive across async gaps the way
        // the per-tab autosave listener does in the real app (the panel only
        // reads its notifier, it does not watch it).
        container.listen(signalTreeScrollProvider, (_, _) {});

        await tester.pumpWidget(app(container));
        await tester.pumpAndSettle();

        expect(container.read(signalTreeScrollProvider), 0.0);
        // jumpTo drives the controller's listeners exactly as a user scroll
        // does, so this exercises the panel's _onScroll → provider write-back
        // without the gesture-arena fragility of a simulated drag.
        listController(tester)!.jumpTo(150);
        await tester.pump();

        expect(container.read(signalTreeScrollProvider), 150);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('seeds the scroll controller from the restored offset', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          hierarchyProvider.overrideWith((_) => AsyncData(tallHierarchy())),
        ],
      );
      addTearDown(container.dispose);
      container.read(signalTreeScrollProvider.notifier).setOffset(120);

      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();

      expect(listController(tester)?.offset, 120);
      expect(tester.takeException(), isNull);
    });
  });
}
