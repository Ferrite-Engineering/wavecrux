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
import 'package:wavecrux/features/search/providers/search_providers.dart';
import 'package:wavecrux/features/search/widgets/signal_search_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Variable _makeVar(String name, {String scopePath = 'top'}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: '$scopePath.$name',
  scopePath: scopePath,
  bitWidth: 8,
);

Scope _makeScope(String name, {List<Variable> variables = const []}) => Scope(
  name: name,
  type: ScopeType.module,
  path: 'top.$name',
  variables: variables,
);

Widget _buildApp({List<Override> overrides = const []}) => ProviderScope(
  overrides: [productTelemetryConfig, ...overrides],
  child: const MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: SignalSearchDialog(),
    ),
  ),
);

void main() {
  group('SignalSearchDialog', () {
    // ── locale sweep ────────────────────────────────────────────────────────

    testWidgets('renders in en locale without exceptions', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ── static structure ────────────────────────────────────────────────────

    testWidgets('shows dialog title', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Search Signals'), findsOneWidget);
    });

    testWidgets('shows search text field', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('shows Substring and Glob mode segments', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Substring'), findsOneWidget);
      expect(find.text('Glob'), findsOneWidget);
    });

    testWidgets('shows all five type filter chips', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Wire'), findsOneWidget);
      expect(find.text('Reg'), findsOneWidget);
      expect(find.text('Integer'), findsOneWidget);
      expect(find.text('Real'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
    });

    testWidgets('shows Add All button when results exist', (tester) async {
      final scopes = [
        _makeScope('cpu', variables: [_makeVar('clk')]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add All'), findsOneWidget);
    });

    testWidgets('shows Close button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      // MaterialLocalizations.closeButtonLabel is locale-dependent; find by
      // checking that a TextButton is present in the action row.
      expect(find.byType(TextButton), findsWidgets);
    });

    // ── empty state ─────────────────────────────────────────────────────────

    testWidgets('shows no-results message when no waveform is loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(
        find.text('No signals match your search'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('results region keeps a fixed height when empty (no balloon)', (
      tester,
    ) async {
      double columnHeight() => tester
          .getSize(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Column),
                )
                .first,
          )
          .height;

      // Empty state — hierarchy with no variables → zero results. (Keep the
      // override count stable across pumps; Riverpod forbids changing it.)
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            hierarchyProvider.overrideWith(
              (_) => const AsyncData<List<Scope>>([]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final emptyHeight = columnHeight();

      // Populated state.
      final scopes = [
        _makeScope(
          'cpu',
          variables: [
            _makeVar('clk', scopePath: 'top.cpu'),
            _makeVar('data', scopePath: 'top.cpu'),
          ],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();
      final populatedHeight = columnHeight();

      // The dialog must not grow/shrink as the match count changes: the empty
      // state previously ballooned because a bare Center expanded to fill the
      // Flexible's bounded constraints.
      expect(emptyHeight, populatedHeight);
    });

    // ── search interaction ──────────────────────────────────────────────────

    testWidgets('typing in search field shows matching signal names', (
      tester,
    ) async {
      final scopes = [
        _makeScope(
          'cpu',
          variables: [
            _makeVar('clk', scopePath: 'top.cpu'),
            _makeVar('data', scopePath: 'top.cpu'),
          ],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      // Find the first TextField (the search field).
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'clk');
      await tester.pumpAndSettle();

      expect(find.text('clk'), findsOneWidget);
      expect(find.text('data'), findsNothing);
    });

    testWidgets('result count label updates with matching count', (
      tester,
    ) async {
      final scopes = [
        _makeScope(
          'cpu',
          variables: [
            _makeVar('clk', scopePath: 'top.cpu'),
            _makeVar('data', scopePath: 'top.cpu'),
          ],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      // Should show 2 signals initially (no filter).
      expect(find.text('2 signals'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'clk');
      await tester.pumpAndSettle();

      expect(find.text('1 signal'), findsOneWidget);
    });

    // ── type filter chips ───────────────────────────────────────────────────

    testWidgets('tapping a type chip applies type filter', (tester) async {
      final wireSignal = _makeVar('clk', scopePath: 'top.cpu');
      const regSignal = Variable(
        name: 'cnt',
        varType: VarType.reg,
        direction: VarDirection.unknown,
        signalRef: 'top.cpu.cnt',
        scopePath: 'top.cpu',
        bitWidth: 8,
      );
      final scopes = [
        _makeScope('cpu', variables: [wireSignal, regSignal]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      // Tap the "Wire" chip — only wire signals should show.
      await tester.tap(find.text('Wire'));
      await tester.pumpAndSettle();

      expect(find.text('clk'), findsOneWidget);
      expect(find.text('cnt'), findsNothing);
    });

    // ── advanced filters toggle ─────────────────────────────────────────────

    testWidgets('tapping filter icon reveals advanced filter fields', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Advanced filters (width + scope) should not be visible initially.
      expect(find.text('Min'), findsNothing);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(find.text('Min'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
    });

    // ── mode toggle ─────────────────────────────────────────────────────────

    testWidgets('switching to Glob mode uses glob matching', (tester) async {
      final scopes = [
        _makeScope(
          'cpu',
          variables: [
            _makeVar('axi_rdata', scopePath: 'top.cpu'),
            _makeVar('clk', scopePath: 'top.cpu'),
          ],
        ),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Glob'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'axi_*');
      await tester.pumpAndSettle();

      expect(find.text('axi_rdata'), findsOneWidget);
      expect(find.text('clk'), findsNothing);
    });

    // ── direction filter chips ──────────────────────────────────────────────

    testWidgets('shows three direction filter chips', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Input'), findsOneWidget);
      expect(find.text('Output'), findsOneWidget);
      expect(find.text('Inout'), findsOneWidget);
    });

    testWidgets('direction chips render in zh_CN locale without exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [productTelemetryConfig],
          child: const MaterialApp(
            locale: Locale('zh', 'CN'),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: SignalSearchDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('direction chips render in ja locale without exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [productTelemetryConfig],
          child: const MaterialApp(
            locale: Locale('ja'),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: SignalSearchDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('direction chips render in ko locale without exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [productTelemetryConfig],
          child: const MaterialApp(
            locale: Locale('ko'),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: SignalSearchDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Input chip filters to input-direction signals', (
      tester,
    ) async {
      const inputVar = Variable(
        name: 'addr',
        varType: VarType.port,
        direction: VarDirection.input,
        signalRef: 'top.cpu.addr',
        scopePath: 'top.cpu',
        bitWidth: 8,
      );
      const outputVar = Variable(
        name: 'data',
        varType: VarType.port,
        direction: VarDirection.output,
        signalRef: 'top.cpu.data',
        scopePath: 'top.cpu',
        bitWidth: 8,
      );
      final scopes = [
        _makeScope('cpu', variables: [inputVar, outputVar]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      // Both signals visible before filter
      expect(find.text('addr'), findsOneWidget);
      expect(find.text('data'), findsOneWidget);

      await tester.tap(find.text('Input'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('addr'), findsOneWidget);
      expect(find.text('data'), findsNothing);
    });

    testWidgets('tapping Output chip filters to output-direction signals', (
      tester,
    ) async {
      const inputVar = Variable(
        name: 'addr',
        varType: VarType.port,
        direction: VarDirection.input,
        signalRef: 'top.cpu.addr',
        scopePath: 'top.cpu',
        bitWidth: 8,
      );
      const outputVar = Variable(
        name: 'data',
        varType: VarType.port,
        direction: VarDirection.output,
        signalRef: 'top.cpu.data',
        scopePath: 'top.cpu',
        bitWidth: 8,
      );
      final scopes = [
        _makeScope('cpu', variables: [inputVar, outputVar]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Output'));
      await tester.pumpAndSettle();

      expect(find.text('data'), findsOneWidget);
      expect(find.text('addr'), findsNothing);
    });

    testWidgets('direction chip toggles off on second tap', (tester) async {
      const inputVar = Variable(
        name: 'addr',
        varType: VarType.port,
        direction: VarDirection.input,
        signalRef: 'top.cpu.addr',
        scopePath: 'top.cpu',
        bitWidth: 1,
      );
      const outputVar = Variable(
        name: 'data',
        varType: VarType.port,
        direction: VarDirection.output,
        signalRef: 'top.cpu.data',
        scopePath: 'top.cpu',
        bitWidth: 1,
      );
      final scopes = [
        _makeScope('cpu', variables: [inputVar, outputVar]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      // Enable filter
      await tester.tap(find.text('Input'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('data'), findsNothing);

      // Disable filter — both signals should be visible again
      await tester.tap(find.text('Input'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('addr'), findsOneWidget);
      expect(find.text('data'), findsOneWidget);
    });

    testWidgets('direction chip selected state is reflected via provider', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inout'), warnIfMissed: false);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SignalSearchDialog)),
      );
      final filter = container.read(searchDialogFilterProvider);
      expect(filter.isDefault, isFalse);
    });

    // ── show() tab-scope routing ────────────────────────────────────────────

    testWidgets(
      'show() with tabContainer resolves hierarchyProvider from tab scope',
      (tester) async {
        final clk = _makeVar('clk');
        final scopes = [
          _makeScope('top', variables: [clk]),
        ];

        // Root container has no hierarchy; tab container has signals.
        final rootContainer = ProviderContainer(
          overrides: [productTelemetryConfig],
        );
        addTearDown(rootContainer.dispose);
        final tabContainer = ProviderContainer(
          parent: rootContainer,
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        );
        addTearDown(tabContainer.dispose);

        late BuildContext ctx;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: rootContainer,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (c) {
                  ctx = c;
                  return const Scaffold(body: SizedBox.shrink());
                },
              ),
            ),
          ),
        );

        // Open via show() with the tab container — dialog must see tab's signals.
        SignalSearchDialog.show(ctx, tabContainer: tabContainer).ignore();
        await tester.pumpAndSettle();

        expect(find.text('clk'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'show() without tabContainer falls back to root scope (no signals)',
      (tester) async {
        final rootContainer = ProviderContainer(
          overrides: [productTelemetryConfig],
        );
        addTearDown(rootContainer.dispose);

        late BuildContext ctx;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: rootContainer,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (c) {
                  ctx = c;
                  return const Scaffold(body: SizedBox.shrink());
                },
              ),
            ),
          ),
        );

        SignalSearchDialog.show(ctx).ignore();
        await tester.pumpAndSettle();

        expect(
          find.text('No signals match your search'),
          findsAtLeastNWidgets(1),
        );
        expect(tester.takeException(), isNull);
      },
    );

    // ── add to viewer ───────────────────────────────────────────────────────

    testWidgets('tapping a result row adds signal to signal groups', (
      tester,
    ) async {
      final clk = _makeVar('clk', scopePath: 'top.cpu');
      final scopes = [
        _makeScope('cpu', variables: [clk]),
      ];
      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('clk'));
      await tester.pumpAndSettle();

      // Verify signal groups notifier received the signal via provider inspection.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SignalSearchDialog)),
      );
      final groups = container.read(signalGroupsProvider);
      expect(groups.entries, hasLength(1));
      expect(groups.entries.first.signalRef, clk.signalRef);
    });

    // ── FST alias identity ──────────────────────────────────────────────────

    testWidgets('checking one FST alias row leaves its siblings unchecked', (
      tester,
    ) async {
      // One underlying signal wired through two scopes: distinct rows,
      // distinct fullPaths, but a single shared signalRef — the FST aliasing
      // shape that a ref-keyed selection conflated.
      const sharedRef = 'sig#7';
      const aliasA = Variable(
        name: 'wb_cyc_i',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: sharedRef,
        scopePath: 'top.wb_ram0',
      );
      const aliasB = Variable(
        name: 'wb_cyc_i',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: sharedRef,
        scopePath: 'top.wb_ram1',
      );
      final scopes = [
        _makeScope('wb_ram0', variables: const [aliasA]),
        _makeScope('wb_ram1', variables: const [aliasB]),
      ];

      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(2));

      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(checkboxes.at(0)).value, isTrue);
      expect(tester.widget<Checkbox>(checkboxes.at(1)).value, isFalse);
    });

    testWidgets('Add Selected adds only the checked alias, not its siblings', (
      tester,
    ) async {
      const sharedRef = 'sig#7';
      const aliasA = Variable(
        name: 'wb_cyc_i',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: sharedRef,
        scopePath: 'top.wb_ram0',
      );
      const aliasB = Variable(
        name: 'wb_cyc_i',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: sharedRef,
        scopePath: 'top.wb_ram1',
      );
      final scopes = [
        _makeScope('wb_ram0', variables: const [aliasA]),
        _makeScope('wb_ram1', variables: const [aliasB]),
      ];

      await tester.pumpWidget(
        _buildApp(
          overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(find.text('Add 1 Signal'), findsOneWidget);

      await tester.tap(find.text('Add 1 Signal'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SignalSearchDialog)),
      );
      expect(container.read(signalGroupsProvider).entries, hasLength(1));
    });
  });
}
