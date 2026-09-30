// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform/legacy_conversion_controller.dart';
import 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/widgets/legacy_conversion_progress_dialog.dart';

/// Pump a stripped-down host that exposes the dialog via a single button. The
/// dialog is `showDialog`-pushed onto the host's Navigator so the same hook
/// the production open path uses is exercised. The dialog's auto-dismiss
/// listener relies on the [legacyConversionControllerProvider] transition
/// from inProgress to idle.
Future<void> _pumpHost(
  WidgetTester tester, {
  required Locale locale,
  required ProviderContainer container,
  Duration showAfter = const Duration(milliseconds: 250),
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              return Center(
                child: ElevatedButton(
                  key: const Key('openDialog'),
                  onPressed: () {
                    unawaited(
                      LegacyConversionProgressDialog.showIfNeeded(
                        context: context,
                        ref: ref,
                        showAfter: showAfter,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      // The dialog reads MobileMetrics off the device class; pin desktop so
      // the touch-target conformance check resolves to a deterministic 44 dp
      // baseline regardless of the host's MediaQuery.
      deviceClassProvider.overrideWith((ref) => DeviceClass.desktop),
    ],
  );
  return container;
}

void main() {
  group('LegacyConversionProgressDialog', () {
    testWidgets(
      'appears for a slow conversion (controller still inProgress past '
      'the show-after debounce)',
      (tester) async {
        final container = _container();
        addTearDown(container.dispose);

        await _pumpHost(
          tester,
          locale: const Locale('en'),
          container: container,
          showAfter: const Duration(milliseconds: 5),
        );

        // Simulate a conversion start before triggering the dialog. The
        // host's button calls showIfNeeded(), which polls inProgress after
        // showAfter — so the controller must already be in-flight when the
        // poll fires.
        container
            .read(legacyConversionControllerProvider.notifier)
            .begin(sourcePath: '/tmp/slow.lxt2', origin: WaveformFormat.lxt2);

        await tester.tap(find.byKey(const Key('openDialog')));
        // Pump past the debounce and through the showDialog frame so the
        // dialog widget is actually inserted into the tree.
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();

        expect(find.text('Converting legacy waveform file'), findsOneWidget);
        expect(find.text('Converting LXT2 to FST…'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Drive the controller forward to verify auto-dismiss on idle.
        container
            .read(legacyConversionControllerProvider.notifier)
            .completeSuccess();
        await tester.pumpAndSettle();
        expect(find.text('Converting legacy waveform file'), findsNothing);
      },
    );

    testWidgets('stays hidden when conversion finishes before the debounce '
        '(< 250 ms file)', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pumpHost(
        tester,
        locale: const Locale('en'),
        container: container,
        showAfter: const Duration(milliseconds: 50),
      );

      final notifier =
          container.read(legacyConversionControllerProvider.notifier)..begin(
            sourcePath: '/tmp/fast.lxt2',
            origin: WaveformFormat.lxt2,
          );

      await tester.tap(find.byKey(const Key('openDialog')));
      // Conversion finishes BEFORE the debounce expires.
      await tester.pump(const Duration(milliseconds: 10));
      notifier.completeSuccess();
      // Run past the debounce so showIfNeeded re-checks.
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();

      // No dialog ever appears.
      expect(find.text('Converting legacy waveform file'), findsNothing);
    });

    testWidgets('Cancel invokes the controller hook and dismisses', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pumpHost(
        tester,
        locale: const Locale('en'),
        container: container,
        showAfter: const Duration(milliseconds: 5),
      );

      var cancelHookCalls = 0;
      void hook() {
        cancelHookCalls++;
      }

      container.read(legacyConversionControllerProvider.notifier)
        ..begin(
          sourcePath: '/tmp/cancel.lxt2',
          origin: WaveformFormat.lxt2,
        )
        ..cancelHook = hook;

      await tester.tap(find.byKey(const Key('openDialog')));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();

      // Cancel button → controller.cancel → installed hook fires + state
      // returns to idle + dialog auto-dismisses.
      await tester.tap(find.byKey(const Key('legacyConversionCancelButton')));
      await tester.pumpAndSettle();

      expect(cancelHookCalls, 1);
      expect(
        container.read(legacyConversionControllerProvider),
        LegacyConversionState.idle,
      );
      expect(find.text('Converting legacy waveform file'), findsNothing);
    });

    testWidgets('progress bar value tracks the controller state', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pumpHost(
        tester,
        locale: const Locale('en'),
        container: container,
        showAfter: const Duration(milliseconds: 5),
      );

      final notifier =
          container.read(legacyConversionControllerProvider.notifier)..begin(
            sourcePath: '/tmp/p.lxt2',
            origin: WaveformFormat.lxt2,
          );

      await tester.tap(find.byKey(const Key('openDialog')));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();

      // Indeterminate (no progress event yet).
      var bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull);

      notifier.updateProgress(const ConversionProgress(done: 1, total: 4));
      await tester.pump();
      bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.25, 1e-9));

      notifier.completeSuccess();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'Cancel button is at least 44×44 dp (touch-target compliance)',
      (tester) async {
        final container = _container();
        addTearDown(container.dispose);

        await _pumpHost(
          tester,
          locale: const Locale('en'),
          container: container,
          showAfter: const Duration(milliseconds: 5),
        );

        container
            .read(legacyConversionControllerProvider.notifier)
            .begin(sourcePath: '/tmp/t.lxt2', origin: WaveformFormat.lxt2);

        await tester.tap(find.byKey(const Key('openDialog')));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();

        final cancelSize = tester.getSize(
          find.byKey(const Key('legacyConversionCancelButton')),
        );
        expect(cancelSize.width, greaterThanOrEqualTo(44));
        expect(cancelSize.height, greaterThanOrEqualTo(44));

        container
            .read(legacyConversionControllerProvider.notifier)
            .completeSuccess();
        await tester.pumpAndSettle();
      },
    );

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        Locale.fromSubtags(languageCode: 'zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders in ${locale.toLanguageTag()} without exceptions', (
          tester,
        ) async {
          final container = _container();
          addTearDown(container.dispose);

          await _pumpHost(
            tester,
            locale: locale,
            container: container,
            showAfter: const Duration(milliseconds: 5),
          );

          container
              .read(legacyConversionControllerProvider.notifier)
              .begin(
                sourcePath: '/tmp/locale.lxt2',
                origin: WaveformFormat.lxt2,
              );

          await tester.tap(find.byKey(const Key('openDialog')));
          await tester.pump(const Duration(milliseconds: 20));
          await tester.pump();

          expect(tester.takeException(), isNull);

          container
              .read(legacyConversionControllerProvider.notifier)
              .completeSuccess();
          await tester.pumpAndSettle();
        });
      }
    });
  });
}
