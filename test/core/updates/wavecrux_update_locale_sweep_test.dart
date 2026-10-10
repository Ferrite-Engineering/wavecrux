// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/updates/wavecrux_update_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Renders the shared update banner and the manual-check toasts through
/// WaveCrux's own [WavecruxUpdateStrings] adapter under the CJK locales, so a
/// missing glyph-width assumption, a broken placeholder or an overflow in a
/// translated string fails here rather than in a user's window.
const _locales = <Locale>[Locale('zh', 'CN'), Locale('ja'), Locale('ko')];

final _config = CruxUpdateConfig(
  productName: 'WaveCrux',
  manifestUri: 'https://updates.example.test/manifest.json',
  downloadPageUri: 'https://example.test/download',
);

const _buildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.2',
  dartSdkVersion: '3.12.2',
);

class _StubUpdateStatusNotifier extends UpdateStatusNotifier {
  _StubUpdateStatusNotifier(this._state);

  final UpdateStatus _state;

  @override
  UpdateStatus build() => _state;

  @override
  Future<void> runScheduledCheck() async {}

  /// When set, [checkNow] blocks on it so the in-flight toast is observable.
  Completer<void>? gate;

  @override
  Future<void> checkNow() async {
    await gate?.future;
  }
}

/// Binds [WavecruxUpdateStrings] from the ambient [L10N], as `app.dart` does.
Widget _host(
  Locale locale,
  UpdateStatus status,
  Widget Function() body, {
  _StubUpdateStatusNotifier? notifier,
}) {
  return ProviderScope(
    overrides: [
      cruxUpdateConfigProvider.overrideWithValue(_config),
      updateStatusProvider.overrideWith(
        () => notifier ?? _StubUpdateStatusNotifier(status),
      ),
      updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
      updateUrlLauncherProvider.overrideWithValue((_) async => true),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: L10N.supportedLocales,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => ProviderScope(
          overrides: [
            cruxUpdateStringsProvider.overrideWithValue(
              WavecruxUpdateStrings(L10N.of(context)),
            ),
          ],
          child: Scaffold(body: body()),
        ),
      ),
    ),
  );
}

void main() {
  for (final locale in _locales) {
    group('update banner and toasts under $locale', () {
      testWidgets('the available banner renders translated, without overflow', (
        tester,
      ) async {
        const status = UpdateStatusAvailable(
          UpdateInfo(
            version: '1.2.0',
            changelogUrl: 'https://example.test/releases/1.2.0',
          ),
        );
        await tester.pumpWidget(
          _host(
            locale,
            status,
            () => const UpdateBanner(child: Text('routed-content')),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(locale);
        expect(find.text(l10n.updateBannerMessage('1.2.0')), findsOneWidget);
        expect(find.text(l10n.updateViewChangesAction), findsOneWidget);
        expect(find.text(l10n.updateNowAction), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.updateDismissLabel), findsOneWidget);
        expect(find.text('routed-content'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final outcome in <String, UpdateStatus>{
        'current': const UpdateStatusCurrent(),
        'error': const UpdateStatusError(),
      }.entries) {
        testWidgets('the ${outcome.key} check toasts render translated', (
          tester,
        ) async {
          await tester.pumpWidget(
            _host(
              locale,
              outcome.value,
              () => Consumer(
                builder: (context, ref, _) {
                  ref.watch(updateBuildInfoProvider);
                  return Center(
                    child: ElevatedButton(
                      onPressed: () => runManualUpdateCheck(context, ref),
                      child: const Text('check'),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pump();
          await tester.tap(find.text('check'));
          // First frame shows the in-flight toast.
          await tester.pump();
          final l10n = await L10N.delegate.load(locale);
          // Let the async check resolve and the outcome toast replace it.
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));

          final expected = outcome.key == 'current'
              ? l10n.updateCheckUpToDate('1.2.3')
              : l10n.updateCheckFailed;
          expect(find.text(expected), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('the in-flight toast renders translated', (tester) async {
        final notifier = _StubUpdateStatusNotifier(const UpdateStatusChecking())
          ..gate = Completer<void>();
        await tester.pumpWidget(
          _host(
            locale,
            const UpdateStatusChecking(),
            () => Consumer(
              builder: (context, ref, _) {
                ref.watch(updateBuildInfoProvider);
                return Center(
                  child: ElevatedButton(
                    onPressed: () => runManualUpdateCheck(context, ref),
                    child: const Text('check'),
                  ),
                );
              },
            ),
            notifier: notifier,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('check'));
        await tester.pump();
        final l10n = await L10N.delegate.load(locale);
        expect(find.text(l10n.updateCheckInProgress), findsOneWidget);
        notifier.gate!.complete();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });
  }
}
