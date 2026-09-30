// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_severity_chips.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

class _PreloadedLog extends CocotbLog {
  _PreloadedLog(this._initial);
  final CocotbLogFile? _initial;
  @override
  CocotbLogFile? build() => _initial;
}

CocotbLogFile _file({
  Map<CocotbLogSeverity, int> counts = const {
    CocotbLogSeverity.info: 5,
    CocotbLogSeverity.error: 2,
  },
}) => CocotbLogFile(
  filePath: '/tmp/run.log',
  entries: const [],
  testNames: const [],
  severityCounts: counts,
  testResults: const {},
);

Widget _wrap({CocotbLogFile? file, Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: [
        cocotbLogProvider.overrideWith(() => _PreloadedLog(file)),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: CocotbSeverityChips()),
      ),
    );

void main() {
  group('CocotbSeverityChips', () {
    testWidgets('locale sweep', (tester) async {
      const locales = ['en', 'zh_CN', 'ja', 'ko'];
      for (final tag in locales) {
        final parts = tag.split('_');
        final locale = parts.length == 2
            ? Locale(parts[0], parts[1])
            : Locale(parts[0]);
        await tester.pumpWidget(_wrap(file: _file(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'locale $tag');
      }
    });

    testWidgets('renders one chip per severity', (tester) async {
      await tester.pumpWidget(_wrap(file: _file()));
      await tester.pumpAndSettle();
      expect(
        find.byType(FilterChip),
        findsNWidgets(CocotbLogSeverity.values.length),
        reason:
            'one chip per severity, derived rather than hardcoded so '
            'adding a level does not silently drop its chip',
      );
    });

    testWidgets('chip displays severity count', (tester) async {
      await tester.pumpWidget(_wrap(file: _file()));
      await tester.pumpAndSettle();
      // Info has 5 entries; chip text is "Info (5)"
      expect(find.textContaining('(5)'), findsOneWidget);
      expect(find.textContaining('(2)'), findsOneWidget);
    });

    testWidgets('tapping chip toggles severity in filter', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cocotbLogProvider.overrideWith(() => _PreloadedLog(_file())),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  container = ProviderScope.containerOf(ctx);
                  return const CocotbSeverityChips();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Initially no severities selected.
      expect(
        container.read(cocotbFilterProvider).severityFilter,
        isEmpty,
      );
      // Tap the first chip. The enum is ordered least- to most-severe and
      // the chip row follows it, so this is TRACE.
      await tester.tap(find.byType(FilterChip).first);
      await tester.pumpAndSettle();
      expect(
        container.read(cocotbFilterProvider).severityFilter,
        contains(CocotbLogSeverity.trace),
      );
    });

    testWidgets('renders zero count when no log loaded', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // All five chips show "(0)".
      expect(
        find.textContaining('(0)'),
        findsNWidgets(CocotbLogSeverity.values.length),
      );
    });
  });
}
