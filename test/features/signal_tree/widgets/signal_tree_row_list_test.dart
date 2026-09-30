// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The signal tree from the keyboard. The external NVDA pass found no keyboard
// route to a signal at all: the rows were bare gesture detectors, so the
// only way to add one without a mouse was Ctrl+F. These tests pin the tree
// keys, the single Tab stop, the app keymap not stealing the tree's arrows,
// focus surviving the lazy list, and the row context menu and selection
// working without a pointer.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/widgets/scope_tree_node.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_row_list.dart';
import 'package:wavecrux/features/signal_tree/widgets/variable_tree_leaf.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── fixture ─────────────────────────────────────────────────────────────────

Variable _v(String name, String scopePath, {int bitWidth = 1}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$scopePath.$name',
  scopePath: scopePath,
  bitWidth: bitWidth,
);

/// top: cpu (a, b[7:0]), clk, rst
List<Scope> _tree() => [
  Scope(
    name: 'top',
    type: ScopeType.module,
    path: 'top',
    variables: [_v('clk', 'top'), _v('rst', 'top')],
    childScopes: [
      Scope(
        name: 'cpu',
        type: ScopeType.module,
        path: 'top.cpu',
        variables: [_v('a', 'top.cpu'), _v('b', 'top.cpu', bitWidth: 8)],
      ),
    ],
  ),
];

/// One scope holding [count] signals, for the lazy-list tests.
List<Scope> _wide(int count) => [
  Scope(
    name: 'wide',
    type: ScopeType.module,
    path: 'wide',
    variables: [
      for (var i = 0; i < count; i++)
        _v('s${i.toString().padLeft(3, '0')}', 'wide'),
    ],
  ),
];

// ── harness ─────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  List<Scope>? scopes,
  Map<ShortcutAction, VoidCallback> handlers = const {},
  List<LogicalKeyboardKey>? keysReachingApp,
  Locale? locale,
}) async {
  final tree = scopes ?? _tree();
  Widget panel = const SizedBox(width: 320, child: SignalTreePanel());
  if (keysReachingApp != null) {
    panel = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) keysReachingApp.add(event.logicalKey);
        return KeyEventResult.ignored;
      },
      child: panel,
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [hierarchyProvider.overrideWith((_) => AsyncData(tree))],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: ShortcutManagerWidget(
          handlers: handlers,
          child: Scaffold(
            body: Row(
              children: [
                panel,
                const Expanded(
                  child: Focus(
                    debugLabel: 'Elsewhere',
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SignalTreePanel)));

bool get _treeFocused =>
    FocusManager.instance.primaryFocus?.debugLabel == 'Signal tree';

/// The path of the row the keyboard is on, as the rows report it.
String? _current(WidgetTester tester) {
  for (final row in tester.widgetList<ScopeTreeNode>(
    find.byType(ScopeTreeNode),
  )) {
    if (row.keyboardFocused) return row.scope.path;
  }
  for (final row in tester.widgetList<VariableTreeLeaf>(
    find.byType(VariableTreeLeaf),
  )) {
    if (row.keyboardFocused) return row.variable.fullPath;
  }
  return null;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// Focus the search field, then Tab into the tree — the route a keyboard
/// user takes.
Future<void> _tabIntoTree(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  await _key(tester, LogicalKeyboardKey.tab);
}

void _expandAll(WidgetTester tester) =>
    _container(
          tester,
        )
        .read(expandedScopesProvider.notifier)
        .expandAll(
          _container(tester)
              .read(
                hierarchyProvider,
              )
              .requireValue,
        );

// ── tests ───────────────────────────────────────────────────────────────────

void main() {
  group('SignalTreeRowList — locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('keyboard use renders in $locale without exceptions', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        await _tabIntoTree(tester);
        await _key(tester, LogicalKeyboardKey.arrowRight);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SignalTreeRowList — one Tab stop', () {
    testWidgets('Tab from the search field lands on the first row', (
      tester,
    ) async {
      await _pump(tester);
      await _tabIntoTree(tester);

      expect(_treeFocused, isTrue);
      expect(_current(tester), 'top');
    });

    testWidgets('the next Tab leaves the tree instead of visiting rows', (
      tester,
    ) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);

      await _key(tester, LogicalKeyboardKey.tab);

      expect(_treeFocused, isFalse);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Elsewhere');
    });

    testWidgets('Tab back returns to the row the keyboard was last on', (
      tester,
    ) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_current(tester), 'top.cpu.a');

      await _key(tester, LogicalKeyboardKey.tab);
      expect(_current(tester), isNull, reason: 'no focus ring without focus');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(_treeFocused, isTrue);
      expect(_current(tester), 'top.cpu.a');
    });

    testWidgets('a click moves the current row but does not take focus', (
      tester,
    ) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();

      await tester.tap(find.text('rst'));
      await tester.pump();
      expect(_treeFocused, isFalse);

      await _tabIntoTree(tester);
      expect(_current(tester), 'top.rst');
    });

    testWidgets('only the current row draws a focus ring', (tester) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);

      final rings = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.foregroundDecoration != null)
          .toList();
      expect(rings, hasLength(1));
      final ringRow = find.ancestor(
        of: find.byWidget(rings.single),
        matching: find.byType(ScopeTreeNode),
      );
      expect(tester.widget<ScopeTreeNode>(ringRow).scope.path, 'top.cpu');
    });
  });

  group('SignalTreeRowList — tree keys', () {
    testWidgets('Up and Down move between rows and stop at the ends', (
      tester,
    ) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);

      final visited = <String?>[];
      for (var i = 0; i < 7; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
        visited.add(_current(tester));
      }
      expect(visited, [
        'top.cpu',
        'top.cpu.a',
        'top.cpu.b',
        'top.clk',
        'top.rst',
        'top.rst',
        'top.rst',
      ]);

      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(_current(tester), 'top.clk');
    });

    testWidgets('Home and End go to the first and last rows', (tester) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);

      await _key(tester, LogicalKeyboardKey.end);
      expect(_current(tester), 'top.rst');
      await _key(tester, LogicalKeyboardKey.home);
      expect(_current(tester), 'top');
    });

    testWidgets('Right expands a collapsed scope, then enters it', (
      tester,
    ) async {
      await _pump(tester);
      await _tabIntoTree(tester);
      final expanded = _container(tester).read(expandedScopesProvider);
      expect(expanded, isEmpty);

      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_container(tester).read(expandedScopesProvider), {'top'});
      expect(_current(tester), 'top', reason: 'expanding does not move');

      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_current(tester), 'top.cpu');

      // Right on a signal does nothing (and pans nothing).
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_current(tester), 'top.cpu.a');
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_current(tester), 'top.cpu.a');
    });

    testWidgets('Left collapses an expanded scope, else goes to the parent', (
      tester,
    ) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.end);
      expect(_current(tester), 'top.rst');

      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(_current(tester), 'top');
      expect(
        _container(tester).read(expandedScopesProvider),
        contains('top'),
        reason: 'moving to the parent does not collapse it',
      );

      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        _container(tester).read(expandedScopesProvider),
        isNot(contains('top')),
      );
      expect(_current(tester), 'top');

      // A collapsed root has nowhere to go.
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(_current(tester), 'top');
    });

    testWidgets('Page Down and Page Up move by a screenful', (tester) async {
      tester.view
        ..physicalSize = const Size(600, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, scopes: _wide(100));
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);

      await _key(tester, LogicalKeyboardKey.pageDown);
      final afterPage = _current(tester)!;
      final row = int.parse(afterPage.substring('wide.s'.length));
      expect(row, greaterThan(3), reason: 'more than one row per page');
      await _key(tester, LogicalKeyboardKey.pageUp);
      expect(_current(tester), 'wide');
    });

    testWidgets('keys with a modifier are left for the app', (tester) async {
      final reached = <LogicalKeyboardKey>[];
      await _pump(tester, keysReachingApp: reached);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(reached, contains(LogicalKeyboardKey.arrowDown));
      expect(_current(tester), 'top');

      reached.clear();
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(reached, isEmpty, reason: 'a bare arrow is the tree’s');
    });
  });

  group('SignalTreeRowList — activation', () {
    testWidgets('Enter on a signal adds it, selects it and announces it', (
      tester,
    ) async {
      final recorder = AnnouncementRecorder.attach(tester);
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_current(tester), 'top.cpu.b');

      await _key(tester, LogicalKeyboardKey.enter);

      final container = _container(tester);
      expect(
        container.read(signalGroupsProvider).entries.map((e) => e.signalRef),
        ['ref_top.cpu.b'],
      );
      expect(container.read(selectedVariablesProvider), {'top.cpu.b'});
      expect(recorder.messages, ['b added to the viewer']);
      expect(_treeFocused, isTrue, reason: 'focus stays on the row');
    });

    testWidgets('Space adds too; a held Enter adds once', (tester) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.end);

      await _key(tester, LogicalKeyboardKey.space);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(
        _container(tester).read(signalGroupsProvider).entries,
        hasLength(2),
      );
    });

    testWidgets('Enter and Space on a scope expand and collapse it', (
      tester,
    ) async {
      await _pump(tester);
      await _tabIntoTree(tester);

      await _key(tester, LogicalKeyboardKey.enter);
      expect(_container(tester).read(expandedScopesProvider), {'top'});
      await _key(tester, LogicalKeyboardKey.space);
      expect(_container(tester).read(expandedScopesProvider), isEmpty);
      expect(_container(tester).read(signalGroupsProvider).entries, isEmpty);
    });
  });

  group('SignalTreeRowList — the context menu and selection keys', () {
    Future<void> shiftF10(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    Future<void> shiftArrow(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }

    /// Presses Down inside the open menu until [label] has focus, then
    /// Enter — a menu item chosen without a pointer.
    Future<void> choose(WidgetTester tester, String label) async {
      for (var i = 0; i < 6; i++) {
        if (describeFocus(tester).name == label) break;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      expect(describeFocus(tester).name, label);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Shift+F10 opens the scope menu over the row, on its first item, '
      'and Add All in Scope works from the keyboard',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester);
        await _tabIntoTree(tester);
        final row = tester.getRect(find.byType(ScopeTreeNode));

        await shiftF10(tester);

        final item = find.text('Add All in Scope');
        expect(item, findsOneWidget);
        expect(
          (tester.getRect(item).top - row.top).abs(),
          lessThan(kSignalTreeRowHeight),
          reason: 'the menu opens at the row, not at the window corner',
        );
        expectFocusAnnounced(tester, named: 'Add All in Scope');

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.text('Add All in Scope'), findsNothing);
        expect(
          _container(tester).read(signalGroupsProvider).entries,
          hasLength(4),
        );
        expect(_treeFocused, isTrue, reason: 'focus comes back to the tree');
        expect(_current(tester), 'top');
        handle.dispose();
      },
    );

    testWidgets(
      'the Menu key opens a signal menu; Copy Signal Path works from the '
      'keyboard',
      (tester) async {
        final handle = tester.ensureSemantics();
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _pump(tester);
        _expandAll(tester);
        await tester.pump();
        await _tabIntoTree(tester);
        await _key(tester, LogicalKeyboardKey.end);

        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pumpAndSettle();
        expect(find.text('Copy Signal Path'), findsOneWidget);
        expectFocusAnnounced(tester, named: 'Add to Viewer');

        await choose(tester, 'Copy Signal Path');

        expect(copied, 'top.rst');
        expect(_treeFocused, isTrue);
        expect(_current(tester), 'top.rst');
        handle.dispose();
      },
    );

    testWidgets('Escape closes the menu and focus returns to the same row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);

      await shiftF10(tester);
      expect(find.byType(PopupMenuItem<String>), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(_treeFocused, isTrue);
      expect(_current(tester), 'top.cpu.a');
      expectFocusAnnounced(tester, named: 'a');
      expect(_container(tester).read(signalGroupsProvider).entries, isEmpty);
      handle.dispose();
    });

    testWidgets(
      'Shift+Down and Shift+Up select a range and Ctrl+Space toggles, '
      'without adding',
      (tester) async {
        await _pump(tester);
        _expandAll(tester);
        await tester.pump();
        await _tabIntoTree(tester);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(_current(tester), 'top.cpu.a');
        final container = _container(tester);

        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
        expect(_current(tester), 'top.cpu.b');
        expect(container.read(selectedVariablesProvider), {
          'top.cpu.a',
          'top.cpu.b',
        });

        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
        expect(_current(tester), 'top.rst');
        expect(container.read(selectedVariablesProvider), {
          'top.cpu.a',
          'top.cpu.b',
          'top.clk',
          'top.rst',
        });

        await shiftArrow(tester, LogicalKeyboardKey.arrowUp);
        expect(container.read(selectedVariablesProvider), {
          'top.cpu.a',
          'top.cpu.b',
          'top.clk',
        });

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          container.read(selectedVariablesProvider),
          isNot(contains('top.clk')),
        );
        expect(container.read(signalGroupsProvider).entries, isEmpty);
      },
    );

    testWidgets('the bulk actions work from the keyboard', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);

      await shiftF10(tester);
      await choose(tester, 'Add 2 Selected to Viewer');
      expect(
        _container(tester)
            .read(signalGroupsProvider)
            .entries
            .map(
              (e) => e.signalRef,
            ),
        ['ref_top.cpu.a', 'ref_top.cpu.b'],
      );
      expect(_treeFocused, isTrue);

      await shiftF10(tester);
      await choose(tester, 'Apply Decoder to Selection…');
      expect(find.byType(Dialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(_treeFocused, isTrue, reason: 'back on the row after the dialog');
      expect(_current(tester), 'top.cpu.b');
      handle.dispose();
    });
  });

  group('SignalTreeRowList — the app keymap', () {
    testWidgets(
      'the focused tree keeps arrows, Home, End and Space from the viewer',
      (tester) async {
        final fired = <ShortcutAction>[];
        await _pump(
          tester,
          handlers: {
            for (final action in const [
              ShortcutAction.panLeftSmall,
              ShortcutAction.panRightSmall,
              ShortcutAction.jumpToStart,
              ShortcutAction.jumpToEnd,
              ShortcutAction.togglePlayback,
            ])
              action: () => fired.add(action),
          },
        );
        _expandAll(tester);
        await tester.pump();

        // Control: with focus outside the tree the viewer's bindings fire, so
        // the assertion below is not vacuous.
        FocusManager.instance.rootScope.descendants
            .firstWhere((n) => n.debugLabel == 'Elsewhere')
            .requestFocus();
        await tester.pump();
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        await _key(tester, LogicalKeyboardKey.home);
        expect(fired, [
          ShortcutAction.panLeftSmall,
          ShortcutAction.jumpToStart,
        ]);
        fired.clear();

        await _tabIntoTree(tester);
        for (final key in const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.home,
          LogicalKeyboardKey.end,
          LogicalKeyboardKey.space,
        ]) {
          await _key(tester, key);
        }

        expect(fired, isEmpty);
      },
    );
  });

  group('SignalTreeRowList — the lazy list', () {
    testWidgets('End scrolls the last row into view', (tester) async {
      await _pump(tester, scopes: _wide(300));
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);

      await _key(tester, LogicalKeyboardKey.end);

      expect(_current(tester), 'wide.s299');
      final list = tester.getRect(find.byType(SignalTreeRowList));
      final row = tester.getRect(find.text('s299'));
      expect(
        list.contains(row.topLeft) && list.contains(row.bottomLeft),
        isTrue,
      );
    });

    testWidgets(
      'focus stays on the tree when its row scrolls out of the build window',
      (tester) async {
        await _pump(tester, scopes: _wide(300));
        _expandAll(tester);
        await tester.pump();
        await _tabIntoTree(tester);
        await _key(tester, LogicalKeyboardKey.end);

        // Scroll the way a mouse wheel would, far enough that the current row
        // is disposed.
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(SignalTreeRowList),
            matching: find.byType(Scrollable),
          ),
        );
        scrollable.position.jumpTo(0);
        await tester.pump();
        expect(find.text('s299'), findsNothing);
        expect(_treeFocused, isTrue);

        await _key(tester, LogicalKeyboardKey.arrowUp);

        expect(_current(tester), 'wide.s298');
        expect(find.text('s298'), findsOneWidget);
      },
    );

    testWidgets('Collapse All leaves the keyboard on the scope it closed', (
      tester,
    ) async {
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();
      await _tabIntoTree(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_current(tester), 'top.cpu.a');

      _container(tester).read(expandedScopesProvider.notifier).collapseAll();
      await tester.pump();

      expect(_current(tester), 'top');
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_current(tester), 'top', reason: 'the only row left');
    });
  });

  group('SignalTreeRowList — what a screen reader hears', () {
    testWidgets('rows announce name, state, width and selection', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tabIntoTree(tester);

      final stops = <FocusStop>[describeFocus(tester)];
      // The instructions are spoken as the container focus enters.
      expect(
        stops.single.line,
        endsWith(
          '[Signal hierarchy. Up and Down move between rows, Right and Left '
          'expand and collapse scopes, and Enter adds a signal to the viewer. '
          'grouping] top button collapsed 4 signals',
        ),
      );

      Future<String> press(LogicalKeyboardKey key) async {
        await _key(tester, key);
        final stop = describeFocus(tester);
        stops.add(stop);
        return stop.line.replaceFirst(RegExp(r'^(\[[^\]]*\] )+'), '');
      }

      expect(
        await press(LogicalKeyboardKey.arrowRight),
        'top button expanded 4 signals',
      );
      expect(
        await press(LogicalKeyboardKey.arrowDown),
        'cpu button collapsed 2 signals',
      );
      await press(LogicalKeyboardKey.enter);
      expect(await press(LogicalKeyboardKey.arrowDown), 'a button');
      expect(await press(LogicalKeyboardKey.arrowDown), 'b, [7:0] button');
      expect(
        await press(LogicalKeyboardKey.enter),
        'b, [7:0] button selected',
      );

      expectCleanFocusWalk(
        FocusWalk(
          stops: stops,
          cycled: true,
          reverse: false,
          offscreen: const {},
        ),
        context: 'signal tree arrow keys',
      );
      handle.dispose();
    });

    testWidgets('a screen reader focusing a row puts the keyboard there', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      _expandAll(tester);
      await tester.pump();

      tester.semantics.performAction(
        find.semantics.byLabel('clk'),
        SemanticsAction.focus,
      );
      await tester.pump();

      expect(_treeFocused, isTrue);
      expect(_current(tester), 'top.clk');
      expectFocusAnnounced(tester, named: 'clk');
      handle.dispose();
    });

    testWidgets('touch platforms get no keyboard instructions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hierarchyProvider.overrideWith((_) => AsyncData(_tree())),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(body: SignalTreePanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel(RegExp('Up and Down')), findsNothing);
      expect(find.semantics.byLabel('top'), findsOneWidget);
      handle.dispose();
    });
  });
}
