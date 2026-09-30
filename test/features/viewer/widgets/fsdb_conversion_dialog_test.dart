// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/widgets/fsdb_conversion_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform/fsdb_conversion_service.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {Locale? locale}) => MaterialApp(
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  locale: locale,
  home: Scaffold(body: child),
);

/// Pumps a [MaterialApp] with a button that opens [FsdbConversionDialog] via
/// [FsdbConversionDialog.show], taps the button, and settles animations.
/// Returns void so the caller can interact with the open dialog without Dart
/// chaining the dialog's result future.
Future<void> _showViaButton(
  WidgetTester tester, {
  required FsdbConversionService service,
  String fsdbPath = '/tmp/sim.fsdb',
  String toolPath = '/synopsys/bin/fsdb2vcd',
  Locale? locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => FsdbConversionDialog.show(
            context,
            fsdbPath: fsdbPath,
            toolPath: toolPath,
            service: service,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('FsdbConversionDialog — locale sweep (direct render)', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('renders without exception in ${locale.languageCode}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const FsdbConversionDialog(
              fsdbPath: '/tmp/sim.fsdb',
              toolPath: '/synopsys/bin/fsdb2vcd',
              service: FsdbConversionService(),
            ),
            locale: locale,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FsdbConversionDialog — confirm view (direct render)', () {
    testWidgets('shows dialog title', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FsdbConversionDialog(
            fsdbPath: '/tmp/sim.fsdb',
            toolPath: '/synopsys/bin/fsdb2vcd',
            service: FsdbConversionService(),
          ),
        ),
      );
      expect(find.text('Convert FSDB File'), findsOneWidget);
    });

    testWidgets('displays the tool path', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FsdbConversionDialog(
            fsdbPath: '/tmp/sim.fsdb',
            toolPath: '/synopsys/bin/fsdb2vcd',
            service: FsdbConversionService(),
          ),
        ),
      );
      expect(find.textContaining('/synopsys/bin/fsdb2vcd'), findsOneWidget);
    });

    testWidgets('shows Cancel and Convert buttons', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FsdbConversionDialog(
            fsdbPath: '/tmp/sim.fsdb',
            toolPath: '/synopsys/bin/fsdb2vcd',
            service: FsdbConversionService(),
          ),
        ),
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Convert'), findsOneWidget);
    });
  });

  group('FsdbConversionDialog — via show() helper', () {
    testWidgets('Cancel button pops dialog with null', (tester) async {
      late Future<String?> dialogResult;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                dialogResult = FsdbConversionDialog.show(
                  context,
                  fsdbPath: '/tmp/sim.fsdb',
                  toolPath: '/synopsys/bin/fsdb2vcd',
                  service: const FsdbConversionService(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await dialogResult, isNull);
    });

    testWidgets('shows progress indicator after tapping Convert', (
      tester,
    ) async {
      // Completer blocks the process runner so the converting state persists
      // long enough for the assertion.
      final blocker = Completer<void>();
      final service = FsdbConversionService(
        executableLocator: (name) => '/fake/$name',
        processRunner: (_, _) async {
          await blocker.future;
          // Throw so there is no real file IO after the blocker is released.
          throw const FsdbConversionException('test cancelled');
        },
      );

      await _showViaButton(tester, service: service);

      await tester.tap(find.text('Convert'));
      await tester
          .pump(); // one frame → converting state + LinearProgressIndicator

      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Release the pending future before the test ends.  Without this the
      // unresolved future keeps the isolate alive and teardown tries to
      // pumpAndSettle, which loops forever on the LinearProgressIndicator's
      // indeterminate animation.
      blocker.complete();
      await tester.pump(); // processRunner throws → catch → setState(error)
      await tester.pump(); // frame: error state, no LinearProgressIndicator
    });

    testWidgets('shows error view when conversion fails', (tester) async {
      // Use the same Completer-based pattern as "shows progress indicator":
      // explicitly control when the mock process runner resolves so that the
      // fake-async pump cycle can drain the microtask reliably.
      final processCompleter = Completer<ProcessResult>();
      final service = FsdbConversionService(
        executableLocator: (name) => '/fake/$name',
        processRunner: (_, _) => processCompleter.future,
      );

      await _showViaButton(tester, service: service);

      await tester.tap(find.text('Convert'));
      await tester.pump(); // converting state (LinearProgressIndicator visible)

      // Complete with an exit-code-1 result to trigger the error path.
      processCompleter.complete(ProcessResult(1, 1, '', 'license error'));
      await tester.pump(); // microtask: exitCode=1 → throw → setState(error)
      await tester.pump(); // frame: error state rendered

      expect(find.textContaining('Conversion failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('FsdbConversionDialog.showNotFound', () {
    testWidgets('shows not-found title and close button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => FsdbConversionDialog.showNotFound(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Synopsys Tools Not Found'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Close button dismisses the dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => FsdbConversionDialog.showNotFound(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Synopsys Tools Not Found'), findsNothing);
    });

    testWidgets('locale sweep — not-found dialog renders in all locales', (
      tester,
    ) async {
      for (final locale in L10N.supportedLocales) {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            locale: locale,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => FsdbConversionDialog.showNotFound(context),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
      }
    });
  });

  group('FsdbConversionDialog.showWebUnsupported', () {
    testWidgets('shows the web-unsupported title and close button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => FsdbConversionDialog.showWebUnsupported(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('FSDB needs the desktop app'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      // The body steers the user to the desktop app / a converted file.
      expect(find.textContaining('desktop app'), findsWidgets);
    });

    testWidgets('Close dismisses the web-unsupported dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => FsdbConversionDialog.showWebUnsupported(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('FSDB needs the desktop app'), findsNothing);
    });

    testWidgets(
      'locale sweep — web-unsupported dialog renders in all locales',
      (tester) async {
        for (final locale in L10N.supportedLocales) {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              locale: locale,
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      FsdbConversionDialog.showWebUnsupported(context),
                  child: const Text('open'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            ),
          );
          await tester.pumpAndSettle();
        }
      },
    );
  });
}
