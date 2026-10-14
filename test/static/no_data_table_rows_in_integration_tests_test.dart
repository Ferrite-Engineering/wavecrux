// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: integration tests must not count transaction-table rows by
/// reading `DataTable.rows`.
///
/// The transaction table's `DataTable` holds only the header row. The rows
/// are in a lazy fixed-extent list that builds only the ones on screen, so
/// `tester.widget<DataTable>(...).rows` is always empty and any check on it
/// fails with `Actual: <0>` while the decoders are working. The full
/// filtered count comes from `transactionTableRowCount(tester)` in
/// `integration_test/helpers/app_driver.dart`.
///
/// This test fails if a `.rows` read on a typed `DataTable` lookup appears
/// anywhere under `integration_test/`, whether chained directly onto the
/// lookup (over any number of line breaks) or read from a variable the
/// lookup was assigned to. Comments are exempt so a doc comment may still
/// name the anti-pattern.
void main() {
  group('findDataTableRowReads', () {
    test('flags a chained read', () {
      expect(
        findDataTableRowReads(
          'expect(tester.widget<DataTable>(finder).rows.length, 3);',
        ),
        hasLength(1),
      );
    });

    test('flags a chained read across line breaks', () {
      const source = '''
final n = tester
    .widget<DataTable>(
      find.descendant(
        of: find.byType(TransactionTablePanel),
        matching: find.byType(DataTable),
      ),
    )
    .rows
    .length;
''';
      expect(findDataTableRowReads(source), hasLength(1));
    });

    test('flags widgetList and a selector before .rows', () {
      expect(
        findDataTableRowReads(
          'final n = tester.widgetList<DataTable>(f).first.rows.length;',
        ),
        hasLength(1),
      );
      expect(
        findDataTableRowReads(
          'final n = tester.firstWidget<DataTable>(f).rows.length;',
        ),
        hasLength(1),
      );
    });

    test('flags the shape the captured tests used', () {
      const source = '''
void _assertAtLeastOneRow(WidgetTester tester) {
  final dataTable = tester.widget<DataTable>(
    find.descendant(
      of: find.byType(TransactionTablePanel),
      matching: find.byType(DataTable),
    ),
  );
  expect(dataTable.rows.length, greaterThanOrEqualTo(1));
}
''';
      expect(findDataTableRowReads(source), hasLength(1));
    });

    test('flags a read from an assigned variable on a later statement', () {
      const source = '''
final table = tester.widget<DataTable>(finder);
await tester.pump();
expect(table.rows, isNotEmpty);
''';
      expect(findDataTableRowReads(source), hasLength(1));
    });

    test('ignores comments', () {
      const source = '''
// tester.widget<DataTable>(finder).rows.length
/// final t = tester.widget<DataTable>(finder); t.rows
/* tester.widget<DataTable>(finder).rows */
''';
      expect(findDataTableRowReads(source), isEmpty);
    });

    test('ignores the supported helper and other .rows reads', () {
      const source = '''
expect(transactionTableRowCount(tester), 3);
expect(tester.widget<TransactionTableBody>(f).rows.length, 3);
expect(find.byType(DataTable), findsNothing);
final other = tester.widget<Table>(f);
expect(other.children, isEmpty);
''';
      expect(findDataTableRowReads(source), isEmpty);
    });

    test('reports the line of the read', () {
      const source = 'a;\nb;\nfinal n = tester.widget<DataTable>(f).rows;\n';
      expect(findDataTableRowReads(source).single, 3);
    });
  });

  test('no integration test reads DataTable.rows', () {
    final dir = Directory('integration_test');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'expected integration_test/ at repo root',
    );

    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in findDataTableRowReads(entity.readAsStringSync())) {
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The transaction table builds only the rows on screen, so its '
          'DataTable.rows is always empty. Count rows with '
          'transactionTableRowCount(tester) from '
          'integration_test/helpers/app_driver.dart. Offenders:\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}

/// The 1-based lines of every `.rows` read on a typed `DataTable` lookup in
/// [source], comments excluded.
List<int> findDataTableRowReads(String source) {
  final code = _blankComments(source);
  final lines = <int>{};

  // A lookup with `.rows` chained straight onto it, possibly through
  // `.first` / `.last` / `.single` / `.elementAt(n)` and over line breaks.
  final chained = RegExp(
    r'<DataTable>\s*\([^;]*?\)'
    r'(?:\s*\.\s*(?:first|last|single|elementAt\s*\([^)]*\)))*'
    r'\s*\.\s*rows\b',
  );
  for (final match in chained.allMatches(code)) {
    lines.add(_lineOf(code, match.start));
  }

  // A lookup assigned to a variable whose `.rows` is read later.
  final assigned = RegExp(
    r'\b(?:final|var|DataTable)\s+(\w+)\s*=\s*[^;]*?<DataTable>[^;]*;',
  );
  for (final match in assigned.allMatches(code)) {
    final name = RegExp.escape(match.group(1)!);
    final read = RegExp('\\b$name\\s*\\.\\s*rows\\b');
    if (read.hasMatch(code.substring(match.end))) {
      lines.add(_lineOf(code, match.start));
    }
  }

  return lines.toList()..sort();
}

/// [source] with comments replaced by spaces, so offsets and line numbers
/// still match the original.
String _blankComments(String source) {
  String blank(Match m) => m.group(0)!.replaceAll(RegExp(r'[^\n]'), ' ');
  return source
      .replaceAllMapped(RegExp(r'/\*[\s\S]*?\*/'), blank)
      .replaceAllMapped(RegExp(r'//[^\n]*'), blank);
}

int _lineOf(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;
