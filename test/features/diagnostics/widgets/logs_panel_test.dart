// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/diagnostics/widgets/logs_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

CruxIssueReporterLogBuffer _seeded() {
  return CruxIssueReporterLogBuffer(capacity: 50)
    ..add(
      CruxIssueLogEntry(
        timestamp: DateTime.utc(2026, 6, 14, 1, 2, 3),
        level: Level.INFO,
        loggerName: 'wavecrux.test',
        message: 'info-msg',
      ),
    )
    ..add(
      CruxIssueLogEntry(
        timestamp: DateTime.utc(2026, 6, 14, 1, 2, 4),
        level: Level.SEVERE,
        loggerName: 'wavecrux.test',
        message: 'severe-msg',
      ),
    );
}

Widget _wrap(
  CruxIssueReporterLogBuffer buffer, {
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [cruxIssueReporterLogBufferProvider.overrideWithValue(buffer)],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(child: LogsPanel()),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LogsPanel — locale sweep', () {
    const locales = [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];
    for (final locale in locales) {
      testWidgets('renders without exception ($locale)', (tester) async {
        await tester.pumpWidget(_wrap(_seeded(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LogsPanel), findsOneWidget);
      });
    }
  });

  testWidgets('default (Normal) filter shows INFO and SEVERE', (tester) async {
    await tester.pumpWidget(_wrap(_seeded()));
    await tester.pumpAndSettle();
    expect(find.textContaining('info-msg'), findsOneWidget);
    expect(find.textContaining('severe-msg'), findsOneWidget);
  });

  testWidgets('selecting Quiet hides INFO, keeps SEVERE', (tester) async {
    await tester.pumpWidget(_wrap(_seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logsPanelLevelFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quiet').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('info-msg'), findsNothing);
    expect(find.textContaining('severe-msg'), findsOneWidget);
  });

  testWidgets('clear empties the buffer and shows the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_seeded()));
    await tester.pumpAndSettle();
    expect(find.textContaining('severe-msg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logsPanelClear')));
    await tester.pumpAndSettle();

    final l10n = L10N.of(tester.element(find.byType(LogsPanel)));
    expect(find.textContaining('severe-msg'), findsNothing);
    expect(find.text(l10n.logsPanelEmpty), findsOneWidget);
  });

  testWidgets('copy writes the visible log lines and confirms via snackbar', (
    tester,
  ) async {
    // Capture the clipboard write without relying on a platform getData
    // responder (which the test binding does not provide).
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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

    await tester.pumpWidget(_wrap(_seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logsPanelCopy')));
    await tester.pump(); // run _copy through the clipboard await
    await tester.pump(const Duration(milliseconds: 300)); // snackbar slide-in

    expect(copied, contains('severe-msg'));
    expect(copied, contains('info-msg'));
    final l10n = L10N.of(tester.element(find.byType(LogsPanel)));
    expect(find.text(l10n.logsPanelCopied), findsOneWidget);

    // Flush the snackbar's auto-dismiss timer so teardown sees no pending timer.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
