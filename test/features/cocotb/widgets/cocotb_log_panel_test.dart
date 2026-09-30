// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_log_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

CocotbLogEntry _e({
  required int line,
  required CocotbLogSeverity severity,
  required String message,
  String? testName,
  int? ticks,
  bool isTestStart = false,
  bool isTestResult = false,
  bool? testPassed,
}) => CocotbLogEntry(
  severity: severity,
  loggerName: 'cocotb.test_basic',
  message: message,
  lineNumber: line,
  simTimeTicks: ticks,
  testName: testName,
  isTestStart: isTestStart,
  isTestResult: isTestResult,
  testPassed: testPassed,
);

CocotbLogFile _file(List<CocotbLogEntry> entries, {List<String>? testNames}) =>
    CocotbLogFile(
      filePath: '/tmp/run.log',
      entries: List.unmodifiable(entries),
      testNames: List.unmodifiable(testNames ?? const <String>[]),
      severityCounts: const {
        CocotbLogSeverity.info: 1,
        CocotbLogSeverity.error: 1,
      },
      testResults: const {},
    );

class _PreloadedLog extends CocotbLog {
  _PreloadedLog(this._initial);
  final CocotbLogFile? _initial;
  @override
  CocotbLogFile? build() => _initial;
}

Widget _wrap({
  CocotbLogFile? file,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      cocotbLogProvider.overrideWith(() => _PreloadedLog(file)),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(body: CocotbLogPanel()),
    ),
  );
}

void main() {
  group('CocotbLogPanel', () {
    testWidgets('locale sweep renders without exceptions', (tester) async {
      const locales = ['en', 'zh_CN', 'ja', 'ko'];
      final file = _file([
        _e(
          line: 1,
          severity: CocotbLogSeverity.info,
          message: 'Reset',
          ticks: 100,
        ),
        _e(
          line: 2,
          severity: CocotbLogSeverity.error,
          message: 'Bad',
          ticks: 200,
        ),
      ]);
      for (final tag in locales) {
        final parts = tag.split('_');
        final locale = parts.length == 2
            ? Locale(parts[0], parts[1])
            : Locale(parts[0]);
        await tester.pumpWidget(_wrap(file: file, locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'locale $tag');
      }
    });

    testWidgets('shows empty state when no log loaded', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.cocotbLogEmpty), findsOneWidget);
    });

    testWidgets('shows entry count badge with full count', (tester) async {
      final file = _file([
        _e(line: 1, severity: CocotbLogSeverity.info, message: 'a', ticks: 10),
        _e(line: 2, severity: CocotbLogSeverity.error, message: 'b', ticks: 20),
      ]);
      await tester.pumpWidget(_wrap(file: file));
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.cocotbLogEntryCount(2)), findsOneWidget);
    });

    testWidgets('shows panel title', (tester) async {
      final file = _file([
        _e(line: 1, severity: CocotbLogSeverity.info, message: 'x', ticks: 1),
      ]);
      await tester.pumpWidget(_wrap(file: file));
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.cocotbLogPanelTitle), findsOneWidget);
    });

    testWidgets('renders entry messages', (tester) async {
      final file = _file([
        _e(
          line: 1,
          severity: CocotbLogSeverity.info,
          message: 'Reset done',
          ticks: 100,
        ),
      ]);
      await tester.pumpWidget(_wrap(file: file));
      await tester.pumpAndSettle();
      expect(find.text('Reset done'), findsOneWidget);
    });

    testWidgets('clear button unloads the log', (tester) async {
      final file = _file([
        _e(line: 1, severity: CocotbLogSeverity.info, message: 'x', ticks: 1),
      ]);
      await tester.pumpWidget(_wrap(file: file));
      await tester.pumpAndSettle();
      // Find and tap the clear (close) icon button.
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.cocotbLogEmpty), findsOneWidget);
    });

    group('clearing the keyword filter', () {
      final file = _file([
        _e(line: 1, severity: CocotbLogSeverity.info, message: 'alpha'),
        _e(line: 2, severity: CocotbLogSeverity.error, message: 'beta'),
      ]);

      // One keystroke's worth of text sits in the debounce while the user
      // clears. Before the fix the header's clear-filter button reset the
      // provider but left that timer armed and the text in the field, so the
      // keystroke landed 300 ms after the clear and filtered the log again.
      testWidgets(
        'the header clear-filter button drops a keystroke still in the '
        'debounce and empties the field',
        (tester) async {
          await tester.pumpWidget(_wrap(file: file));
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(
            tester.element(find.byType(CocotbLogPanel)),
          );

          await tester.enterText(find.byType(TextField), 'alp');
          await tester.pump(const Duration(milliseconds: 350));
          expect(container.read(cocotbFilterProvider).keywordFilter, 'alp');
          expect(find.text('beta'), findsNothing);

          // A further keystroke, then Clear before its debounce elapses.
          await tester.enterText(find.byType(TextField), 'alph');
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.byIcon(Icons.filter_alt_off));
          await tester.pump(const Duration(milliseconds: 400));

          expect(container.read(cocotbFilterProvider).keywordFilter, isEmpty);
          expect(find.text('alpha'), findsOneWidget);
          expect(find.text('beta'), findsOneWidget);
          final field = tester.widget<TextField>(find.byType(TextField));
          expect(field.controller!.text, isEmpty);
        },
      );

      testWidgets(
        "the field's own clear button applies at once and drops a pending "
        'keystroke',
        (tester) async {
          await tester.pumpWidget(_wrap(file: file));
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(
            tester.element(find.byType(CocotbLogPanel)),
          );

          await tester.enterText(find.byType(TextField), 'alp');
          await tester.pump(const Duration(milliseconds: 350));
          await tester.enterText(find.byType(TextField), 'alph');
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.byIcon(Icons.clear));
          await tester.pump();

          expect(
            container.read(cocotbFilterProvider).keywordFilter,
            isEmpty,
            reason: 'a clear is not typing; it has no burst to wait out',
          );
          await tester.pump(const Duration(milliseconds: 400));
          expect(container.read(cocotbFilterProvider).keywordFilter, isEmpty);
          expect(find.text('beta'), findsOneWidget);
        },
      );
    });
  });
}
