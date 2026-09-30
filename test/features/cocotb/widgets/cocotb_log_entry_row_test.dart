// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_log_entry_row.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

CocotbLogEntry _entry({
  CocotbLogSeverity severity = CocotbLogSeverity.info,
  String message = 'hello',
  int? ticks = 100,
  bool isTestStart = false,
  bool isTestResult = false,
  bool? testPassed,
}) => CocotbLogEntry(
  severity: severity,
  loggerName: 'cocotb.test_basic',
  message: message,
  lineNumber: 1,
  simTimeTicks: ticks,
  isTestStart: isTestStart,
  isTestResult: isTestResult,
  testPassed: testPassed,
);

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('CocotbLogEntryRow', () {
    testWidgets('locale sweep', (tester) async {
      const locales = ['en', 'zh_CN', 'ja', 'ko'];
      for (final tag in locales) {
        final parts = tag.split('_');
        final locale = parts.length == 2
            ? Locale(parts[0], parts[1])
            : Locale(parts[0]);
        await tester.pumpWidget(
          _wrap(CocotbLogEntryRow(entry: _entry()), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'locale $tag');
      }
    });

    testWidgets('renders the message text', (tester) async {
      await tester.pumpWidget(
        _wrap(CocotbLogEntryRow(entry: _entry(message: 'Reset complete'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reset complete'), findsOneWidget);
    });

    testWidgets('test result entry shows passed badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CocotbLogEntryRow(
            entry: _entry(
              isTestResult: true,
              testPassed: true,
              message: 'test_x passed',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.cocotbLogTestPassed), findsOneWidget);
    });

    testWidgets('test result entry shows failed badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CocotbLogEntryRow(
            entry: _entry(
              isTestResult: true,
              testPassed: false,
              message: 'test_x failed',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.cocotbLogTestFailed), findsOneWidget);
    });

    testWidgets('tap places primary cursor at entry time', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Keep the provider alive for the duration of the test so the state
      // change isn't lost to auto-dispose between the action and assertion.
      final sub = container.listen(
        cursorStateProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: CocotbLogEntryRow(entry: _entry(ticks: 250)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Invoke the InkWell's onTap directly to avoid gesture-arena
      // ambiguity from the nested GestureDetector that handles secondary
      // taps.
      final inkWell = tester.widget<InkWell>(
        find
            .descendant(
              of: find.byType(CocotbLogEntryRow),
              matching: find.byType(InkWell),
            )
            .first,
      );
      inkWell.onTap!.call();
      await tester.pumpAndSettle();
      expect(
        container.read(cursorStateProvider).primaryCursorTime,
        250,
      );
    });

    testWidgets('row has minimum 44pt touch target', (tester) async {
      await tester.pumpWidget(_wrap(CocotbLogEntryRow(entry: _entry())));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(CocotbLogEntryRow));
      expect(size.height, greaterThanOrEqualTo(44.0));
    });

    testWidgets('null timestamp disables tap', (tester) async {
      await tester.pumpWidget(
        _wrap(CocotbLogEntryRow(entry: _entry(ticks: null))),
      );
      await tester.pumpAndSettle();
      // The InkWell onTap is null when no ticks — but tapping should still
      // not throw.
      await tester.tap(find.byType(CocotbLogEntryRow));
      expect(tester.takeException(), isNull);
    });
  });
}
