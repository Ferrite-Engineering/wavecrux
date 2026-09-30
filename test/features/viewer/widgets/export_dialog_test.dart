// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/widgets/export_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

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

Future<ExportDialogResult?> _showDialog(
  WidgetTester tester, {
  Locale? locale,
}) async {
  ExportDialogResult? result;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await ExportDialog.show(context);
          },
          child: const Text('Open'),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('ExportDialog — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exception', (tester) async {
        await _showDialog(tester, locale: locale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ExportDialog — static structure', () {
    testWidgets('shows format section with VCD/PNG/SVG options', (
      tester,
    ) async {
      await _showDialog(tester);
      expect(find.text('VCD (Value Change Dump)'), findsOneWidget);
      expect(find.text('PNG Image'), findsOneWidget);
      expect(find.text('SVG Vector'), findsOneWidget);
    });

    testWidgets('shows time range section', (tester) async {
      await _showDialog(tester);
      expect(find.text('Visible Range'), findsWidgets);
      expect(find.text('Full Simulation'), findsOneWidget);
    });

    testWidgets('shows signals section', (tester) async {
      await _showDialog(tester);
      expect(find.text('Visible Signals Only'), findsOneWidget);
      expect(find.text('All Loaded Signals'), findsOneWidget);
    });

    testWidgets('Cancel and Export buttons are present', (tester) async {
      await _showDialog(tester);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Export…'), findsOneWidget);
    });

    testWidgets('resolution section hidden for VCD (default)', (tester) async {
      await _showDialog(tester);
      expect(find.text('Resolution'), findsNothing);
    });

    testWidgets('resolution section appears when PNG selected', (tester) async {
      await _showDialog(tester);
      await tester.tap(find.text('PNG Image'));
      await tester.pumpAndSettle();
      expect(find.text('Resolution'), findsOneWidget);
      expect(find.text('1× (screen)'), findsOneWidget);
      expect(find.text('2× (retina)'), findsOneWidget);
      expect(find.text('3× (high-DPI)'), findsOneWidget);
    });

    testWidgets('resolution section hidden for SVG', (tester) async {
      await _showDialog(tester);
      await tester.tap(find.text('SVG Vector'));
      await tester.pumpAndSettle();
      expect(find.text('Resolution'), findsNothing);
    });
  });

  // Two tests below pump a 1000 dp-tall surface. The dialog grew a fourth
  // format option (SAIF) and no longer fits the default 800x600 test viewport
  // alongside its actions row. That is a genuine short-window concern, not
  // only a test artifact — see the manual check in the verification checklist
  // — but it is a layout question for the dialog rather than something these
  // result-value tests should be asserting.
  group('ExportDialog — result values', () {
    testWidgets('Cancel returns null', (tester) async {
      ExportDialogResult? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await ExportDialog.show(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('Export with defaults returns VCD/visible/visible/2x', (
      tester,
    ) async {
      ExportDialogResult? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await ExportDialog.show(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.format, ExportFormat.vcd);
      expect(result!.timeRange, ExportTimeRange.visible);
      expect(result!.signals, ExportSignals.visible);
      expect(result!.pixelRatio, 2.0);
    });

    testWidgets('selecting PNG and 3x returns correct result', (tester) async {
      ExportDialogResult? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await ExportDialog.show(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PNG Image'));
      await tester.pumpAndSettle();
      final tile3x = find.text('3× (high-DPI)');
      await tester.ensureVisible(tile3x);
      await tester.tap(tile3x);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();

      expect(result!.format, ExportFormat.png);
      expect(result!.pixelRatio, 3.0);
    });

    testWidgets('selecting Full Simulation time range returns correct result', (
      tester,
    ) async {
      ExportDialogResult? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await ExportDialog.show(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Full Simulation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();

      expect(result!.timeRange, ExportTimeRange.full);
    });

    testWidgets('selecting All Loaded Signals returns correct result', (
      tester,
    ) async {
      ExportDialogResult? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await ExportDialog.show(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('All Loaded Signals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();

      expect(result!.signals, ExportSignals.all);
    });
  });
}
