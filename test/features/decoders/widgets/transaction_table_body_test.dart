// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The transaction table from the keyboard and a screen reader. Before, a
// DataTable put a focusable ink well in every cell: a keyboard walked the
// report cell by cell, each stop a bare value, and decoder labels such as
// "R 0x08 → 0xFF" were read with the arrow as "?".

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:wavecrux/core/utils/speakable_text.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_body.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

TableTransaction _row(
  int index,
  String label, {
  bool isError = false,
  String? errorMessage,
  Map<String, String> fields = const {},
}) => TableTransaction(
  rowIndex: index,
  decoderInstanceId: 'd1',
  decoderDisplayName: 'APB #1',
  transaction: DecodedTransaction(
    startTime: index * 10,
    endTime: index * 10 + 5,
    label: label,
    fields: fields,
    isError: isError,
    errorMessage: errorMessage,
  ),
);

List<TableTransaction> _rows(int count) => [
  for (var i = 1; i <= count; i++)
    _row(i, 'R 0x$i → 0xFF', fields: {'address': '0x$i', 'data': '0xFF'}),
];

class _Harness {
  final activated = <TableTransaction>[];
  final sorted = <(TransactionSortColumn, bool)>[];
  final horizontal = ScrollController();
  final rows = ValueNotifier<List<TableTransaction>>(_rows(4));
  (Object, String)? selected;
  TransactionTableFilter filter = const TransactionTableFilter();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  _Harness? harness,
  Locale? locale,
  Map<ShortcutAction, VoidCallback> handlers = const {},
  Size size = const Size(900, 400),
  List<LogicalKeyboardKey>? keysReachingApp,
}) async {
  final h = harness ?? _Harness();
  addTearDown(h.horizontal.dispose);
  addTearDown(h.rows.dispose);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget body = StatefulBuilder(
    builder: (context, setState) => ValueListenableBuilder(
      valueListenable: h.rows,
      builder: (context, rows, _) => TransactionTableBody(
        rows: rows,
        fieldKeys: const ['address', 'data'],
        filter: h.filter,
        selectedRow: h.selected,
        horizontalScrollController: h.horizontal,
        onSort: (column, {required ascending}) =>
            h.sorted.add((column, ascending)),
        onRowTap: (row) => setState(() {
          h.activated.add(row);
          h.selected = (row.transaction, row.decoderInstanceId);
        }),
      ),
    ),
  );
  if (keysReachingApp != null) {
    body = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) keysReachingApp.add(event.logicalKey);
        return KeyEventResult.ignored;
      },
      child: body,
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: ShortcutManagerWidget(
          handlers: handlers,
          child: Scaffold(
            body: Column(
              children: [
                const Focus(
                  debugLabel: 'Before',
                  child: SizedBox(height: 20, width: 20),
                ),
                Expanded(child: body),
                const Focus(
                  debugLabel: 'After',
                  child: SizedBox(height: 20, width: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

bool get _rowsFocused =>
    FocusManager.instance.primaryFocus?.debugLabel == 'Transaction rows';

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// Tabs from the start of the window until the rows hold focus.
Future<int> _tabToRows(WidgetTester tester) async {
  FocusManager.instance.rootScope.descendants
      .firstWhere((n) => n.debugLabel == 'Before')
      .requestFocus();
  await tester.pump();
  for (var i = 1; i <= 30; i++) {
    await _key(tester, LogicalKeyboardKey.tab);
    if (_rowsFocused) return i;
  }
  fail('Tab never reached the rows');
}

void main() {
  group('TransactionTableBody — locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('keyboard use renders in $locale without exceptions', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, locale: locale);
        await _tabToRows(tester);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        await _key(tester, LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(kUnspeakableGlyph.hasMatch(describeFocus(tester).name), isFalse);
        handle.dispose();
      });
    }
  });

  group('TransactionTableBody — one Tab stop', () {
    testWidgets('the headers come first, then every row is a single stop', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      // Before, the five sortable headers, then 4 x 7 cells.
      final tabs = await _tabToRows(tester);
      expect(tabs, 6, reason: 'five header stops, then the rows');
      expect(describeFocus(tester).name, startsWith('1, APB #1'));

      await _key(tester, LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'After');
      handle.dispose();
    });

    testWidgets('Shift+Tab back returns to the row the keyboard was on', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tabToRows(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowDown);

      await _key(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(_rowsFocused, isTrue);
      expect(describeFocus(tester).name, startsWith('3, APB #1'));
      handle.dispose();
    });

    testWidgets('headers are named buttons with the sort state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = _Harness()
        ..filter = const TransactionTableFilter(
          sortColumn: TransactionSortColumn.startTime,
          sortAscending: false,
        );
      await _pump(tester, harness: h);
      FocusManager.instance.rootScope.descendants
          .firstWhere((n) => n.debugLabel == 'Before')
          .requestFocus();
      await tester.pump();

      final lines = <String>[];
      for (var i = 0; i < 5; i++) {
        await _key(tester, LogicalKeyboardKey.tab);
        lines.add(
          describeFocus(
            tester,
          ).line.replaceFirst(RegExp(r'^(\[[^\]]*\] )+'), ''),
        );
      }
      expect(lines, [
        '# button',
        'Decoder button',
        'Start button sorted descending',
        'End button',
        'Label button',
      ]);

      // Enter on a header sorts; it is not a row activation.
      await _key(tester, LogicalKeyboardKey.enter);
      expect(h.sorted, [(TransactionSortColumn.label, true)]);
      expect(h.activated, isEmpty);
      handle.dispose();
    });
  });

  group('TransactionTableBody — row keys', () {
    testWidgets('Up, Down, Home and End move between rows', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tabToRows(tester);

      String current() => describeFocus(tester).name.split(',').first;
      final visited = <String>[];
      for (final key in const [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.arrowUp,
      ]) {
        await _key(tester, key);
        visited.add(current());
      }
      expect(visited, ['2', '3', '2', '4', '4', '1', '1']);
      handle.dispose();
    });

    testWidgets('Page Down and Page Up move a screenful and scroll', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = _Harness()..rows.value = _rows(60);
      await _pump(tester, harness: h, size: const Size(900, 300));
      await _tabToRows(tester);

      await _key(tester, LogicalKeyboardKey.pageDown);
      final afterPage = int.parse(describeFocus(tester).name.split(',').first);
      expect(afterPage, greaterThan(3));
      expect(find.text('$afterPage').hitTestable(), findsOneWidget);

      await _key(tester, LogicalKeyboardKey.end);
      expect(describeFocus(tester).name, startsWith('60,'));
      expect(find.text('60').hitTestable(), findsOneWidget);

      await _key(tester, LogicalKeyboardKey.pageUp);
      expect(
        int.parse(describeFocus(tester).name.split(',').first),
        lessThan(60),
      );
      handle.dispose();
    });

    testWidgets('Enter and Space do what a click does; a held Enter once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await _pump(tester);
      await _tabToRows(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);

      await _key(tester, LogicalKeyboardKey.enter);
      expect(h.activated.map((r) => r.rowIndex), [2]);
      expect(describeFocus(tester).line, endsWith('button selected'));

      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.space);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.activated.map((r) => r.rowIndex), [2, 3, 3]);
      expect(_rowsFocused, isTrue);
      handle.dispose();
    });

    testWidgets('Left and Right scroll the columns sideways', (tester) async {
      final h = _Harness()
        ..rows.value = [
          for (var i = 1; i <= 3; i++)
            _row(i, 'R ${'0xABCDEF01 ' * 12}', fields: {'address': 'x'}),
        ];
      await _pump(tester, harness: h, size: const Size(500, 400));
      await _tabToRows(tester);
      // Tabbing through the wide Label header scrolled it into view.
      h.horizontal.jumpTo(0);
      await tester.pump();

      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(h.horizontal.offset, 96);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.horizontal.offset, 48);
    });

    testWidgets('the app keymap does not take the rows keys', (tester) async {
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

      // Control: from outside the table the viewer's bindings fire.
      FocusManager.instance.rootScope.descendants
          .firstWhere((n) => n.debugLabel == 'After')
          .requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      await _key(tester, LogicalKeyboardKey.home);
      expect(fired, [ShortcutAction.panLeftSmall, ShortcutAction.jumpToStart]);
      fired.clear();

      await _tabToRows(tester);
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
    });

    testWidgets('keys with a modifier are left for the app', (tester) async {
      final reached = <LogicalKeyboardKey>[];
      await _pump(tester, keysReachingApp: reached);
      await _tabToRows(tester);
      reached.clear();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(reached, contains(LogicalKeyboardKey.arrowUp));

      reached.clear();
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(reached, isEmpty);
    });
  });

  group('TransactionTableBody — pointer', () {
    testWidgets('a click anywhere on a row activates that row', (
      tester,
    ) async {
      final h = await _pump(tester);

      await tester.tap(find.text('R 0x3 → 0xFF'));
      await tester.pump();
      await tester.tap(find.text('APB #1').first);
      await tester.pump();
      await tester.tap(find.text('20'));
      await tester.pump();

      expect(h.activated.map((r) => r.rowIndex), [3, 1, 2]);
      expect(_rowsFocused, isFalse, reason: 'a click does not take focus');
    });

    testWidgets('a clicked row is where the keyboard picks up', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await tester.tap(find.text('R 0x3 → 0xFF'));
      await tester.pump();

      await _tabToRows(tester);
      expect(describeFocus(tester).name, startsWith('3, APB #1'));
      handle.dispose();
    });

    testWidgets('a header click still sorts and activates no row', (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(h.sorted, [(TransactionSortColumn.startTime, true)]);
      expect(h.activated, isEmpty);
    });
  });

  group('TransactionTableBody — what a screen reader hears', () {
    testWidgets('each row is one sentence; errors say so', (tester) async {
      final handle = tester.ensureSemantics();
      final h = _Harness()
        ..rows.value = [
          _row(1, 'W 0x4 = 0xDEADBEEF'),
          _row(
            2,
            'R 0x8 → 0x12 [SLVERR]',
            isError: true,
            errorMessage: 'Slave error',
          ),
          _row(3, 'Frame ─ truncated', isError: true),
        ];
      await _pump(tester, harness: h);

      expect(
        find.semantics.byLabel('1, APB #1, 10 to 15, W 0x4 = 0xDEADBEEF'),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel(
          '2, APB #1, 20 to 25, R 0x8 to 0x12 [SLVERR], error: Slave error',
        ),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel('3, APB #1, 30 to 35, Frame truncated, error'),
        findsOneWidget,
      );
      // The cells are not read a second time on their own.
      expect(find.semantics.byLabel('0xDEADBEEF'), findsNothing);
      expect(find.semantics.byLabel('APB #1'), findsNothing);
      handle.dispose();
    });

    testWidgets('no row label reaches semantics with an unspeakable glyph', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final glyphs = [
        for (var rune = 0x2190; rune <= 0x21FF; rune += 7)
          String.fromCharCode(rune),
        '─',
        '▲',
        '▼',
        '■',
        '⟶',
        '⤳',
        '',
      ];
      final h = _Harness()
        ..rows.value = [
          for (var i = 0; i < glyphs.length; i++)
            _row(
              i + 1,
              'src${glyphs[i]}dst',
              isError: i.isEven,
              errorMessage: i.isEven ? 'bad ${glyphs[i]} frame' : null,
            ),
        ];
      await _pump(tester, harness: h, size: const Size(900, 2400));

      final offenders = <String>[];
      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        for (final text in [data.label, data.value, data.tooltip]) {
          if (kUnspeakableGlyph.hasMatch(text)) offenders.add(text);
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      for (final view in tester.binding.renderViews) {
        final root = view.owner?.semanticsOwner?.rootSemanticsNode;
        if (root != null) visit(root);
      }
      expect(find.text('src→dst'), findsNothing, reason: 'fixture sanity');
      expect(find.text('src${glyphs.first}dst'), findsOneWidget);
      expect(offenders, isEmpty);
      handle.dispose();
    });

    testWidgets('a screen reader focusing a row puts the keyboard there', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      tester.semantics.performAction(
        find.semantics.byLabel('3, APB #1, 30 to 35, R 0x3 to 0xFF'),
        SemanticsAction.focus,
      );
      await tester.pump();

      expect(_rowsFocused, isTrue);
      expectFocusAnnounced(tester, named: '3, APB #1');
      handle.dispose();
    });

    testWidgets('only the focused row is tinted as focused', (tester) async {
      await _pump(tester);
      Color? colorOf(int index) => tester
          .widget<DataTable>(find.byType(DataTable))
          .rows[index]
          .color
          ?.resolve(const {});
      expect(colorOf(1), isNull);

      await _tabToRows(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(colorOf(1), isNotNull);
      expect(colorOf(0), isNull);
      expect(colorOf(2), isNull);
    });

    testWidgets('the keyboard stays on its row when the rows are re-sorted', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = _Harness();
      await _pump(tester, harness: h);
      await _tabToRows(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(describeFocus(tester).name, startsWith('2, APB #1'));

      h.rows.value = h.rows.value.reversed.toList();
      await tester.pump();

      expect(_rowsFocused, isTrue);
      expect(describeFocus(tester).name, startsWith('2, APB #1'));
      handle.dispose();
    });
  });
}
