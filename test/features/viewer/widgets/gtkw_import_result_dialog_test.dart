// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/features/viewer/widgets/gtkw_import_result_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/session/gtkw_import_service.dart';

// ── helpers ────────────────────────────────────────────────────────────────

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Widget child, {Locale? locale}) => MaterialApp(
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  locale: locale,
  home: Scaffold(body: child),
);

GtkwImportResult _result({
  int matched = 3,
  int groups = 1,
  int markers = 2,
  List<String> unmatched = const [],
  List<GtkwFilterIssue> filterIssues = const [],
}) => GtkwImportResult(
  sessionState: const SessionState(),
  matchedSignalCount: matched,
  groupCount: groups,
  markerCount: markers,
  unmatchedSignalPaths: unmatched,
  filterIssues: filterIssues,
);

const _everyFilterIssue = [
  GtkwFilterIssue(
    signalPath: 'top.state[2:0]',
    filterPath: '/home/u/filters/states.txt',
    kind: GtkwFilterIssueKind.missingFile,
  ),
  GtkwFilterIssue(
    signalPath: 'top.opcode[6:0]',
    filterPath: '/home/u/bin/decode',
    kind: GtkwFilterIssueKind.process,
  ),
  GtkwFilterIssue(
    signalPath: 'top.bus[31:0]',
    filterPath: '/home/u/bin/txn',
    kind: GtkwFilterIssueKind.transaction,
  ),
];

Future<void> _showDialog(WidgetTester tester, GtkwImportResult result) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => GtkwImportResultDialog.show(context, result: result),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  group('GtkwImportResultDialog', () {
    for (final locale in _locales) {
      testWidgets('locale sweep — renders in $locale without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            GtkwImportResultDialog(
              result: _result(
                unmatched: const ['top.missing'],
                filterIssues: _everyFilterIssue,
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows dialog title', (tester) async {
      await _showDialog(tester, _result());
      expect(find.text('GTKWave Import Complete'), findsOneWidget);
    });

    testWidgets('shows signal count summary row', (tester) async {
      await _showDialog(tester, _result(matched: 5));
      expect(find.textContaining('5 signals imported'), findsOneWidget);
    });

    testWidgets('shows group count summary row', (tester) async {
      await _showDialog(tester, _result(groups: 3));
      expect(find.textContaining('3 groups'), findsOneWidget);
    });

    testWidgets('shows marker count summary row', (tester) async {
      await _showDialog(tester, _result(markers: 4));
      expect(find.textContaining('4 markers'), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      await _showDialog(tester, _result());
      expect(find.text('GTKWave Import Complete'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('GTKWave Import Complete'), findsNothing);
    });

    testWidgets('unmatched section hidden when all signals matched', (
      tester,
    ) async {
      await _showDialog(tester, _result());
      expect(find.textContaining('not found'), findsNothing);
    });

    testWidgets('unmatched section shown when there are unmatched signals', (
      tester,
    ) async {
      await _showDialog(
        tester,
        _result(unmatched: const ['top.missing', 'top.bogus']),
      );
      expect(
        find.textContaining('not found in waveform (2)'),
        findsOneWidget,
      );
    });

    testWidgets('unmatched signal paths are listed', (tester) async {
      await _showDialog(
        tester,
        _result(unmatched: const ['top.missing', 'tb.dut.bad']),
      );
      expect(find.text('top.missing'), findsOneWidget);
      expect(find.text('tb.dut.bad'), findsOneWidget);
    });

    testWidgets('filter section hidden when every filter applied', (
      tester,
    ) async {
      await _showDialog(tester, _result());
      expect(find.textContaining('Filters not applied'), findsNothing);
    });

    testWidgets('filters not applied are listed with the reason', (
      tester,
    ) async {
      await _showDialog(tester, _result(filterIssues: _everyFilterIssue));
      expect(find.text('Filters not applied (3):'), findsOneWidget);
      expect(
        find.text(
          'top.state[2:0]: filter file not found: /home/u/filters/states.txt',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'top.opcode[6:0]: filter process not imported: /home/u/bin/decode',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'top.bus[31:0]: transaction filter not imported: /home/u/bin/txn',
        ),
        findsOneWidget,
      );
    });

    testWidgets('unmatched signals and filter issues show together', (
      tester,
    ) async {
      await _showDialog(
        tester,
        _result(
          unmatched: const ['top.missing'],
          filterIssues: _everyFilterIssue.take(1).toList(),
        ),
      );
      expect(find.textContaining('not found in waveform (1)'), findsOneWidget);
      expect(find.text('Filters not applied (1):'), findsOneWidget);
    });

    testWidgets('zero counts displayed correctly', (tester) async {
      await _showDialog(
        tester,
        _result(matched: 0, groups: 0, markers: 0),
      );
      expect(find.textContaining('0 signals imported'), findsOneWidget);
      expect(find.textContaining('0 groups'), findsOneWidget);
      expect(find.textContaining('0 markers'), findsOneWidget);
    });

    testWidgets('GtkwImportResultDialog.show is a static convenience method', (
      tester,
    ) async {
      // Verify show() works the same as directly constructing the widget.
      await _showDialog(tester, _result(matched: 7, groups: 2, markers: 1));
      expect(find.textContaining('7 signals imported'), findsOneWidget);
    });
  });
}
